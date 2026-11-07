import Foundation
import Testing
@testable import HeddleActor

@Test func subjectHelpersMatchHeddleConventions() {
    #expect(
        HeddleSubjects.workerTasks(workerType: "image_classifier", tier: "local")
            == "heddle.tasks.image_classifier.local"
    )
    #expect(HeddleSubjects.results(parentTaskId: nil) == "heddle.results.default")
    #expect(HeddleSubjects.results(parentTaskId: "goal-1") == "heddle.results.goal-1")
    #expect(
        HeddleSubjects.processorQueueGroup(workerType: "image_classifier")
            == "processors-image_classifier"
    )
}

@Test func inMemoryTransportRoutesQueueGroupsRoundRobin() async throws {
    let transport = InMemoryTransport()
    let first = try await transport.subscribe(subject: "heddle.test", queueGroup: "processors-echo")
    let second = try await transport.subscribe(subject: "heddle.test", queueGroup: "processors-echo")

    try await transport.publish(subject: "heddle.test", payload: Data("one".utf8))
    try await transport.publish(subject: "heddle.test", payload: Data("two".utf8))

    #expect(String(decoding: try await nextMessage(from: first).payload, as: UTF8.self) == "one")
    #expect(String(decoding: try await nextMessage(from: second).payload, as: UTF8.self) == "two")

    await transport.close()
}

enum TestTimeout: Error {
    case timedOut
    case streamClosed
}

func nextMessage(
    from stream: AsyncThrowingStream<HeddleMessage, Error>
) async throws -> HeddleMessage {
    try await withThrowingTaskGroup(of: HeddleMessage.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let message = try await iterator.next() else {
                throw TestTimeout.streamClosed
            }
            return message
        }

        group.addTask {
            try await Task.sleep(for: .seconds(5))
            throw TestTimeout.timedOut
        }

        let message = try await group.next()!
        group.cancelAll()
        return message
    }
}
