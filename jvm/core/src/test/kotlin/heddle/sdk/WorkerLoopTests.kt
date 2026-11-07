package heddle.sdk

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.node.JsonNodeFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

data class EchoPayload(val message: String)
data class EchoOutput(val response: String)

class EchoWorker(transport: HeddleTransport = InMemoryHeddleTransport()) : HeddleWorker<EchoPayload, EchoOutput>(
    workerType = "echo",
    modelTier = ModelTier.LOCAL,
    payloadClass = EchoPayload::class.java,
    outputClass = EchoOutput::class.java,
    transport = transport,
) {
    val malformed = mutableListOf<WireFormatException>()
    var resets = 0

    override suspend fun process(payload: EchoPayload, metadata: Map<String, Any?>): WorkerOutput<EchoOutput> {
        if (payload.message == "boom") throw RuntimeException("Boom!")
        return WorkerOutput(EchoOutput("Echo: ${payload.message}"), metadata = mapOf("seen_tier" to metadata["model_tier"]))
    }

    override suspend fun reset() {
        resets += 1
    }

    override suspend fun onMalformedMessage(data: ByteArray, error: WireFormatException) {
        malformed += error
    }
}

class WorkerLoopTests {
    private val nodes = JsonNodeFactory.instance

    private fun taskFrame(message: String = "hello world"): WireEnvelope = HeddleWire.wrap(
        TaskMessage(workerType = "echo", input = mapOf("message" to message), taskId = "t1",
            parentTaskId = "goal-1", modelTier = ModelTier.LOCAL),
        lane = mapOf<String, JsonNode>(
            "_trace_context" to nodes.objectNode().put("traceparent", "00-abc-def-01"),
            "_x_custom" to nodes.arrayNode().add(1).add("two").addNull(),
        ),
        origin = "test",
        correlationId = "corr-1",
    )

    @Test
    fun runPublishesFramedResultCarryingTheLane() = runTest {
        val transport = InMemoryHeddleTransport()
        val worker = EchoWorker(transport)
        backgroundScope.launch { worker.run() }
        val results = transport.subscribe(HeddleSubjects.result("goal-1"))

        val inbound = taskFrame()
        transport.publish(HeddleSubjects.task("echo", ModelTier.LOCAL), HeddleWire.serialize(inbound))

        val (envelope, body) = HeddleWire.parse(results.first())
        val result = body as TaskResult
        assertEquals(PayloadTypes.TASK_RESULT, envelope.payloadType)
        assertNotEquals(inbound.messageId, envelope.messageId)
        assertEquals(envelope.occurredAt, envelope.recordedAt)
        assertNull(envelope.origin)
        assertNull(envelope.correlationId)
        assertNull(envelope.causationId)
        assertEquals(inbound.lane, envelope.lane)

        assertEquals("t1", result.taskId)
        assertEquals("goal-1", result.parentTaskId)
        assertEquals("echo", result.workerType)
        assertEquals(TaskStatus.COMPLETED, result.status)
        assertEquals("Echo: hello world", result.output?.get("response"))
        assertEquals(setOf("prompt_tokens", "completion_tokens"), result.tokenUsage.keys)
        assertEquals("local", result.metadata["seen_tier"])
    }

    @Test
    fun resultEchoesTheTasksWorkerType() = runTest {
        val frame = HeddleWire.wrap(TaskMessage(workerType = "echo-v2", input = mapOf("message" to "hi")))
        val result = HeddleWire.parseBody(assertNotNull(EchoWorker().handle(HeddleWire.serialize(frame)))) as TaskResult
        assertEquals("echo-v2", result.workerType)
    }

    @Test
    fun processingFailurePublishesFailedResultAndResets() = runTest {
        val worker = EchoWorker()
        val frame = assertNotNull(worker.handle(HeddleWire.serialize(taskFrame("boom"))))
        val result = HeddleWire.parseBody(frame) as TaskResult
        assertEquals(TaskStatus.FAILED, result.status)
        assertEquals("Boom!", result.error)
        assertEquals(setOf("prompt_tokens", "completion_tokens"), result.tokenUsage.keys)
        assertEquals(1, worker.resets)
    }

    @Test
    fun malformedMessagesAreSkippedAtTheRightLayer() = runTest {
        val cases = listOf(
            """{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"message":"hi"}},"bogus":1}""" to WireLayer.FRAME,
            """{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"message":"hi"}},"occurred_at":"2026-01-01T00:00:00"}""" to WireLayer.FRAME,
            """{"payload_type":"core.TaskMessage","payload":{"input":{"message":"hi"}}}""" to WireLayer.BODY,
            """{"payload_type":"core.TaskResult","payload":{"task_id":"t","worker_type":"echo","status":"completed"}}""" to WireLayer.DISPATCH,
            """{"payload_type":"events.Event","payload":{}}""" to WireLayer.DISPATCH,
            "not json" to WireLayer.FRAME,
        )
        for ((raw, layer) in cases) {
            val worker = EchoWorker()
            assertNull(worker.handle(raw.toByteArray()), raw)
            assertEquals(listOf(layer), worker.malformed.map { it.layer }, raw)
            // The worker keeps working afterwards.
            assertNotNull(worker.handle(HeddleWire.serialize(taskFrame())))
        }
    }

    @Test
    fun everyValidTaskFixtureYieldsAParseableResult() = runTest {
        for (file in Fixtures.files("valid").filter { Fixtures.entry(it).get("payload_type").asText() == PayloadTypes.TASK_MESSAGE }) {
            val bytes = Fixtures.bytes(file)
            val inbound = HeddleWire.parseFrame(bytes)
            val task = HeddleWire.parseBody(inbound) as TaskMessage
            val worker = object : HeddleWorker<Map<*, *>, Map<*, *>>(
                task.workerType, task.modelTier, Map::class.java, Map::class.java, InMemoryHeddleTransport(),
            ) {
                override suspend fun process(payload: Map<*, *>, metadata: Map<String, Any?>) = WorkerOutput<Map<*, *>>(payload)
            }
            val frame = assertNotNull(worker.handle(bytes), file)
            val (envelope, body) = HeddleWire.parse(HeddleWire.serialize(frame))
            assertEquals(PayloadTypes.TASK_RESULT, envelope.payloadType, file)
            assertEquals(task.taskId, (body as TaskResult).taskId, file)
            assertEquals(inbound.lane, envelope.lane, file)
            assertTrue(body.status == TaskStatus.COMPLETED, file)
        }
    }
}
