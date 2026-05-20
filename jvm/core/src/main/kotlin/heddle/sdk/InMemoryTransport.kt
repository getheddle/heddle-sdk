package heddle.sdk

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.filter
import java.util.concurrent.ConcurrentHashMap

/**
 * In-memory implementation of [HeddleTransport] for tests and local examples.
 */
class InMemoryHeddleTransport : HeddleTransport {
    private val subjects = ConcurrentHashMap<String, MutableSharedFlow<ByteArray>>()

    override suspend fun publish(subject: String, data: ByteArray) {
        val flow = subjects.computeIfAbsent(subject) { createFlow() }
        flow.emit(data)
    }

    override fun subscribe(subject: String, queueGroup: String?): Flow<ByteArray> {
        // Note: queueGroup is ignored in this simple in-memory implementation.
        // Every subscriber to the same subject receives all messages.
        return subjects.computeIfAbsent(subject) { createFlow() }
    }

    private fun createFlow() = MutableSharedFlow<ByteArray>(
        replay = 1,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
}
