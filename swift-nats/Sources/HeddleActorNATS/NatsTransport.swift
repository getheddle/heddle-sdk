import Foundation
import HeddleActor
@preconcurrency import Nats

public actor NatsTransport: HeddleTransport {
    private let client: NatsClient
    private var connected = false

    public init(url: URL = URL(string: "nats://localhost:4222")!) {
        self.client = NatsClientOptions()
            .url(url)
            .build()
    }

    public init(client: NatsClient, connected: Bool = false) {
        self.client = client
        self.connected = connected
    }

    public func connect() async throws {
        guard !connected else {
            return
        }

        try await client.connect()
        connected = true
    }

    public func close() async throws {
        guard connected else {
            return
        }

        try await client.close()
        connected = false
    }

    public func publish(subject: String, payload: Data) async throws {
        try await ensureConnected()
        try await client.publish(payload, subject: subject)
    }

    public func subscribe(
        subject: String,
        queueGroup: String? = nil
    ) async throws -> AsyncThrowingStream<HeddleMessage, Error> {
        try await ensureConnected()
        let subscription = try await client.subscribe(subject: subject, queue: queueGroup)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await message in subscription {
                        continuation.yield(
                            HeddleMessage(
                                subject: message.subject,
                                payload: message.payload ?? Data()
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    try? await subscription.unsubscribe()
                }
            }
        }
    }

    private func ensureConnected() async throws {
        if !connected {
            try await connect()
        }
    }
}
