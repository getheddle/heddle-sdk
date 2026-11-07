import Foundation
import Testing
@testable import HeddleActor

@Test func workerRunPublishesFramedResultCarryingTheLane() async throws {
    let inbound = makeTaskFrame()
    let (envelope, body) = try await roundTrip(TestEchoWorker(), try HeddleWire.serialize(inbound))
    guard case let .taskResult(result) = body else {
        Issue.record("expected a TaskResult")
        return
    }

    #expect(envelope.payloadType == PayloadTypes.taskResult)
    #expect(envelope.messageId != inbound.messageId)
    #expect(envelope.occurredAt == envelope.recordedAt)
    #expect(envelope.origin == nil && envelope.correlationId == nil && envelope.causationId == nil)
    #expect(envelope.lane == inbound.lane)

    #expect(result.taskId == "task-1")
    #expect(result.parentTaskId == "goal-1")
    #expect(result.workerType == "echo")
    #expect(result.status == .completed)
    #expect(result.output?["text"] == .string("HELLO"))
    #expect(result.tokenUsage.keys.sorted() == ["completion_tokens", "prompt_tokens"])
    #expect(result.metadata["seen_tier"] == .string("local"))
}

@Test func inputValidationFailurePublishesFailedResult() async throws {
    let frame = makeTaskFrame(input: ["wrong": .int(1)])
    let (_, body) = try await roundTrip(TestEchoWorker(), try HeddleWire.serialize(frame))
    guard case let .taskResult(result) = body else {
        Issue.record("expected a TaskResult")
        return
    }
    #expect(result.status == .failed)
    #expect(result.error?.hasPrefix("Input validation:") == true)
    #expect(result.tokenUsage.keys.sorted() == ["completion_tokens", "prompt_tokens"])
}

