package heddle.sdk

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

data class EchoPayload(val message: String)
data class EchoOutput(val response: String)

class EchoWorker(transport: HeddleTransport) : HeddleWorker<EchoPayload, EchoOutput>(
    workerType = "echo",
    payloadClass = EchoPayload::class.java,
    outputClass = EchoOutput::class.java,
    transport = transport
) {
    override suspend fun process(payload: EchoPayload, metadata: Map<String, Any?>): WorkerOutput<EchoOutput> {
        return WorkerOutput(EchoOutput("Echo: ${payload.message}"))
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class WorkerLoopTests {

    @Test
    fun testWorkerSuccessLoop() = runTest {
        val transport = InMemoryHeddleTransport()
        val worker = EchoWorker(transport)

        // Launch worker in the background scope of runTest
        backgroundScope.launch {
            worker.run()
        }

        // Prepare a task
        val task = TaskMessage(
            taskId = "t1",
            workerType = "echo",
            payload = mapOf("message" to "hello world")
        ).apply {
            addExtensionData("_x_trace", HeddleJson.mapper.valueToTree("trace-id"))
        }

        // Subscribe to results before publishing
        val resultFlow = transport.subscribe(HeddleSubjects.result())

        // Publish task
        transport.publish(HeddleSubjects.task("echo"), HeddleJson.mapper.writeValueAsBytes(task))

        // Wait for result
        val resultData = resultFlow.first()
        val result = HeddleJson.mapper.readValue(resultData, TaskResult::class.java)

        assertEquals("t1", result.taskId)
        assertEquals(TaskStatus.COMPLETED, result.status)
        assertEquals("Echo: hello world", result.output?.get("response"))
        
        // Verify Middleware Lane propagation
        assertEquals("trace-id", result.getExtensionData()["_x_trace"]?.asText())
    }

    @Test
    fun testWorkerFailureLoop() = runTest {
        val transport = InMemoryHeddleTransport()
        
        // A worker that always throws
        val failingWorker = object : HeddleWorker<EchoPayload, EchoOutput>(
            workerType = "fail",
            payloadClass = EchoPayload::class.java,
            outputClass = EchoOutput::class.java,
            transport = transport
        ) {
            override suspend fun process(payload: EchoPayload, metadata: Map<String, Any?>): WorkerOutput<EchoOutput> {
                throw RuntimeException("Boom!")
            }
        }

        backgroundScope.launch {
            failingWorker.run()
        }

        val task = TaskMessage(taskId = "t2", workerType = "fail", payload = mapOf("message" to "fail me"))
        val resultFlow = transport.subscribe(HeddleSubjects.result())

        transport.publish(HeddleSubjects.task("fail"), HeddleJson.mapper.writeValueAsBytes(task))

        val resultData = resultFlow.first()
        val result = HeddleJson.mapper.readValue(resultData, TaskResult::class.java)

        assertEquals("t2", result.taskId)
        assertEquals(TaskStatus.FAILED, result.status)
        assertEquals("Boom!", result.error)
    }
}
