package heddle.sdk

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.node.ObjectNode
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Holds the SDK to the vendored v1 conformance fixtures (schemas/v1/fixtures,
 * driven by manifest.json), the same files heddle's own runtime is tested
 * against.
 */
object Fixtures {
    private val mapper = jacksonObjectMapper()

    val directory: File = generateSequence(File(System.getProperty("user.dir")).absoluteFile) { it.parentFile }
        .firstOrNull { File(it, "schemas/manifest.json").exists() }
        ?.let { File(it, "schemas/v1/fixtures") }
        ?: error("repository root (schemas/manifest.json) not found")

    val manifest: ObjectNode = mapper.readTree(File(directory, "manifest.json")) as ObjectNode

    val entries: List<ObjectNode> = manifest.get("fixtures").map { it as ObjectNode }

    fun files(expect: String) = entries.filter { it.get("expect").asText() == expect }.map { it.get("file").asText() }

    fun entry(file: String) = entries.single { it.get("file").asText() == file }

    fun bytes(file: String) = File(directory, file).readBytes()

    fun tree(bytes: ByteArray) = mapper.readTree(bytes) as ObjectNode
}

class WireConformanceTests {
    @Test
    fun manifestRegistersExactlyTheSdkPayloadTypes() {
        val registered = Fixtures.manifest.get("payload_types").fieldNames().asSequence().sorted().toList()
        assertEquals(PayloadTypes.ALL.sorted(), registered)
    }

    @Test
    fun manifestListsTwentyFourFixtures() {
        assertEquals(24, Fixtures.files("valid").size + Fixtures.files("invalid").size)
    }

    @Test
    fun everyValidFixtureParsesAndRoundTrips() {
        val failures = mutableListOf<String>()
        for (file in Fixtures.files("valid")) {
            val entry = Fixtures.entry(file)
            val bytes = Fixtures.bytes(file)
            val (envelope, body) = HeddleWire.parse(bytes)
            if (envelope.payloadType != entry.get("payload_type").asText()) failures += "$file: payload_type"

            // Re-serialize from the typed body, not the raw payload.
            val reframed = HeddleWire.wrap(body, envelope.lane, envelope.origin, envelope.correlationId, envelope.causationId)
                .copy(messageId = envelope.messageId, occurredAt = envelope.occurredAt, recordedAt = envelope.recordedAt)
            val actual = HeddleWire.toJsonObject(reframed)
            val expected = Fixtures.tree(bytes)

            entry.get("may_drop")?.forEach { drop(expected, it.asText()); drop(actual, it.asText()) }
            for (key in listOf("occurred_at", "recorded_at")) {
                val want = HeddleWire.parseTimestamp(expected.get(key).asText())
                val got = HeddleWire.parseTimestamp(actual.get(key).asText())
                if (want == null || want != got) failures += "$file: $key $want != $got"
                expected.remove(key)
                actual.remove(key)
            }
            if (!jsonValueEquals(expected, actual)) failures += "$file: round-trip mismatch\n  expected $expected\n  actual   $actual"
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    @Test
    fun everyInvalidFixtureIsRejectedAtTheNamedLayer() {
        val failures = mutableListOf<String>()
        for (file in Fixtures.files("invalid")) {
            val want = WireLayer.valueOf(Fixtures.entry(file).get("rejected_at").asText().uppercase())
            try {
                HeddleWire.parse(Fixtures.bytes(file))
                failures += "$file: accepted"
            } catch (e: WireFormatException) {
                if (e.layer != want) failures += "$file: rejected at ${e.layer}, expected $want (${e.message})"
            }
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    @Test
    fun timestampsFollowRfc3339WithOffset() {
        val cases = mapOf(
            "2026-01-01T00:00:00Z" to true,
            "2026-01-01t00:00:00z" to true,
            "2026-01-01T00:00:00.123456789+02:00" to true,
            "2024-02-29T23:59:59-23:59" to true,
            "2026-01-01T00:00:00" to false,
            "2026-01-01T00:00:00+0200" to false,
            "2026-01-01T00:00:60Z" to false,
            "2026-02-30T00:00:00Z" to false,
            "2026-01-01T00:00:00Z\n" to false,
            "2026-01-01T00:00:00.Z" to false,
        )
        for ((text, ok) in cases) assertEquals(ok, HeddleWire.parseTimestamp(text) != null, text)
    }

    @Test
    fun timestampFormattingIsUtcWithMicroseconds() {
        val value = assertNotNull(HeddleWire.parseTimestamp("2026-01-01T02:00:00.1234569+02:00"))
        assertEquals("2026-01-01T00:00:00.123456Z", HeddleWire.formatTimestamp(value))
    }

    @Test
    fun missingTimestampsAreFilledTogether() {
        val none = HeddleWire.parseFrame("""{"payload_type":"core.TaskMessage","payload":{}}""".toByteArray())
        assertEquals(none.occurredAt, none.recordedAt)
        val one = HeddleWire.parseFrame(
            """{"payload_type":"core.TaskMessage","payload":{},"occurred_at":"2026-01-01T00:00:00Z"}""".toByteArray()
        )
        assertEquals(one.occurredAt, one.recordedAt)
    }

    @Test
    fun jacksonLeniencyDoesNotReachTheWire() {
        fun body(json: String) = assertFailsWith<WireFormatException> {
            HeddleWire.parse("""{"payload_type":"core.TaskResult","payload":$json}""".toByteArray())
        }.layer
        val base = """"task_id":"t","worker_type":"w","status":"completed""""
        assertEquals(WireLayer.BODY, body("""{$base,"processing_time_ms":420.5}"""))
        assertEquals(WireLayer.BODY, body("""{$base,"processing_time_ms":"420"}"""))
        assertEquals(WireLayer.BODY, body("""{$base,"processing_time_ms":true}"""))
        assertEquals(WireLayer.BODY, body("""{"task_id":"t","worker_type":5,"status":"completed"}"""))
        val epoch = assertFailsWith<WireFormatException> {
            HeddleWire.parseFrame("""{"payload_type":"core.TaskResult","payload":{},"occurred_at":1700000000}""".toByteArray())
        }
        assertEquals(WireLayer.FRAME, epoch.layer)
    }

    private fun drop(root: ObjectNode, dottedPath: String) {
        val parts = dottedPath.split(".")
        var node: JsonNode? = root
        for (part in parts.dropLast(1)) node = node?.get(part)
        (node as? ObjectNode)?.remove(parts.last())
    }
}

/** JSON equality by value: key order is ignored and numbers compare numerically. */
fun jsonValueEquals(a: JsonNode?, b: JsonNode?): Boolean = when {
    a == null || b == null -> a == b
    a.isNumber && b.isNumber -> a.decimalValue().compareTo(b.decimalValue()) == 0
    a.isObject && b.isObject -> a.size() == b.size() &&
        a.fieldNames().asSequence().all { b.has(it) && jsonValueEquals(a.get(it), b.get(it)) }
    a.isArray && b.isArray -> a.size() == b.size() && (0 until a.size()).all { jsonValueEquals(a.get(it), b.get(it)) }
    else -> a == b
}

