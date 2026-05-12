import Foundation

public actor InMemoryTransport: HeddleTransport {
    private struct Subscriber {
        let id: UUID
        let subject: String
        let queueGroup: String?
        let continuation: AsyncThrowingStream<HeddleMessage, Error>.Continuation
    }

    private var subscribers: [Subscriber] = []
    private var groupCounters: [GroupKey: Int] = [:]
    private var closed = false

    public init() {}

    deinit {
        for subscriber in subscribers {
            subscriber.continuation.finish()
        }
    }

    public func publish(subject: String, payload: Data) async throws {
        try ensureOpen()

        let message = HeddleMessage(subject: subject, payload: payload)
        let targets = selectTargets(for: subject)
        for target in targets {
            target.continuation.yield(message)
        }
    }

    public func subscribe(
        subject: String,
        queueGroup: String? = nil
    ) async throws -> AsyncThrowingStream<HeddleMessage, Error> {
        try ensureOpen()

        let id = UUID()
        return AsyncThrowingStream { continuation in
            let subscriber = Subscriber(
                id: id,
                subject: subject,
                queueGroup: queueGroup,
                continuation: continuation
            )
            subscribers.append(subscriber)

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id: id) }
            }
        }
    }

    public func close() {
        guard !closed else {
            return
        }

        closed = true
        let active = subscribers
        subscribers.removeAll()
        groupCounters.removeAll()

        for subscriber in active {
            subscriber.continuation.finish()
        }
    }

    public func subscriberCount(subject: String, queueGroup: String? = nil) -> Int {
        subscribers.filter { subscriber in
            subscriber.subject == subject && subscriber.queueGroup == queueGroup
        }.count
    }

    private func selectTargets(for subject: String) -> [Subscriber] {
        var targets: [Subscriber] = []
        var grouped: [String: [Subscriber]] = [:]

        for subscriber in subscribers where subscriber.subject == subject {
            guard let queueGroup = subscriber.queueGroup else {
                targets.append(subscriber)
                continue
            }

            grouped[queueGroup, default: []].append(subscriber)
        }

        for (queueGroup, members) in grouped where !members.isEmpty {
            let key = GroupKey(subject: subject, queueGroup: queueGroup)
            let counter = groupCounters[key, default: 0]
            targets.append(members[counter % members.count])
            groupCounters[key] = counter + 1
        }

        return targets
    }

    private func removeSubscriber(id: UUID) {
        subscribers.removeAll { $0.id == id }
    }

    private func ensureOpen() throws {
        if closed {
            throw InMemoryTransportError.closed
        }
    }
}

private struct GroupKey: Hashable {
    var subject: String
    var queueGroup: String
}

public enum InMemoryTransportError: Error, Sendable {
    case closed
}
