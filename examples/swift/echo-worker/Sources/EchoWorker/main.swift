import Foundation
import HeddleActor

struct EchoPayload: Codable, Sendable {
    var text: String
}

struct EchoOutput: Codable, Sendable {
    var text: String
    var length: Int
}

final class EchoWorker: HeddleWorker<EchoPayload, EchoOutput>, @unchecked Sendable {
    init() {
        super.init(
            workerType: "echo",
            tier: "local",
            inputSchema: [
                "type": .string("object"),
                "required": .array([.string("text")]),
                "properties": .object([
                    "text": .object(["type": .string("string")])
                ]),
            ],
            outputSchema: [
                "type": .string("object"),
                "required": .array([.string("text"), .string("length")]),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                    "length": .object(["type": .string("integer")]),
                ]),
            ]
        )
    }

    override func process(
        payload: EchoPayload,
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<EchoOutput> {
        WorkerOutput(
            output: EchoOutput(
                text: payload.text.uppercased(),
                length: payload.text.count
            ),
            modelUsed: "swift-example",
            metadata: ["example": .string("echo-worker")]
        )
    }
}

let task = TaskMessage(
    taskId: "task-echo-1",
    parentTaskId: "goal-demo-1",
    workerType: "echo",
    payload: ["text": .string("hello from Swift")],
    modelTier: .local,
    traceContext: [
        "traceparent": "00-00000000000000000000000000000000-0000000000000000-01"
    ]
)

let result = await EchoWorker().handle(task)
let data = try HeddleCoders.encode(result)
print(String(decoding: data, as: UTF8.self))
