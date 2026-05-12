import Foundation
@testable import HeddleActor

#if canImport(XCTest)
import XCTest

final class SubjectTests: XCTestCase {
    func testSubjectHelpersMatchHeddleConventions() {
        XCTAssertEqual(
            HeddleSubjects.workerTasks(workerType: "image_classifier", tier: "local"),
            "heddle.tasks.image_classifier.local"
        )
        XCTAssertEqual(HeddleSubjects.results(parentTaskId: nil), "heddle.results.default")
        XCTAssertEqual(HeddleSubjects.results(parentTaskId: "goal-1"), "heddle.results.goal-1")
        XCTAssertEqual(
            HeddleSubjects.processorQueueGroup(workerType: "image_classifier"),
            "processors-image_classifier"
        )
    }

    func testTaskMessageRoundTripUsesSnakeCaseWireKeys() throws {
        let task = makeTaskMessage()
        let data = try HeddleCoders.encode(task)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["task_id"] as? String, "task-1")
        XCTAssertEqual(json["parent_task_id"] as? String, "goal-1")
        XCTAssertEqual(json["worker_type"] as? String, "echo")
        XCTAssertNotNil(json["_trace_context"])

        let decoded = try HeddleCoders.decode(TaskMessage.self, from: data)
        XCTAssertEqual(decoded.taskId, task.taskId)
        XCTAssertEqual(decoded.payload["text"], .string("hello"))
    }

    func testInMemoryTransportRoutesQueueGroupsRoundRobin() async throws {
        let transport = InMemoryTransport()
        let first = try await transport.subscribe(subject: "heddle.test", queueGroup: "processors-echo")
        let second = try await transport.subscribe(subject: "heddle.test", queueGroup: "processors-echo")

        try await transport.publish(subject: "heddle.test", payload: Data("one".utf8))
        try await transport.publish(subject: "heddle.test", payload: Data("two".utf8))

        let firstMessage = try await nextMessage(from: first)
        let secondMessage = try await nextMessage(from: second)

        XCTAssertEqual(String(decoding: firstMessage.payload, as: UTF8.self), "one")
        XCTAssertEqual(String(decoding: secondMessage.payload, as: UTF8.self), "two")

        await transport.close()
    }

    func testWorkerRunPublishesResultThroughInMemoryTransport() async throws {
        let worker = TestEchoWorker()
        let transport = InMemoryTransport()
        let results = try await transport.subscribe(
            subject: HeddleSubjects.results(parentTaskId: "goal-1"),
            queueGroup: nil
        )

        let workerLoop = Task {
            try await worker.run(transport: transport)
        }

        try await waitForSubscription(transport: transport, worker: worker)

        let task = makeTaskMessage()
        try await transport.publish(
            subject: worker.subject,
            payload: HeddleCoders.encode(task)
        )

        let message = try await nextMessage(from: results)
        let result = try HeddleCoders.decode(TaskResult.self, from: message.payload)
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.output?["text"], .string("HELLO"))
        XCTAssertEqual(result.traceContext, task.traceContext)

        await transport.close()
        workerLoop.cancel()
        _ = try? await workerLoop.value
    }
}
#elseif canImport(Testing)
import Testing

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

@Test func taskMessageRoundTripUsesSnakeCaseWireKeys() throws {
    let task = TaskMessage(
        taskId: "task-1",
        parentTaskId: "goal-1",
        workerType: "echo",
        payload: ["text": .string("hello")],
        modelTier: .local,
        traceContext: ["traceparent": "00-abc-def-01"]
    )

    let data = try HeddleCoders.encode(task)
    let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(json["task_id"] as? String == "task-1")
    #expect(json["parent_task_id"] as? String == "goal-1")
    #expect(json["worker_type"] as? String == "echo")
    #expect(json["_trace_context"] != nil)

    let decoded = try HeddleCoders.decode(TaskMessage.self, from: data)
    #expect(decoded.taskId == task.taskId)
    #expect(decoded.payload["text"] == .string("hello"))
}
#endif

private func makeTaskMessage() -> TaskMessage {
    TaskMessage(
        taskId: "task-1",
        parentTaskId: "goal-1",
        workerType: "echo",
        payload: ["text": .string("hello")],
        modelTier: .local,
        traceContext: ["traceparent": "00-abc-def-01"]
    )
}

private struct TestEchoPayload: Codable, Sendable {
    var text: String
}

private struct TestEchoOutput: Codable, Sendable {
    var text: String
}

private final class TestEchoWorker: HeddleWorker<TestEchoPayload, TestEchoOutput>, @unchecked Sendable {
    init() {
        super.init(workerType: "echo", tier: "local")
    }

    override func process(
        payload: TestEchoPayload,
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<TestEchoOutput> {
        WorkerOutput(output: TestEchoOutput(text: payload.text.uppercased()))
    }
}

private enum TestTimeout: Error {
    case timedOut
    case streamClosed
}

private func waitForSubscription(
    transport: InMemoryTransport,
    worker: TestEchoWorker
) async throws {
    for _ in 0..<500 {
        let count = await transport.subscriberCount(
            subject: worker.subject,
            queueGroup: worker.queueGroup
        )
        if count > 0 {
            return
        }

        try await Task.sleep(for: .milliseconds(10))
    }

    throw TestTimeout.timedOut
}

private func nextMessage(
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
