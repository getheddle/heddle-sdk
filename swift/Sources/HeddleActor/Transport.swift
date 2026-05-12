import Foundation

public struct HeddleMessage: Sendable {
    public var subject: String
    public var payload: Data

    public init(subject: String, payload: Data) {
        self.subject = subject
        self.payload = payload
    }
}

public protocol HeddleTransport: Sendable {
    func publish(subject: String, payload: Data) async throws

    func subscribe(
        subject: String,
        queueGroup: String?
    ) async throws -> AsyncThrowingStream<HeddleMessage, Error>
}

