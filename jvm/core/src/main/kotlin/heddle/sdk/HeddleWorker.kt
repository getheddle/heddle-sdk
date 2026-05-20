package heddle.sdk

import com.fasterxml.jackson.module.kotlin.convertValue
import com.fasterxml.jackson.module.kotlin.readValue
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.onEach
import org.slf4j.LoggerFactory
import java.util.concurrent.TimeUnit

/**
 * Base class for Heddle processor workers.
 *
 * Handles the subscription loop, decoding, validation, and result publishing.
 * Inherit from this class and implement [process] to create a worker.
 */
abstract class HeddleWorker<TPayload : Any, TOutput : Any>(
    val workerType: String,
    val modelTier: ModelTier = ModelTier.STANDARD,
    private val payloadClass: Class<TPayload>,
    private val outputClass: Class<TOutput>,
    private val transport: HeddleTransport
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    /**
     * Implement domain processing logic here.
     */
    abstract suspend fun process(payload: TPayload, metadata: Map<String, Any?>): WorkerOutput<TOutput>

    /**
     * Start the worker subscription loop.
     */
    suspend fun run() {
        val subject = HeddleSubjects.task(workerType, modelTier)
        val queueGroup = "processors-$workerType"

        logger.info("Starting worker '$workerType' on subject '$subject' (queue group '$queueGroup')")

        transport.subscribe(subject, queueGroup).collect { data ->
            handleTask(data)
        }
    }

    private suspend fun handleTask(data: ByteArray) {
        val startTime = System.nanoTime()
        var inboundMessage: TaskMessage? = null

        try {
            // 1. Decode TaskMessage
            inboundMessage = HeddleJson.mapper.readValue<TaskMessage>(data)

            // 2. Validate Payload (Shallow)
            val payloadNode = HeddleJson.mapper.valueToTree<com.fasterxml.jackson.databind.JsonNode>(inboundMessage.payload)
            ShallowSchemaValidator.validate("Payload", payloadNode)

            // 3. Convert to typed payload
            val typedPayload = HeddleJson.mapper.convertValue(inboundMessage.payload, payloadClass)

            // 4. Run Process
            val workerOutput = process(typedPayload, inboundMessage.metadata)

            // 5. Validate Output (Shallow)
            val outputNode = HeddleJson.mapper.valueToTree<com.fasterxml.jackson.databind.JsonNode>(workerOutput.output)
            ShallowSchemaValidator.validate("Output", outputNode)

            // 6. Success: Publish TaskResult
            val durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime).toInt()
            val result = TaskResult(
                taskId = inboundMessage.taskId,
                parentTaskId = inboundMessage.parentTaskId,
                workerType = workerType,
                status = TaskStatus.COMPLETED,
                output = HeddleJson.mapper.convertValue(workerOutput.output),
                modelUsed = workerOutput.modelUsed,
                tokenUsage = workerOutput.tokenUsage ?: emptyMap(),
                metadata = workerOutput.metadata ?: emptyMap(),
                processingTimeMs = durationMs,
                traceContext = inboundMessage.traceContext
            )

            // Propagate extension data (Middleware Lane)
            inboundMessage.getExtensionData().forEach { (k, v) ->
                result.addExtensionData(k, v)
            }

            publishResult(result)

        } catch (e: Exception) {
            val durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime).toInt()
            logger.error("Error processing task: ${e.message}", e)

            if (inboundMessage != null) {
                // Publish Failure TaskResult
                val failureResult = TaskResult(
                    taskId = inboundMessage.taskId,
                    parentTaskId = inboundMessage.parentTaskId,
                    workerType = workerType,
                    status = TaskStatus.FAILED,
                    error = e.message ?: "Unknown error",
                    processingTimeMs = durationMs,
                    traceContext = inboundMessage.traceContext
                )
                
                // Propagate extension data even on failure
                inboundMessage.getExtensionData().forEach { (k, v) ->
                    failureResult.addExtensionData(k, v)
                }

                try {
                    publishResult(failureResult)
                } catch (pe: Exception) {
                    logger.error("Failed to publish failure result: ${pe.message}", pe)
                }
            } else {
                logger.warn("Skipping malformed message (could not decode TaskMessage)")
            }
        }
    }

    private suspend fun publishResult(result: TaskResult) {
        val subject = HeddleSubjects.result(result.parentTaskId)
        val data = HeddleJson.mapper.writeValueAsBytes(result)
        transport.publish(subject, data)
    }
}
