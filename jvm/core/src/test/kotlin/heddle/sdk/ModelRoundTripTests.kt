package heddle.sdk

import com.fasterxml.jackson.module.kotlin.readValue
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class ModelRoundTripTests {

    @Test
    fun testTaskMessageRoundTripWithMiddlewareLane() {
        val json = """
            {
                "task_id": "test-task",
                "worker_type": "echo",
                "payload": {"message": "hello"},
                "model_tier": "standard",
                "priority": "normal",
                "created_at": "2026-05-19T12:00:00Z",
                "_trace_context": {
                    "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
                },
                "_x_custom_middleware_key": "custom-value"
            }
        """.trimIndent()

        val message: TaskMessage = HeddleJson.mapper.readValue(json)

        // Verify known fields
        assertEquals("test-task", message.taskId)
        assertEquals("echo", message.workerType)
        assertEquals(ModelTier.STANDARD, message.modelTier)
        assertEquals("hello", message.payload["message"])
        assertEquals("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", message.traceContext?.get("traceparent"))

        // Verify middleware lane preservation (unknown fields)
        val extensionData = message.getExtensionData()
        assertTrue(extensionData.containsKey("_x_custom_middleware_key"))
        assertEquals("custom-value", extensionData["_x_custom_middleware_key"]?.asText())

        // Round-trip back to JSON
        val reserialized = HeddleJson.mapper.writeValueAsString(message)
        
        // Verify the unknown key is still there
        assertTrue(reserialized.contains("_x_custom_middleware_key"))
        assertTrue(reserialized.contains("custom-value"))
        assertTrue(reserialized.contains("_trace_context"))
    }

    @Test
    fun testTaskResultRoundTrip() {
        val result = TaskResult(
            taskId = "test-task",
            status = TaskStatus.COMPLETED,
            output = mapOf("result" to "done"),
            processingTimeMs = 123
        ).apply {
            addExtensionData("_x_passthrough", HeddleJson.mapper.valueToTree("important"))
        }

        val json = HeddleJson.mapper.writeValueAsString(result)

        assertTrue(json.contains(""""status":"completed""""))
        assertTrue(json.contains(""""processing_time_ms":123"""))
        assertTrue(json.contains(""""_x_passthrough":"important""""))

        val deserialized: TaskResult = HeddleJson.mapper.readValue(json)
        assertEquals(TaskStatus.COMPLETED, deserialized.status)
        assertEquals("important", deserialized.getExtensionData()["_x_passthrough"]?.asText())
    }
}
