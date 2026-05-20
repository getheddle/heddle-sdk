package heddle.examples

import heddle.sdk.*
import heddle.sdk.nats.NatsHeddleTransport
import kotlinx.coroutines.runBlocking

data class EchoPayload(val message: String)
data class EchoOutput(val response: String)

/**
 * A simple Echo worker implemented in Kotlin.
 *
 * Demonstrates:
 * 1. Typed payload and output models.
 * 2. Inheriting from HeddleWorker.
 * 3. Using NatsHeddleTransport.
 */
class KotlinEchoWorker(transport: HeddleTransport) : HeddleWorker<EchoPayload, EchoOutput>(
    workerType = "echo-kotlin",
    payloadClass = EchoPayload::class.java,
    outputClass = EchoOutput::class.java,
    transport = transport
) {
    override suspend fun process(payload: EchoPayload, metadata: Map<String, Any?>): WorkerOutput<EchoOutput> {
        println("Kotlin worker received: ${payload.message}")
        return WorkerOutput(EchoOutput("Kotlin Echo: ${payload.message}"))
    }
}

fun main() = runBlocking {
    // Connect to NATS (standard heddle default)
    val transport = NatsHeddleTransport.connect("nats://localhost:4222")
    
    val worker = KotlinEchoWorker(transport)
    worker.run()
}
