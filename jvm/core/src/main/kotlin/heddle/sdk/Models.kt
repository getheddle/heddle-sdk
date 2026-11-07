package heddle.sdk

import com.fasterxml.jackson.annotation.*
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.SerializationFeature
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.*

/**
 * Shared JSON configuration for the Heddle SDK.
 */
object HeddleJson {
    val mapper: ObjectMapper = jacksonObjectMapper().apply {
        registerModule(JavaTimeModule())
        configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
        configure(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS, false)
        setSerializationInclusion(JsonInclude.Include.NON_NULL)
    }

    fun nowIso8601(): String {
        return HeddleClock.nowIso8601()
    }
}

/**
 * Hint to the router about which class of LLM backend a task expects.
 */
enum class ModelTier(override val wire: String) : WireEnum {
    @JsonProperty("local") LOCAL("local"),
    @JsonProperty("standard") STANDARD("standard"),
    @JsonProperty("frontier") FRONTIER("frontier"),
}

enum class TaskPriority(override val wire: String) : WireEnum {
    @JsonProperty("low") LOW("low"),
    @JsonProperty("normal") NORMAL("normal"),
    @JsonProperty("high") HIGH("high"),
    @JsonProperty("critical") CRITICAL("critical"),
}

enum class TaskStatus(override val wire: String) : WireEnum {
    @JsonProperty("pending") PENDING("pending"),
    @JsonProperty("processing") PROCESSING("processing"),
    @JsonProperty("completed") COMPLETED("completed"),
    @JsonProperty("failed") FAILED("failed"),
}

/**
 * Body of a unit of work dispatched to a worker (`payload_type`
 * `core.TaskMessage`).
 *
 * Mirrors `heddle.core.messages.TaskMessage`. It travels inside a
 * [WireEnvelope] and is read and written only by [HeddleWire]. [input] is the
 * worker's input as opaque JSON (formerly `payload`).
 */
data class TaskMessage @JvmOverloads constructor(
    val workerType: String,
    val input: Map<String, Any?>,
    val taskId: String = UUID.randomUUID().toString(),
    val parentTaskId: String? = null,
    val modelTier: ModelTier = ModelTier.STANDARD,
    val priority: TaskPriority = TaskPriority.NORMAL,
    val requestId: String? = null,
    val metadata: Map<String, Any?> = emptyMap(),
) : WireBody {
    override val payloadType: String get() = PayloadTypes.TASK_MESSAGE
}

/**
 * Body of a worker's response to a [TaskMessage] (`payload_type`
 * `core.TaskResult`).
 *
 * Mirrors `heddle.core.messages.TaskResult`. Worker authors do not construct
 * it: [HeddleWorker] assembles it from the [WorkerOutput] and frames it,
 * copying the inbound frame's Middleware Lane.
 */
data class TaskResult @JvmOverloads constructor(
    val taskId: String,
    val workerType: String,
    val status: TaskStatus,
    val parentTaskId: String? = null,
    val output: Map<String, Any?>? = null,
    val error: String? = null,
    val modelUsed: String? = null,
    val tokenUsage: Map<String, Long> = emptyMap(),
    val metadata: Map<String, Any?> = emptyMap(),
    val processingTimeMs: Long = 0,
) : WireBody {
    override val payloadType: String get() = PayloadTypes.TASK_RESULT
}

/**
 * Body of a higher-level goal handed to an orchestrator (`payload_type`
 * `core.OrchestratorGoal`). Orchestration happens on the Python side; the
 * model exists so JVM tooling can submit goals on `heddle.goals.incoming`.
 */
data class OrchestratorGoal @JvmOverloads constructor(
    val instruction: String,
    val goalId: String = UUID.randomUUID().toString(),
    val context: Map<String, Any?> = emptyMap(),
    val requestId: String? = null,
    val priority: TaskPriority = TaskPriority.NORMAL,
) : WireBody {
    override val payloadType: String get() = PayloadTypes.ORCHESTRATOR_GOAL
}

/**
 * Compressed orchestrator state captured for self-summarisation. Mirrors
 * `heddle.core.messages.CheckpointState`. It is stored, not sent on the bus,
 * so it is not framed; it is read and written with [HeddleJson].
 */
data class CheckpointState(
    @JsonProperty("goal_id")
    val goalId: String = "",

    @JsonProperty("original_instruction")
    val originalInstruction: String = "",

    @JsonProperty("executive_summary")
    val executiveSummary: String = "",

    @JsonProperty("completed_tasks")
    val completedTasks: List<Map<String, Any?>> = emptyList(),

    @JsonProperty("pending_tasks")
    val pendingTasks: List<Map<String, Any?>> = emptyList(),

    @JsonProperty("open_issues")
    val openIssues: List<String> = emptyList(),

    @JsonProperty("decisions_made")
    val decisionsMade: List<String> = emptyList(),

    @JsonProperty("context_token_count")
    val contextTokenCount: Int = 0,

    @JsonProperty("checkpoint_number")
    val checkpointNumber: Int = 0,

    @JsonProperty("created_at")
    val createdAt: String = HeddleJson.nowIso8601()
)

/**
 * SDK-ergonomic return type for worker processing.
 * **Not a wire type.** [HeddleWorker] turns it into a [TaskResult]. As
 * upstream, the result carries exactly `prompt_tokens` and
 * `completion_tokens` from [tokenUsage], each defaulting to 0.
 */
data class WorkerOutput<T> @JvmOverloads constructor(
    val output: T,
    val modelUsed: String? = null,
    val tokenUsage: Map<String, Long>? = null,
    val metadata: Map<String, Any?>? = null
)

object HeddleClock {
    private val formatter = DateTimeFormatter.ISO_INSTANT.withZone(ZoneOffset.UTC)

    fun nowIso8601(): String {
        return formatter.format(Instant.now())
    }
}
