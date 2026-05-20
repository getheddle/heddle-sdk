package heddle.sdk

import kotlinx.coroutines.flow.Flow

/**
 * Subject helper for Heddle task/result/control subjects.
 */
object HeddleSubjects {
    fun task(workerType: String, tier: ModelTier = ModelTier.STANDARD): String =
        "heddle.tasks.$workerType.${tier.name.lowercase()}"

    fun result(parentTaskId: String? = null): String =
        "heddle.results.${parentTaskId ?: "default"}"

    fun control(actorId: String): String =
        "heddle.control.$actorId"
}

/**
 * Minimal transport boundary with publish/subscribe semantics.
 */
interface HeddleTransport {
    /**
     * Publish bytes to a subject.
     */
    suspend fun publish(subject: String, data: ByteArray)

    /**
     * Subscribe to a subject with an optional queue group.
     * Returns a Flow of ByteArrays.
     */
    fun subscribe(subject: String, queueGroup: String? = null): Flow<ByteArray>
}
