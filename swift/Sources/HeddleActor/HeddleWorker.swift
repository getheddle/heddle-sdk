import Foundation

open class HeddleWorker<Payload: Decodable & Sendable, Output: Encodable & Sendable>: @unchecked Sendable {
    public let workerType: String
    public let tier: String
    public let inputSchema: [String: JSONValue]?
    public let outputSchema: [String: JSONValue]?

    public init(
        workerType: String,
        tier: String = "local",
        inputSchema: [String: JSONValue]? = nil,
        outputSchema: [String: JSONValue]? = nil
    ) {
        self.workerType = workerType
        self.tier = tier
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
    }

    public var subject: String {
        HeddleSubjects.workerTasks(workerType: workerType, tier: tier)
    }

    public var queueGroup: String {
        HeddleSubjects.processorQueueGroup(workerType: workerType)
    }

    open func process(
        payload: Payload,
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<Output> {
        fatalError("Subclasses must implement process(payload:metadata:)")
    }

    open func reset() async {}

    public func run(transport: HeddleTransport) async throws {
        let stream = try await transport.subscribe(subject: subject, queueGroup: queueGroup)
        for try await message in stream {
            guard let result = await handle(message.payload) else {
                continue
            }
            let data = try HeddleCoders.encode(result)
            try await transport.publish(
                subject: HeddleSubjects.results(parentTaskId: result.parentTaskId),
                payload: data
            )
        }
    }

    public func handle(_ data: Data) async -> TaskResult? {
        do {
            let task = try HeddleCoders.decode(TaskMessage.self, from: data)
            return await handle(task)
        } catch {
            await malformedMessage(error)
            return nil
        }
    }

    public func handle(_ task: TaskMessage) async -> TaskResult {
        let result: TaskResult
        do {
            result = try await handleCore(task)
        } catch {
            result = failure(task, error: error.localizedDescription)
        }
        await reset()
        return result
    }

    open func malformedMessage(_ error: Error) async {}

    private func handleCore(_ task: TaskMessage) async throws -> TaskResult {
        let inputErrors = ShallowSchemaValidator.validate(
            data: task.payload,
            schema: inputSchema,
            context: "input"
        )
        if !inputErrors.isEmpty {
            return failure(task, error: "Input validation: \(inputErrors.joined(separator: "; "))")
        }

        let payloadData = try HeddleCoders.encode(task.payload)
        let payload = try HeddleCoders.decode(Payload.self, from: payloadData)
        let started = ContinuousClock.now
        let processed = try await process(payload: payload, metadata: task.metadata)
        let elapsed = started.duration(to: .now)

        let outputData = try HeddleCoders.encode(processed.output)
        let outputValue = try HeddleCoders.decode(JSONValue.self, from: outputData)
        guard case let .object(outputObject) = outputValue else {
            return failure(task, error: "Worker output must serialize to a JSON object")
        }

        let outputErrors = ShallowSchemaValidator.validate(
            data: outputObject,
            schema: outputSchema,
            context: "output"
        )
        if !outputErrors.isEmpty {
            return failure(task, error: "Output validation: \(outputErrors.joined(separator: "; "))")
        }

        return TaskResult(
            taskId: task.taskId,
            parentTaskId: task.parentTaskId,
            workerType: task.workerType,
            status: .completed,
            output: outputObject,
            error: nil,
            modelUsed: processed.modelUsed,
            tokenUsage: processed.tokenUsage,
            metadata: processed.metadata,
            processingTimeMs: durationMillis(elapsed),
            traceContext: task.traceContext
        )
    }

    private func failure(_ task: TaskMessage, error: String) -> TaskResult {
        TaskResult(
            taskId: task.taskId,
            parentTaskId: task.parentTaskId,
            workerType: task.workerType,
            status: .failed,
            error: error,
            traceContext: task.traceContext
        )
    }
}

public enum HeddleCoders {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

private func durationMillis(_ duration: Duration) -> Int {
    let components = duration.components
    let seconds = components.seconds * 1_000
    let fractional = components.attoseconds / 1_000_000_000_000_000
    return Int(seconds + fractional)
}
