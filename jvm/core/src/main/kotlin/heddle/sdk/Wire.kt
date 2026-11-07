// The Heddle v1 wire frame (WireEnvelope) and its strict codec.
//
// Mirrors heddle/src/heddle/core/envelope.py. Every message on the bus is a
// frame: identity, causation, two timestamps, a `payload_type`
// discriminator, the typed body in `payload`, and the Middleware Lane
// (top-level `_`-prefixed keys, carried as opaque JSON).
//
// Parsing has two steps, as upstream: validate the frame, then pick the body
// model by `payload_type` and validate the body. Errors carry the layer that
// rejected the message (frame / body / dispatch), matching the `rejected_at`
// column of schemas/v1/fixtures/manifest.json.
//
// The codec reads a Jackson tree and checks every field by hand, so the
// rules are identical to the .NET and Swift SDKs and Jackson's lenient
// binding (floats truncated to ints, scalars coerced to strings, epoch
// numbers accepted as Instants) never touches the wire. See
// schemas/v1/fixtures/README.md for the rules.

package heddle.sdk

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.node.JsonNodeFactory
import com.fasterxml.jackson.databind.node.ObjectNode
import com.fasterxml.jackson.module.kotlin.convertValue
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

/** The layer at which an inbound message was rejected. */
enum class WireLayer {
    /** The frame is invalid (missing or ill-typed field, unknown non-`_` key, bad timestamp). */
    FRAME,

    /** The frame is valid, but the body fails its model. */
    BODY,

    /** The frame is valid, but no body model is registered for its `payload_type`. */
    DISPATCH,
}

/** An inbound message that does not satisfy the v1 wire contract. */
class WireFormatException(val layer: WireLayer, message: String, cause: Throwable? = null) :
    Exception("${layer.name.lowercase()}: $message", cause)

/** The `payload_type` discriminators this SDK registers. */
object PayloadTypes {
    const val TASK_MESSAGE = "core.TaskMessage"
    const val TASK_RESULT = "core.TaskResult"
    const val ORCHESTRATOR_GOAL = "core.OrchestratorGoal"

    /** Every registered discriminator. Anything else is a dispatch rejection. */
    @JvmField
    val ALL: List<String> = listOf(TASK_MESSAGE, TASK_RESULT, ORCHESTRATOR_GOAL)
}

/** A typed v1 body. [TaskMessage], [TaskResult] and [OrchestratorGoal] implement it. */
sealed interface WireBody {
    val payloadType: String
}

/**
 * The generic frame every Heddle message rides. Use [HeddleWire] to build and
 * read frames.
 *
 * [lane] is the Middleware Lane: every top-level `_`-prefixed key, as opaque
 * JSON. Actors that publish a message because of an inbound one copy it onto
 * the new frame (heddle DESIGN_INVARIANTS #22).
 */
data class WireEnvelope(
    val messageId: String = UUID.randomUUID().toString(),
    val payloadType: String,
    val payload: ObjectNode,
    val origin: String? = null,
    val correlationId: String? = null,
    val causationId: String? = null,
    /** Domain time: when the thing this message is about happened. */
    val occurredAt: Instant,
    /** Bus time: when this message was recorded onto the transport. */
    val recordedAt: Instant,
    val lane: Map<String, JsonNode> = emptyMap(),
)

/** Strict reader and writer for the v1 wire frame and the core bodies. */
object HeddleWire {
    private val frameFields = setOf(
        "message_id", "payload_type", "payload", "origin", "correlation_id",
        "causation_id", "occurred_at", "recorded_at",
    )

    // RFC 3339 date-time with a mandatory offset (envelope.py `_RFC3339`).
    private val rfc3339 = Regex(
        """(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(?:([Zz])|([+-])(\d{2}):(\d{2}))"""
    )

    private val format = DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss.SSSSSS'Z'").withZone(ZoneOffset.UTC)

    private val nodes = JsonNodeFactory.instance

