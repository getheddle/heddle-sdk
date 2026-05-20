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
enum class ModelTier {
    @JsonProperty("local") LOCAL,
    @JsonProperty("standard") STANDARD,
    @JsonProperty("frontier") FRONTIER
}

/**
 * Priority hint for scheduling and (future) preemption decisions.
 */
enum class TaskPriority {
    @JsonProperty("low") LOW,
    @JsonProperty("normal") NORMAL,
    @JsonProperty("high") HIGH,
    @JsonProperty("critical") CRITICAL
}

/**
 * Lifecycle state carried on [TaskResult].
 */
enum class TaskStatus {
    @JsonProperty("pending") PENDING,
    @JsonProperty("processing") PROCESSING,
    @JsonProperty("completed") COMPLETED,
    @JsonProperty("failed") FAILED
}

/**
 * Wire envelope for a unit of work dispatched to a worker.
 */
data class TaskMessage(
    @JsonProperty("task_id")
    val taskId: String = UUID.randomUUID().toString(),

    @JsonProperty("parent_task_id")
    val parentTaskId: String? = null,

    @JsonProperty("worker_type")
    val workerType: String = "",

    @JsonProperty("payload")
    val payload: Map<String, Any?> = emptyMap(),

    @JsonProperty("model_tier")
    val modelTier: ModelTier = ModelTier.STANDARD,

    @JsonProperty("priority")
    val priority: TaskPriority = TaskPriority.NORMAL,

    @JsonProperty("created_at")
    val createdAt: String = HeddleJson.nowIso8601(),

    @JsonProperty("request_id")
    val requestId: String? = null,

    @JsonProperty("metadata")
    val metadata: Map<String, Any?> = emptyMap(),

    @JsonProperty("_trace_context")
    val traceContext: Map<String, String>? = null
) {
    @JsonIgnore
    private val _extensionData = mutableMapOf<String, JsonNode>()

    @JsonAnySetter
    fun addExtensionData(key: String, value: JsonNode) {
        _extensionData[key] = value
    }

    @JsonAnyGetter
    fun getExtensionData(): Map<String, JsonNode> = _extensionData
}

/**
 * Wire envelope for a worker's response to a [TaskMessage].
 */
data class TaskResult(
    @JsonProperty("task_id")
    val taskId: String = "",

    @JsonProperty("parent_task_id")
    val parentTaskId: String? = null,

    @JsonProperty("worker_type")
    val workerType: String = "",

    @JsonProperty("status")
    val status: TaskStatus = TaskStatus.COMPLETED,

    @JsonProperty("output")
    val output: Map<String, Any?>? = null,

    @JsonProperty("error")
    val error: String? = null,

    @JsonProperty("model_used")
    val modelUsed: String? = null,

    @JsonProperty("token_usage")
    val tokenUsage: Map<String, Int> = emptyMap(),

    @JsonProperty("metadata")
    val metadata: Map<String, Any?> = emptyMap(),

    @JsonProperty("processing_time_ms")
    val processingTimeMs: Int = 0,

    @JsonProperty("completed_at")
    val completedAt: String = HeddleJson.nowIso8601(),

    @JsonProperty("_trace_context")
    val traceContext: Map<String, String>? = null
) {
    @JsonIgnore
    private val _extensionData = mutableMapOf<String, JsonNode>()

    @JsonAnySetter
    fun addExtensionData(key: String, value: JsonNode) {
        _extensionData[key] = value
    }

    @JsonAnyGetter
    fun getExtensionData(): Map<String, JsonNode> = _extensionData
}

/**
 * Wire envelope for a higher-level goal handed to an orchestrator.
 */
data class OrchestratorGoal(
    @JsonProperty("goal_id")
    val goalId: String = UUID.randomUUID().toString(),

    @JsonProperty("instruction")
    val instruction: String = "",

    @JsonProperty("context")
    val context: Map<String, Any?> = emptyMap(),

    @JsonProperty("request_id")
    val requestId: String? = null,

    @JsonProperty("priority")
    val priority: TaskPriority = TaskPriority.NORMAL,

    @JsonProperty("created_at")
    val createdAt: String = HeddleJson.nowIso8601()
)

/**
 * Compressed orchestrator state captured for self-summarisation.
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
 * Provenance and correlation for an event.
 */
data class EventMetadata(
    @JsonProperty("command_id")
    val commandId: String? = null,

    @JsonProperty("correlation_id")
    val correlationId: String? = null,

    @JsonProperty("issued_by")
    val issuedBy: String = "",

    @JsonProperty("extra")
    val extra: Map<String, Any?> = emptyMap()
)

/**
 * Canonical event envelope for heddle.contrib.events.
 */
data class EventEnvelope(
    @JsonProperty("event_id")
    val eventId: String = UUID.randomUUID().toString(),

    @JsonProperty("aggregate_type")
    val aggregateType: String = "",

    @JsonProperty("aggregate_id")
    val aggregateId: String = "",

    @JsonProperty("aggregate_version")
    val aggregateVersion: Int = 0,

    @JsonProperty("event_type")
    val eventType: String = "",

    @JsonProperty("event_version")
    val eventVersion: Int = 1,

    @JsonProperty("payload")
    val payload: Map<String, Any?> = emptyMap(),

    @JsonProperty("metadata")
    val metadata: EventMetadata = EventMetadata(),

    @JsonProperty("occurred_at")
    val occurredAt: String = "",

    @JsonProperty("recorded_at")
    val recordedAt: String = ""
)

/**
 * Provenance and correlation for a command.
 */
data class CommandMetadata(
    @JsonProperty("correlation_id")
    val correlationId: String? = null,

    @JsonProperty("issued_by")
    val issuedBy: String = "",

    @JsonProperty("issued_by_legacy")
    val issuedByLegacy: String? = null,

    @JsonProperty("extra")
    val extra: Map<String, Any?> = emptyMap()
)

/**
 * Canonical command envelope for heddle.contrib.events.
 */
data class CommandMessage(
    @JsonProperty("command_id")
    val commandId: String = UUID.randomUUID().toString(),

    @JsonProperty("aggregate_type")
    val aggregateType: String = "",

    @JsonProperty("aggregate_id")
    val aggregateId: String = "",

    @JsonProperty("command_type")
    val commandType: String = "",

    @JsonProperty("command_version")
    val commandVersion: Int = 1,

    @JsonProperty("payload")
    val payload: Map<String, Any?> = emptyMap(),

    @JsonProperty("metadata")
    val metadata: CommandMetadata = CommandMetadata(),

    @JsonProperty("issued_at")
    val issuedAt: String = "",

    @JsonProperty("expected_aggregate_version")
    val expectedAggregateVersion: Int? = null
)

/**
 * SDK-ergonomic return type for worker processing.
 * **Not a wire type.**
 */
data class WorkerOutput<T>(
    val output: T,
    val modelUsed: String? = null,
    val tokenUsage: Map<String, Int>? = null,
    val metadata: Map<String, Any?>? = null
)

object HeddleClock {
    private val formatter = DateTimeFormatter.ISO_INSTANT.withZone(ZoneOffset.UTC)

    fun nowIso8601(): String {
        return formatter.format(Instant.now())
    }
}