@Test(arguments: [
    (#"{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"text":"hi"}},"bogus":1}"#, WireLayer.frame),
    (#"{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"text":"hi"}},"occurred_at":"2026-01-01T00:00:00"}"#, WireLayer.frame),
    (#"{"payload_type":"core.TaskMessage","payload":{"input":{"text":"hi"}}}"#, WireLayer.body),
    (#"{"payload_type":"core.TaskResult","payload":{"task_id":"t","worker_type":"echo","status":"completed"}}"#, WireLayer.dispatch),
    (#"{"payload_type":"events.Event","payload":{}}"#, WireLayer.dispatch),
    ("not json", WireLayer.frame),
])
func malformedMessagesAreSkippedAndTheLoopContinues(raw: String, layer: WireLayer) async throws {
    let worker = TestEchoWorker()
    let transport = InMemoryTransport()
    let results = try await transport.subscribe(subject: HeddleSubjects.results(parentTaskId: "goal-1"), queueGroup: nil)
    let loop = Task { try await worker.run(transport: transport) }
    try await waitForSubscription(transport, worker)

    try await transport.publish(subject: worker.subject, payload: Data(raw.utf8))
    try await transport.publish(subject: worker.subject, payload: try HeddleWire.serialize(makeTaskFrame()))

    let (_, body) = try HeddleWire.parse(try await nextMessage(from: results).payload)
    guard case let .taskResult(result) = body else {
        Issue.record("expected a TaskResult")
        return
    }
    #expect(result.status == .completed)
    let malformed = await worker.recorder.errors
    #expect(malformed.count == 1)
    #expect((malformed.first as? WireFormatError)?.layer == layer)

    await transport.close()
    loop.cancel()
    _ = try? await loop.value
}

@Test(arguments: [
    "valid/task_message_full.json",
    "valid/task_message_middleware_lane.json",
    "valid/task_message_minimal_defaults.json",
    "valid/task_message_unknown_body_key.json",
])
func everyValidTaskFixtureYieldsAParseableResult(file: String) async throws {
    let data = try Fixtures.data(file)
    let inbound = try HeddleWire.parseFrame(data)
    guard case let .taskMessage(task) = try HeddleWire.parseBody(inbound) else {
        Issue.record("expected a TaskMessage")
        return
    }
    let worker = PassThroughWorker(workerType: task.workerType, tier: task.modelTier.rawValue)
    let (envelope, body) = try await roundTrip(worker, data, parentTaskId: task.parentTaskId)
    guard case let .taskResult(result) = body else {
        Issue.record("expected a TaskResult")
        return
    }
    #expect(envelope.payloadType == PayloadTypes.taskResult)
    #expect(result.taskId == task.taskId)
    #expect(envelope.lane == inbound.lane)
}

@Test func unserializableOutputPublishesFailedResult() async throws {
    let (_, body) = try await roundTrip(NaNWorker(workerType: "echo", tier: "local"), try HeddleWire.serialize(makeTaskFrame()))
    guard case let .taskResult(result) = body else {
        Issue.record("expected a TaskResult")
        return
    }
    #expect(result.status == .failed)
    #expect(result.output == nil)
    #expect(result.error?.isEmpty == false)
}

private final class NaNWorker: HeddleWorker<[String: JSONValue], [String: Double]>, @unchecked Sendable {
    override func process(
        payload: [String: JSONValue],
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<[String: Double]> {
        WorkerOutput(output: ["score": .nan])
    }
}

// MARK: - Helpers

private func roundTrip<P, O>(
    _ worker: HeddleWorker<P, O>,
    _ frame: Data,
    parentTaskId: String? = "goal-1"
) async throws -> (WireEnvelope, WireBody) {
    let transport = InMemoryTransport()
    let results = try await transport.subscribe(subject: HeddleSubjects.results(parentTaskId: parentTaskId), queueGroup: nil)
    let loop = Task { try await worker.run(transport: transport) }
    try await waitForSubscription(transport, worker)
    try await transport.publish(subject: worker.subject, payload: frame)
    let message = try await nextMessage(from: results)
    await transport.close()
    loop.cancel()
    _ = try? await loop.value
    return try HeddleWire.parse(message.payload)
}

private func waitForSubscription<P, O>(_ transport: InMemoryTransport, _ worker: HeddleWorker<P, O>) async throws {
    for _ in 0..<500 {
        if await transport.subscriberCount(subject: worker.subject, queueGroup: worker.queueGroup) > 0 {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw TestTimeout.timedOut
}

private func makeTaskFrame(input: [String: JSONValue] = ["text": .string("hello")]) -> WireEnvelope {
    let task = TaskMessage(taskId: "task-1", parentTaskId: "goal-1", workerType: "echo", input: input, modelTier: .local)
    return HeddleWire.wrap(
        .taskMessage(task),
        lane: [
            "_trace_context": .object(["traceparent": .string("00-abc-def-01")]),
            "_x_custom": .array([.int(1), .string("two"), .null]),
        ],
        origin: "test",
        correlationId: "corr-1"
    )
}

private struct EchoPayload: Codable, Sendable {
    var text: String
}

private struct EchoOutput: Codable, Sendable {
    var text: String
    var length: Int
}

private actor ErrorRecorder {
    var errors: [Error] = []
    func record(_ error: Error) { errors.append(error) }
}

private final class TestEchoWorker: HeddleWorker<EchoPayload, EchoOutput>, @unchecked Sendable {
    let recorder = ErrorRecorder()

    init() {
        super.init(
            workerType: "echo",
            tier: "local",
            inputSchema: [
                "type": .string("object"),
                "required": .array([.string("text")]),
                "properties": .object(["text": .object(["type": .string("string")])]),
            ]
        )
    }

    override func process(payload: EchoPayload, metadata: [String: JSONValue]) async throws -> WorkerOutput<EchoOutput> {
        WorkerOutput(
            output: EchoOutput(text: payload.text.uppercased(), length: payload.text.count),
            metadata: ["seen_tier": metadata["model_tier"] ?? .null]
        )
    }

    override func malformedMessage(_ error: Error) async {
        await recorder.record(error)
    }
}

private final class PassThroughWorker: HeddleWorker<[String: JSONValue], [String: JSONValue]>, @unchecked Sendable {
    override func process(
        payload: [String: JSONValue],
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<[String: JSONValue]> {
        WorkerOutput(output: payload)
    }
}
