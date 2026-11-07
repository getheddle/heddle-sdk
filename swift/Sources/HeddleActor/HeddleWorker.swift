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
/// ``TaskMessage/input``, plus the task's metadata dictionary (with
/// `model_tier` added, as upstream). You
/// return a ``WorkerOutput`` containing your typed domain output and
/// optional metrics.
///
/// ## What the base class handles for you
///
/// - Subscribing to the right wire subject
///   (`heddle.tasks.{worker_type}.{tier}`) with the right queue
///   group (`processors-{worker_type}`).
/// - Parsing the inbound ``WireEnvelope`` frame and its ``TaskMessage``
///   body, and skipping malformed messages (invalid frame, invalid
///   body, or any `payload_type` other than `core.TaskMessage`) without
///   crashing the subscription loop (calls ``malformedMessage(_:)`` for
///   hooks).
/// - Shallow JSON-Schema validation of the input payload against
///   ``inputSchema``, if provided.
/// - Deserialising the payload to `Payload`.
/// - Calling `process(payload:metadata:)`.
/// - Encoding the output and shallow-validating against
///   ``outputSchema``, if provided.
/// - Constructing the ``TaskResult`` body: copying routing fields from
///   the inbound task (``TaskMessage/taskId``,
///   ``TaskMessage/parentTaskId``, ``TaskMessage/workerType``),
///   measuring elapsed time, and pulling typed output and metrics from
///   your ``WorkerOutput``.
/// - Framing the result with a fresh `message_id` and timestamps,
///   copying every `_`-prefixed Middleware-Lane key (for example
///   `_trace_context`) from the inbound frame, and publishing it to
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
///     be `Decodable` from the JSON object in `TaskMessage.input`.
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
            guard let frame = await handle(message.payload) else {
                continue
            }
            guard case let .taskResult(result) = try HeddleWire.parseBody(frame) else { continue }
            try await transport.publish(
                subject: HeddleSubjects.results(parentTaskId: result.parentTaskId),
                payload: try HeddleWire.serialize(frame)
            )
        }
    }

    /// Handle one inbound transport message: parse the frame, run the task,
    /// and return the framed result. Returns `nil` (after calling
    /// ``malformedMessage(_:)``) when the message is not a valid framed
    /// ``TaskMessage``.
    public func handle(_ data: Data) async -> WireEnvelope? {
        let envelope: WireEnvelope
        let task: TaskMessage
        do {
            envelope = try HeddleWire.parseFrame(data)
            guard envelope.payloadType == PayloadTypes.taskMessage else {
                throw WireFormatError(
                    .dispatch,
                    "expected payload_type '\(PayloadTypes.taskMessage)' on a task subject, got '\(envelope.payloadType)'"
                )
            }
            guard case let .taskMessage(body) = try HeddleWire.parseBody(envelope) else {
                throw WireFormatError(.dispatch, "not a task message")
            }
            task = body
        } catch {
            await malformedMessage(error)
            return nil
        }
        let result = await handle(task)
        return HeddleWire.wrap(.taskResult(result), lane: envelope.lane)
    }

    /// Run one task through validation, `process(payload:metadata:)` and
    /// result assembly. Never throws for a processing failure: the result
    /// has ``TaskStatus/failed`` instead.
    public func handle(_ task: TaskMessage) async -> TaskResult {
        let started = ContinuousClock.now
        let elapsed = { durationMillis(started.duration(to: .now)) }
        let result: TaskResult
        do {
            result = try await handleCore(task, elapsed: elapsed)
        } catch {
            result = Self.result(task, .failed, elapsed(), error: String(describing: error))
        }
        await reset()
        return result
    }

    /// Optional hook called when the inbound transport message is not a
    /// valid framed ``TaskMessage``. The error is a ``WireFormatError``
    /// naming the rejecting layer. Override to log, emit a
    /// metric, or report to a dead-letter sink.
    ///
    /// Malformed messages are skipped, not process-fatal — the
    /// subscription loop continues. This mirrors Heddle's framework
    /// invariant: a single bad message must not take down a worker
    /// replica.
    open func malformedMessage(_ error: Error) async {}

    private func handleCore(_ task: TaskMessage, elapsed: () -> Int) async throws -> TaskResult {
        let inputErrors = ShallowSchemaValidator.validate(
            data: task.input,
            schema: inputSchema,
            context: "input"
        )
        if !inputErrors.isEmpty {
            return Self.result(task, .failed, elapsed(), error: "Input validation: \(inputErrors.joined(separator: "; "))")
        }

        let payloadData = try HeddleCoders.encode(task.input)
        let payload = try HeddleCoders.decode(Payload.self, from: payloadData)
        var metadata = task.metadata
        metadata["model_tier"] = .string(task.modelTier.rawValue)
        let processed = try await process(payload: payload, metadata: metadata)

        let outputData = try HeddleCoders.encode(processed.output)
        let outputValue = try HeddleCoders.decode(JSONValue.self, from: outputData)
        guard case let .object(outputObject) = outputValue else {
            return Self.result(task, .failed, elapsed(), error: "Worker output must serialize to a JSON object",
                               modelUsed: processed.modelUsed, tokens: processed.tokenUsage)
        }

        let outputErrors = ShallowSchemaValidator.validate(
            data: outputObject,
            schema: outputSchema,
            context: "output"
        )
        if !outputErrors.isEmpty {
            return Self.result(task, .failed, elapsed(), error: "Output validation: \(outputErrors.joined(separator: "; "))",
                               modelUsed: processed.modelUsed, tokens: processed.tokenUsage)
        }

        return Self.result(task, .completed, elapsed(), output: outputObject,
                           modelUsed: processed.modelUsed, tokens: processed.tokenUsage, metadata: processed.metadata)
    }

    // Mirrors heddle.worker.base._publish_result: token_usage always carries
    // exactly prompt_tokens and completion_tokens, and metadata comes from the
    // worker's output (never the task's).
    private static func result(
        _ task: TaskMessage,
        _ status: TaskStatus,
        _ elapsedMs: Int,
        output: [String: JSONValue]? = nil,
        error: String? = nil,
        modelUsed: String? = nil,
        tokens: [String: Int] = [:],
        metadata: [String: JSONValue] = [:]
    ) -> TaskResult {
        TaskResult(
            taskId: task.taskId,
            parentTaskId: task.parentTaskId,
            workerType: task.workerType,
            status: status,
            output: output,
            error: error,
            modelUsed: modelUsed,
            tokenUsage: [
                "prompt_tokens": tokens["prompt_tokens"] ?? 0,
                "completion_tokens": tokens["completion_tokens"] ?? 0,
            ],
            metadata: metadata,
            processingTimeMs: elapsedMs
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
