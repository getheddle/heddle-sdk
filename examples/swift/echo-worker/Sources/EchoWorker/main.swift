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

enum ExampleError: Error {
    case timedOutWaitingForSubscription
    case timedOutWaitingForResult
    case resultStreamClosed
}

func waitForWorkerSubscription(
    transport: InMemoryTransport,
    worker: EchoWorker
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

    throw ExampleError.timedOutWaitingForSubscription
}

func firstResult(
    from stream: AsyncThrowingStream<HeddleMessage, Error>
) async throws -> HeddleMessage {
    try await withThrowingTaskGroup(of: HeddleMessage.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let message = try await iterator.next() else {
                throw ExampleError.resultStreamClosed
            }
            return message
        }

        group.addTask {
            try await Task.sleep(for: .seconds(5))
            throw ExampleError.timedOutWaitingForResult
        }

        let message = try await group.next()!
        group.cancelAll()
        return message
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

let worker = EchoWorker()
let transport = InMemoryTransport()
let results = try await transport.subscribe(
    subject: HeddleSubjects.results(parentTaskId: task.parentTaskId),
    queueGroup: nil
)

let workerLoop = Task {
    try await worker.run(transport: transport)
}

try await waitForWorkerSubscription(transport: transport, worker: worker)
try await transport.publish(
    subject: worker.subject,
    payload: HeddleCoders.encode(task)
)

let message = try await firstResult(from: results)
let result = try HeddleCoders.decode(TaskResult.self, from: message.payload)
let data = try HeddleCoders.encode(result)
print(String(decoding: data, as: UTF8.self))

await transport.close()
workerLoop.cancel()
_ = try? await workerLoop.value
