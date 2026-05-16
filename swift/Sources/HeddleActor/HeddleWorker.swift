import Foundation

/// Transport-agnostic base class for foreign processor workers.
/// Subclass, override `process(payload:metadata:)`, and call
/// `run(transport:)` against any `HeddleTransport`.
///
/// ## What you implement
///
/// The `process(payload:metadata:)` method (overridden in your
/// subclass — the base implementation calls `fatalError`). You
/// receive a typed `Payload` deserialised from the inbound
/// ``TaskMessage/payload``, plus the task's metadata dictionary. You
/// return a ``WorkerOutput`` containing your typed domain output and
/// optional metrics.
///
/// ## What the base class handles for you
///
/// - Subscribing to the right wire subject
///   (`heddle.tasks.{worker_type}.{tier}`) with the right queue
///   group (`processors-{worker_type}`).
/// - Decoding inbound ``TaskMessage`` bytes and skipping malformed
///   messages without crashing the subscription loop (calls
///   ``malformedMessage(_:)`` for hooks).
/// - Shallow JSON-Schema validation of the input payload against
///   ``inputSchema``, if provided.
/// - Deserialising the payload to `Payload`.
/// - Calling `process(payload:metadata:)`.
/// - Encoding the output and shallow-validating against
///   ``outputSchema``, if provided.
/// - Constructing the wire ``TaskResult`` envelope: copying routing
///   fields from the inbound task (``TaskMessage/taskId``,
///   ``TaskMessage/parentTaskId``, ``TaskMessage/workerType``),
///   propagating ``TaskMessage/traceContext``, measuring elapsed
///   time, pulling typed output + metrics from your
///   ``WorkerOutput``.
/// - Publishing the result to
///   `heddle.results.{parent_task_id or "default"}`.
/// - Calling ``reset()`` between tasks — workers are stateless in
///   every language SDK (cross-repo invariant C3); the base class
///   enforces this regardless of your subclass discipline.
/// - Converting thrown errors during `process(payload:metadata:)`
///   into ``TaskResult`` with ``TaskStatus/failed`` plus the error
///   description. Processing failures never crash the worker; the
///   subscription loop continues.
///
/// ## What you DON'T do
///
/// Construct ``TaskMessage`` or ``TaskResult`` directly, manage
/// subscription lifecycles, emit trace spans (that's the OTel
/// layer's job), or persist state between tasks (workers are
/// stateless).
///
/// ## Transports
///
/// Ship as separate packages. `swift-nats` provides a live NATS
/// adapter; `InMemoryTransport` is for tests and same-process
/// examples. The base class is transport-agnostic by design
/// (cross-repo invariant C5).
///
/// - Parameters:
///   - Payload: The native type for the worker's input payload. Must
///     be `Decodable` from the JSON object on `TaskMessage.payload`.
///   - Output: The native type for the worker's output. Must
///     `Encodable`-serialise to a JSON object (the base class checks
///     this and fails the task with a clear error if not).
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

    /// Implement this. Process one typed payload and return one typed
    /// output (wrapped in ``WorkerOutput`` for optional metrics).
    ///
    /// - Parameters:
    ///   - payload: The deserialised inbound payload. Has already
    ///     passed shallow input-schema validation if ``inputSchema``
    ///     was set.
    ///   - metadata: Free-form per-task metadata attached by the
    ///     producer (typically orchestrator-level routing hints,
    ///     retry counters, etc.). Pass through or ignore.
    /// - Returns: A ``WorkerOutput`` containing the typed domain
    ///   output plus optional model / usage / metadata fields. The
    ///   base class transforms this into the wire ``TaskResult``.
    /// - Throws: Throw on processing failure. The base class converts
    ///   thrown errors into ``TaskResult`` with ``TaskStatus/failed``
    ///   and the error description; the subscription loop is
    ///   unaffected. Do not catch errors just to swallow them —
    ///   return-with-error is what the wire contract expects.
    ///
    /// The default implementation calls `fatalError`. Override in
    /// every concrete worker subclass.
    open func process(
        payload: Payload,
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<Output> {
        fatalError("Subclasses must implement process(payload:metadata:)")
    }

    /// Optional hook called between tasks to clear any state that
    /// crept in during ``process(payload:metadata:)``. Workers are
    /// stateless in every language SDK (cross-repo invariant C3);
    /// override this if your subclass holds per-task scratch state
    /// (caches, buffers) that must be reset.
    ///
    /// The base class calls this unconditionally after every task,
    /// success or failure. Default implementation is a no-op.
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

    /// Optional hook called when the inbound transport message can't
    /// be decoded as a ``TaskMessage``. Override to log, emit a
    /// metric, or report to a dead-letter sink.
    ///
    /// Malformed messages are skipped, not process-fatal — the
    /// subscription loop continues. This mirrors Heddle's framework
    /// invariant: a single bad message must not take down a worker
    /// replica.
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
