package heddle.sdk

import org.slf4j.LoggerFactory
import java.util.concurrent.TimeUnit

/**
 * Base class for Heddle processor workers.
 *
 * Inherit from this class and implement [process]. The base class:
 *
 * - subscribes to `heddle.tasks.{worker_type}.{tier}` with queue group
 *   `processors-{worker_type}`;
 * - parses the inbound [WireEnvelope] frame and its [TaskMessage] body, and
 *   skips malformed messages (invalid frame, invalid body, or any
 *   `payload_type` other than `core.TaskMessage`) after calling
 *   [onMalformedMessage], without stopping the loop;
 * - converts [TaskMessage.input] to the typed payload and calls [process]
 *   with the task's metadata plus `model_tier`, as upstream;
 * - builds the [TaskResult]: routing fields from the task, timing, and
 *   output and metrics from the [WorkerOutput]; a thrown exception becomes a
 *   `failed` result;
 * - frames the result with a fresh `message_id` and timestamps, copies every
 *   `_`-prefixed Middleware-Lane key from the inbound frame, and publishes it
 *   to `heddle.results.{parent_task_id or "default"}`;
 * - calls [reset] after every task. Workers are stateless in every language
 *   SDK (cross-repo invariant C3).
 */
abstract class HeddleWorker<TPayload : Any, TOutput : Any>(
    val workerType: String,
    val modelTier: ModelTier = ModelTier.STANDARD,
    private val payloadClass: Class<TPayload>,
    private val outputClass: Class<TOutput>,
    private val transport: HeddleTransport,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    /** Implement domain processing logic here. Throw on failure. */
    abstract suspend fun process(payload: TPayload, metadata: Map<String, Any?>): WorkerOutput<TOutput>

    /** Called after every task, success or failure. Clear per-task state here. Default: no-op. */
    open suspend fun reset() {}

    /**
     * Called when an inbound message is not a valid framed [TaskMessage]. The
     * message is skipped and the loop continues. Default: log a warning.
     */
    open suspend fun onMalformedMessage(data: ByteArray, error: WireFormatException) {
        logger.warn("Skipping malformed message: ${error.message}")
    }

    /** Start the worker subscription loop. */
    suspend fun run() {
        val subject = HeddleSubjects.task(workerType, modelTier)
        val queueGroup = "processors-$workerType"

        logger.info("Starting worker '$workerType' on subject '$subject' (queue group '$queueGroup')")

        transport.subscribe(subject, queueGroup).collect { data ->
            val frame = handle(data) ?: return@collect
            val result = HeddleWire.parseBody(frame) as TaskResult
            val bytes = try {
                HeddleWire.serialize(frame)
            } catch (e: IllegalArgumentException) {
                // The result cannot be written as wire JSON (for example a NaN
                // in the output). Report a failure, as upstream does.
                val failed = result.copy(
                    status = TaskStatus.FAILED,
                    output = null,
                    metadata = emptyMap(),
                    error = "Result is not serializable as wire JSON: ${e.message}",
                )
                HeddleWire.serialize(HeddleWire.wrap(failed, frame.lane))
            }
            transport.publish(HeddleSubjects.result(result.parentTaskId), bytes)
        }
    }

    /**
     * Handle one inbound transport message: parse the frame, run the task, and
     * return the framed result. Returns null (after [onMalformedMessage]) when
     * the message is not a valid framed [TaskMessage].
     */
    suspend fun handle(data: ByteArray): WireEnvelope? {
        val envelope: WireEnvelope
        val task: TaskMessage
        try {
            envelope = HeddleWire.parseFrame(data)
            if (envelope.payloadType != PayloadTypes.TASK_MESSAGE) {
                throw WireFormatException(
                    WireLayer.DISPATCH,
                    "expected payload_type '${PayloadTypes.TASK_MESSAGE}' on a task subject, got '${envelope.payloadType}'",
                )
            }
            task = HeddleWire.parseBody(envelope) as TaskMessage
        } catch (e: WireFormatException) {
            onMalformedMessage(data, e)
            return null
        }
        return HeddleWire.wrap(handleTask(task), envelope.lane)
    }

    /**
     * Run one task through [process] and result assembly. Never throws for a
     * processing failure: the result has [TaskStatus.FAILED] instead.
     */
    suspend fun handleTask(task: TaskMessage): TaskResult {
        val start = System.nanoTime()
        fun elapsed() = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
        try {
            val payload = HeddleJson.mapper.convertValue(task.input, payloadClass)
            val metadata = task.metadata + ("model_tier" to task.modelTier.wire)
            val out = process(payload, metadata)
            val outputNode = HeddleJson.mapper.valueToTree<com.fasterxml.jackson.databind.JsonNode>(out.output)
            if (!outputNode.isObject) {
                return result(task, TaskStatus.FAILED, elapsed(), error = "Worker output must serialize to a JSON object",
                    modelUsed = out.modelUsed, tokens = out.tokenUsage)
            }
            @Suppress("UNCHECKED_CAST")
            val output = HeddleJson.mapper.convertValue(outputNode, Map::class.java) as Map<String, Any?>
            return result(task, TaskStatus.COMPLETED, elapsed(), output = output,
                modelUsed = out.modelUsed, tokens = out.tokenUsage, metadata = out.metadata)
        } catch (e: kotlinx.coroutines.CancellationException) {
            // A cancelled worker publishes nothing, as upstream.
            throw e
        } catch (e: Exception) {
            logger.error("Error processing task ${task.taskId}: ${e.message}", e)
            return result(task, TaskStatus.FAILED, elapsed(), error = e.message ?: e.javaClass.simpleName)
        } finally {
            reset()
        }
    }

    // Mirrors heddle.worker.base._publish_result: token_usage always carries
    // exactly prompt_tokens and completion_tokens, and metadata comes from the
    // worker's output (never the task's).
    private fun result(
        task: TaskMessage,
        status: TaskStatus,
        elapsedMs: Long,
        output: Map<String, Any?>? = null,
        error: String? = null,
        modelUsed: String? = null,
        tokens: Map<String, Long>? = null,
        metadata: Map<String, Any?>? = null,
    ) = TaskResult(
        taskId = task.taskId,
        parentTaskId = task.parentTaskId,
        workerType = task.workerType,
        status = status,
        output = output,
        error = error,
        modelUsed = modelUsed,
        tokenUsage = mapOf(
            "prompt_tokens" to (tokens?.get("prompt_tokens") ?: 0L),
            "completion_tokens" to (tokens?.get("completion_tokens") ?: 0L),
        ),
        metadata = metadata ?: emptyMap(),
        processingTimeMs = elapsedMs,
    )
}