    // A plain mapper for the wire: no NON_NULL inclusion (opaque JSON keeps
    // its nulls) and no binding, only tree reading and writing.
    private val mapper = jacksonObjectMapper().apply {
        // Reject `{...} trailing`, as Python, .NET and Swift do.
        configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_TRAILING_TOKENS, true)
    }

    // ------------------------------------------------------------------
    // Frame
    // ------------------------------------------------------------------

    /** Two-step parse: the frame, then the body chosen by `payload_type`. */
    @JvmStatic
    @Throws(WireFormatException::class)
    fun parse(data: ByteArray): Pair<WireEnvelope, WireBody> {
        val envelope = parseFrame(data)
        return envelope to parseBody(envelope)
    }

    /** Validate the frame only. The body stays unvalidated JSON. */
    @JvmStatic
    @Throws(WireFormatException::class)
    fun parseFrame(data: ByteArray): WireEnvelope {
        val root = try {
            mapper.readTree(data)
        } catch (e: Exception) {
            throw WireFormatException(WireLayer.FRAME, "message is not valid JSON", e)
        }
        if (root !is ObjectNode) throw WireFormatException(WireLayer.FRAME, "message is not a JSON object")
        return parseFrame(root)
    }

    /** Validate a frame that is already a JSON object. */
    @JvmStatic
    @Throws(WireFormatException::class)
    fun parseFrame(root: ObjectNode): WireEnvelope {
        val keys = root.fieldNames().asSequence().toList()
        val unknown = keys.filter { !it.startsWith("_") && it !in frameFields }.sorted()
        if (unknown.isNotEmpty()) {
            throw WireFormatException(
                WireLayer.FRAME,
                "unknown top-level key(s) $unknown; only declared fields and `_`-prefixed Middleware-Lane keys are accepted",
            )
        }
        val f = Fields(root, WireLayer.FRAME)
        if (!root.has("payload_type")) throw WireFormatException(WireLayer.FRAME, "payload_type is required")
        if (!root.has("payload")) throw WireFormatException(WireLayer.FRAME, "payload is required")

        val hasOccurred = root.has("occurred_at")
        val hasRecorded = root.has("recorded_at")
        val occurred: Instant
        val recorded: Instant
        if (!hasOccurred && !hasRecorded) {
            occurred = now()
            recorded = occurred
        } else {
            // A present key must be a valid timestamp: an explicit null is not "absent".
            occurred = timestamp(f, if (hasOccurred) "occurred_at" else "recorded_at")
            recorded = if (hasRecorded) timestamp(f, "recorded_at") else occurred
        }

        return WireEnvelope(
            messageId = if (root.has("message_id")) f.string("message_id") else UUID.randomUUID().toString(),
            payloadType = f.string("payload_type"),
            payload = f.obj("payload").deepCopy(),
            origin = f.optionalString("origin"),
            correlationId = f.optionalString("correlation_id"),
            causationId = f.optionalString("causation_id"),
            occurredAt = occurred,
            recordedAt = recorded,
            lane = keys.filter { it.startsWith("_") }.associateWith { root.get(it).deepCopy<JsonNode>() },
        )
    }

    /** Validate the body for the frame's `payload_type` (step two). */
    @JvmStatic
    @Throws(WireFormatException::class)
    fun parseBody(envelope: WireEnvelope): WireBody {
        val f = Fields(envelope.payload, WireLayer.BODY)
        return when (envelope.payloadType) {
            PayloadTypes.TASK_MESSAGE -> TaskMessage(
                taskId = if (f.has("task_id")) f.string("task_id") else UUID.randomUUID().toString(),
                parentTaskId = f.optionalString("parent_task_id"),
                workerType = f.string("worker_type"),
                input = f.map("input"),
                modelTier = if (f.has("model_tier")) f.enumValue("model_tier", ModelTier.values()) else ModelTier.STANDARD,
                priority = if (f.has("priority")) f.enumValue("priority", TaskPriority.values()) else TaskPriority.NORMAL,
                requestId = f.optionalString("request_id"),
                metadata = if (f.has("metadata")) f.map("metadata") else emptyMap(),
            )
            PayloadTypes.TASK_RESULT -> TaskResult(
                taskId = f.string("task_id"),
                parentTaskId = f.optionalString("parent_task_id"),
                workerType = f.string("worker_type"),
                status = f.enumValue("status", TaskStatus.values()),
                output = if (f.isNullOrAbsent("output")) null else f.map("output"),
                error = f.optionalString("error"),
                modelUsed = f.optionalString("model_used"),
                tokenUsage = if (f.has("token_usage")) {
                    f.obj("token_usage").fields().asSequence().associate { (k, v) -> k to integer(v, "token_usage.$k") }
                } else {
                    emptyMap()
                },
                metadata = if (f.has("metadata")) f.map("metadata") else emptyMap(),
                processingTimeMs = if (f.has("processing_time_ms")) {
                    integer(envelope.payload.get("processing_time_ms"), "processing_time_ms")
                } else {
                    0L
                },
            )
            PayloadTypes.ORCHESTRATOR_GOAL -> OrchestratorGoal(
                goalId = if (f.has("goal_id")) f.string("goal_id") else UUID.randomUUID().toString(),
                instruction = f.string("instruction"),
                context = if (f.has("context")) f.map("context") else emptyMap(),
                requestId = f.optionalString("request_id"),
                priority = if (f.has("priority")) f.enumValue("priority", TaskPriority.values()) else TaskPriority.NORMAL,
            )
            else -> throw WireFormatException(
                WireLayer.DISPATCH,
                "no payload model registered for '${envelope.payloadType}'",
            )
        }
    }

    /**
     * Build a frame around a typed body. Both timestamps take one fresh
     * instant. [lane] is copied onto the frame; every key must start with `_`.
     */
    @JvmStatic
    @JvmOverloads
    fun wrap(
        body: WireBody,
        lane: Map<String, JsonNode> = emptyMap(),
        origin: String? = null,
        correlationId: String? = null,
        causationId: String? = null,
    ): WireEnvelope {
        require(lane.keys.all { it.startsWith("_") }) { "Middleware-Lane keys must start with '_'" }
        val now = now()
        return WireEnvelope(
            payloadType = body.payloadType,
            payload = bodyObject(body),
            origin = origin,
            correlationId = correlationId,
            causationId = causationId,
            occurredAt = now,
            recordedAt = now,
            lane = lane.mapValues { it.value.deepCopy<JsonNode>() },
        )
    }

    /** The frame as a JSON object. Every field is written, nulls included. */
    @JvmStatic
    fun toJsonObject(envelope: WireEnvelope): ObjectNode {
        val root = nodes.objectNode()
        root.put("message_id", envelope.messageId)
        root.put("payload_type", envelope.payloadType)
        root.set<JsonNode>("payload", envelope.payload.deepCopy())
        root.put("origin", envelope.origin)
        root.put("correlation_id", envelope.correlationId)
        root.put("causation_id", envelope.causationId)
        root.put("occurred_at", formatTimestamp(envelope.occurredAt))
        root.put("recorded_at", formatTimestamp(envelope.recordedAt))
        envelope.lane.forEach { (k, v) -> root.set<JsonNode>(k, v.deepCopy()) }
        return root
    }

    /** The frame as UTF-8 JSON bytes, ready to publish. */
    @JvmStatic
    fun serialize(envelope: WireEnvelope): ByteArray = mapper.writeValueAsBytes(toJsonObject(envelope))

    /** The body as JSON, every field written. */
    @JvmStatic
    fun bodyObject(body: WireBody): ObjectNode {
        val o = nodes.objectNode()
        when (body) {
            is TaskMessage -> {
                o.put("task_id", body.taskId)
                o.put("parent_task_id", body.parentTaskId)
                o.put("worker_type", body.workerType)
                o.set<JsonNode>("input", tree(body.input))
                o.put("model_tier", body.modelTier.wire)
                o.put("priority", body.priority.wire)
                o.put("request_id", body.requestId)
                o.set<JsonNode>("metadata", tree(body.metadata))
            }
            is TaskResult -> {
                o.put("task_id", body.taskId)
                o.put("parent_task_id", body.parentTaskId)
                o.put("worker_type", body.workerType)
                o.put("status", body.status.wire)
                o.set<JsonNode>("output", body.output?.let { tree(it) } ?: nodes.nullNode())
                o.put("error", body.error)
                o.put("model_used", body.modelUsed)
                val tokens = o.putObject("token_usage")
                body.tokenUsage.forEach { (k, v) -> tokens.put(k, v) }
                o.set<JsonNode>("metadata", tree(body.metadata))
                o.put("processing_time_ms", body.processingTimeMs)
            }
            is OrchestratorGoal -> {
                o.put("goal_id", body.goalId)
                o.put("instruction", body.instruction)
                o.set<JsonNode>("context", tree(body.context))
                o.put("request_id", body.requestId)
                o.put("priority", body.priority.wire)
            }
        }
        return o
    }

    // ------------------------------------------------------------------
    // Timestamps
    // ------------------------------------------------------------------

    /**
     * Parse an RFC 3339 date-time with a mandatory offset. Fractional seconds
     * beyond microseconds are truncated, as upstream does. A leap second
     * (`:60`) and impossible dates are rejected. Returns null when invalid.
     */
    @JvmStatic
    fun parseTimestamp(text: String): Instant? {
        val m = rfc3339.matchEntire(text) ?: return null
        val g = m.groupValues
        return try {
            val local = LocalDateTime.of(g[1].toInt(), g[2].toInt(), g[3].toInt(), g[4].toInt(), g[5].toInt(), g[6].toInt())
            val micros = if (g[7].isEmpty()) 0L else g[7].padEnd(6, '0').substring(0, 6).toLong()
            var offsetSeconds = 0L
            if (g[8].isEmpty()) {
                val hours = g[10].toInt()
                val minutes = g[11].toInt()
                if (hours > 23 || minutes > 59) return null
                offsetSeconds = (hours * 3600L + minutes * 60L) * (if (g[9] == "-") -1 else 1)
            }
            val instant = Instant.ofEpochSecond(local.toEpochSecond(ZoneOffset.UTC) - offsetSeconds, micros * 1000)
            // The instant must be representable in UTC (years 0001-9999), since
            // frames are written in UTC.
            if (instant < minUtc || instant > maxUtc) return null
            instant
        } catch (e: DateTimeException) {
            null
        }
    }

    /** UTC, six fractional digits, `Z`. Any instant-equal form is conformant. */
    @JvmStatic
    fun formatTimestamp(value: Instant): String = format.format(value)

    private val minUtc: Instant = Instant.parse("0001-01-01T00:00:00Z")
    private val maxUtc: Instant = Instant.parse("9999-12-31T23:59:59.999999Z")

    private fun now(): Instant {
        val n = Instant.now()
        return Instant.ofEpochSecond(n.epochSecond, (n.nano / 1000) * 1000L)
    }

    private fun timestamp(f: Fields, key: String): Instant =
        parseTimestamp(f.string(key))
            ?: throw WireFormatException(WireLayer.FRAME, "$key must be an RFC 3339 date-time string with a UTC offset")

    /**
     * A JSON integer. As in JSON Schema's `integer`, an integral number
     * written as a float (`420.0`, `1e3`) is accepted; strings, booleans,
     * fractions and null are rejected.
     */
    private fun integer(node: JsonNode?, path: String): Long {
        if (node != null && node.isIntegralNumber && node.canConvertToLong()) return node.longValue()
        if (node != null && node.isFloatingPointNumber) {
            val d = node.doubleValue()
            if (!d.isInfinite() && Math.floor(d) == d && Math.abs(d) < 9.2e18) return d.toLong()
        }
        throw WireFormatException(WireLayer.BODY, "$path must be an integer")
    }

    private fun tree(value: Map<String, Any?>): JsonNode = mapper.valueToTree(value)

    /** Typed, layer-tagged field readers over one JSON object. */
    private class Fields(val o: ObjectNode, val layer: WireLayer) {
        fun has(key: String) = o.has(key)

        fun isNullOrAbsent(key: String) = !o.has(key) || o.get(key).isNull

        fun string(key: String): String {
            val v = o.get(key) ?: throw WireFormatException(layer, "$key is required")
            if (!v.isTextual) throw WireFormatException(layer, "$key must be a string")
            return v.textValue()
        }

        fun optionalString(key: String): String? = if (isNullOrAbsent(key)) null else string(key)

        fun obj(key: String): ObjectNode {
            val v = o.get(key) ?: throw WireFormatException(layer, "$key is required")
            return v as? ObjectNode ?: throw WireFormatException(layer, "$key must be a JSON object")
        }

        fun map(key: String): Map<String, Any?> = mapper.convertValue(obj(key))

        fun <E : WireEnum> enumValue(key: String, values: Array<E>): E {
            val text = string(key)
            return values.firstOrNull { it.wire == text }
                ?: throw WireFormatException(layer, "$key: unknown value '$text'")
        }
    }
}

/** A contract enum with a lower-case wire spelling. */
interface WireEnum {
    val wire: String
}
