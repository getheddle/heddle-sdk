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
