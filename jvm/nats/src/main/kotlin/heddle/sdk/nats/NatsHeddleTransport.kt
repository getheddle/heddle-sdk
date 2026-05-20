package heddle.sdk.nats

import heddle.sdk.HeddleTransport
import io.nats.client.Connection
import io.nats.client.Dispatcher
import io.nats.client.Nats
import io.nats.client.Options
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import org.slf4j.LoggerFactory

/**
 * NATS implementation of [HeddleTransport] using the official io.nats:jnats client.
 */
class NatsHeddleTransport(private val connection: Connection) : HeddleTransport {
    private val logger = LoggerFactory.getLogger(javaClass)

    override suspend fun publish(subject: String, data: ByteArray) {
        connection.publish(subject, data)
    }

    override fun subscribe(subject: String, queueGroup: String?): Flow<ByteArray> = callbackFlow {
        val dispatcher: Dispatcher = connection.createDispatcher { msg ->
            try {
                trySend(msg.data)
            } catch (e: Exception) {
                logger.error("Error sending message to flow: ${e.message}", e)
            }
        }

        if (queueGroup != null) {
            logger.debug("Subscribing to subject '$subject' with queue group '$queueGroup'")
            dispatcher.subscribe(subject, queueGroup)
        } else {
            logger.debug("Subscribing to subject '$subject'")
            dispatcher.subscribe(subject)
        }

        awaitClose {
            logger.debug("Closing NATS subscription for subject '$subject'")
            connection.closeDispatcher(dispatcher)
        }
    }

    companion object {
        /**
         * Connect to NATS with default options.
         */
        fun connect(url: String = Options.DEFAULT_URL): NatsHeddleTransport {
            val options = Options.Builder()
                .server(url)
                .maxReconnects(-1) // Infinite reconnects
                .build()
            val nc = Nats.connect(options)
            return NatsHeddleTransport(nc)
        }
    }
}
