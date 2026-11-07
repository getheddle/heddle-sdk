// Language-native types for Heddle's v1 wire bodies (TaskMessage,
// TaskResult, OrchestratorGoal), the standalone CheckpointState, and the
// SDK-internal WorkerOutput<Output> ergonomic shape.
//
// The bodies mirror heddle/src/heddle/core/messages.py via
// schemas/v1/*.schema.json. They travel inside a WireEnvelope frame
// (Wire.swift) and are read and written only by HeddleWire, which applies
// the contract's strict typing; they are deliberately not Codable. When the
// upstream schemas change, run `python tools/sync_schemas.py --update
// --upstream ../heddle` from the repo root, align this file and Wire.swift,
// and re-run the fixture tests. See docs/CONTRACT_EVOLUTION.md.
//
// Bodies carry no timestamps and no Middleware-Lane keys: both live on the
// frame (WireEnvelope.occurredAt / recordedAt / lane).

import Foundation

/// Hint to the router about which class of LLM backend a task expects.
///
/// Heddle's router uses `(worker_type, model_tier)` as the
/// deterministic routing key. Foreign processor workers without an
/// LLM dependency typically run as `.local`; LLM workers may declare
/// a different tier so the router can dispatch to the appropriate
/// backend pool. The literal values are part of the wire contract.
public enum ModelTier: String, Codable, Sendable {
    case local
    case standard
    case frontier
}

/// Priority hint for scheduling and (future) preemption decisions.
///
/// Today Heddle's router treats priority as informational — it does
/// not preempt running tasks. The field is part of the wire contract
/// so producers and orchestrators can express intent that future
/// scheduling layers may honour.
public enum TaskPriority: String, Codable, Sendable {
    case low
    case normal
    case high
    case critical
}

/// Lifecycle state carried on `TaskResult`.
///
/// Worker code does not construct these directly when using
/// ``HeddleWorker``; the base class derives the right status from
/// the outcome of `process(payload:metadata:)` (`.completed` on
/// return, `.failed` on exception or validation error). `.pending`
/// and `.processing` are reserved for orchestrator-side state
/// tracking; workers do not emit them.
public enum TaskStatus: String, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
}

/// Body of a unit of work dispatched to a worker (`payload_type`
/// `core.TaskMessage`).
///
/// Mirrors `heddle.core.messages.TaskMessage`. Foreign processor workers
/// receive it, framed, on `heddle.tasks.{worker_type}.{tier}` and reply with
/// a framed ``TaskResult`` on `heddle.results.{parent_task_id or "default"}`.
///
/// Worker authors implementing ``HeddleWorker`` do not construct
/// `TaskMessage` themselves: the base class parses the frame, decodes
/// ``input`` into the worker's native `Payload` type, and passes it to
/// `process(payload:metadata:)`. Direct construction is for tests and
/// tooling; frame it with ``HeddleWire/wrap(_:lane:origin:correlationId:causationId:)``.
public struct TaskMessage: Equatable, Sendable {
    public var taskId: String
    public var parentTaskId: String?
    public var workerType: String
    /// The worker's input, as opaque JSON (formerly `payload`).
    public var input: [String: JSONValue]
    public var modelTier: ModelTier
    public var priority: TaskPriority
    public var requestId: String?
    public var metadata: [String: JSONValue]

    public init(
        taskId: String = UUID().uuidString.lowercased(),
        parentTaskId: String? = nil,
        workerType: String,
        input: [String: JSONValue],
        modelTier: ModelTier = .standard,
        priority: TaskPriority = .normal,
        requestId: String? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.taskId = taskId
        self.parentTaskId = parentTaskId
        self.workerType = workerType
        self.input = input
        self.modelTier = modelTier
        self.priority = priority
        self.requestId = requestId
        self.metadata = metadata
    }
}

/// Body of a worker's response to a ``TaskMessage`` (`payload_type`
/// `core.TaskResult`).
///
/// Mirrors `heddle.core.messages.TaskResult`. Worker authors do not
/// construct `TaskResult` directly: they return a ``WorkerOutput`` from
/// `process(payload:metadata:)`, and ``HeddleWorker`` assembles the result
/// (routing fields, status, timing, token usage) and frames it, copying the
/// inbound frame's Middleware Lane.
public struct TaskResult: Equatable, Sendable {
    public var taskId: String
    public var parentTaskId: String?
    public var workerType: String
    public var status: TaskStatus
    public var output: [String: JSONValue]?
    public var error: String?
    public var modelUsed: String?
    public var tokenUsage: [String: Int]
    public var metadata: [String: JSONValue]
    public var processingTimeMs: Int

    public init(
        taskId: String,
        parentTaskId: String? = nil,
        workerType: String,
        status: TaskStatus,
        output: [String: JSONValue]? = nil,
        error: String? = nil,
        modelUsed: String? = nil,
        tokenUsage: [String: Int] = [:],
        metadata: [String: JSONValue] = [:],
        processingTimeMs: Int = 0
    ) {
        self.taskId = taskId
        self.parentTaskId = parentTaskId
        self.workerType = workerType
        self.status = status
        self.output = output
        self.error = error
        self.modelUsed = modelUsed
        self.tokenUsage = tokenUsage
        self.metadata = metadata
        self.processingTimeMs = processingTimeMs
    }
}

/// Body of a higher-level goal handed to an orchestrator (`payload_type`
/// `core.OrchestratorGoal`).
///
/// Mirrors `heddle.core.messages.OrchestratorGoal`. Orchestration happens on
/// the Python side; the model exists so cross-language tooling (CLI clients,
/// scripted submitters) can submit goals on `heddle.goals.incoming`.
public struct OrchestratorGoal: Equatable, Sendable {
    public var goalId: String
    public var instruction: String
    public var context: [String: JSONValue]
    public var requestId: String?
    public var priority: TaskPriority

    public init(
        goalId: String = UUID().uuidString.lowercased(),
        instruction: String,
        context: [String: JSONValue] = [:],
        requestId: String? = nil,
        priority: TaskPriority = .normal
    ) {
        self.goalId = goalId
        self.instruction = instruction
        self.context = context
        self.requestId = requestId
        self.priority = priority
    }
}

/// Compressed orchestrator state captured for self-summarisation.
///
/// Mirrors `heddle.core.messages.CheckpointState`. It is stored, not
/// sent on the bus, so it is not framed; it stays `Codable`. Used by
/// Heddle's `CheckpointManager` on the Python side when an
/// orchestrator's conversation history exceeds a token threshold:
/// the manager compresses history into this structure and persists
/// it (typically to Valkey via the `checkpoint` KV store domain).
/// The orchestrator can then resume with a fresh context composed of
/// the checkpoint plus a recent-interactions window.
///
/// SDK consumers rarely construct this directly; the model exists
/// so foreign tooling can inspect checkpoint payloads on the wire.
public struct CheckpointState: Codable, Equatable, Sendable {
    public var goalId: String
    public var originalInstruction: String
    public var executiveSummary: String
    public var completedTasks: [[String: JSONValue]]
    public var pendingTasks: [[String: JSONValue]]
    public var openIssues: [String]
    public var decisionsMade: [String]
    public var contextTokenCount: Int
    public var checkpointNumber: Int
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case goalId = "goal_id"
        case originalInstruction = "original_instruction"
        case executiveSummary = "executive_summary"
        case completedTasks = "completed_tasks"
        case pendingTasks = "pending_tasks"
        case openIssues = "open_issues"
        case decisionsMade = "decisions_made"
        case contextTokenCount = "context_token_count"
        case checkpointNumber = "checkpoint_number"
        case createdAt = "created_at"
    }

    public init(
        goalId: String = "",
        originalInstruction: String = "",
        executiveSummary: String = "",
        completedTasks: [[String: JSONValue]] = [],
        pendingTasks: [[String: JSONValue]] = [],
        openIssues: [String] = [],
        decisionsMade: [String] = [],
        contextTokenCount: Int = 0,
        checkpointNumber: Int = 0,
        createdAt: String = HeddleClock.nowIso8601()
    ) {
        self.goalId = goalId
        self.originalInstruction = originalInstruction
        self.executiveSummary = executiveSummary
        self.completedTasks = completedTasks
        self.pendingTasks = pendingTasks
        self.openIssues = openIssues
        self.decisionsMade = decisionsMade
        self.contextTokenCount = contextTokenCount
        self.checkpointNumber = checkpointNumber
        self.createdAt = createdAt
    }
}

/// SDK-ergonomic return type for ``HeddleWorker/process(payload:metadata:)``.
/// **Not a wire type.**
///
/// ## What it is
///
/// A small typed wrapper around the worker's domain output
/// (``output``) plus optional metrics (``modelUsed``, ``tokenUsage``,
/// ``metadata``). Worker authors construct one and return it from
/// `process(payload:metadata:)`.
///
/// ## What it is not
///
/// A wire envelope. `WorkerOutput` is never serialised onto the
/// Heddle bus. The wire body for a worker's response is
/// ``TaskResult``, framed by a ``WireEnvelope``: routing fields (task
/// ID, parent task ID, worker type), lifecycle status, timing, and
/// the Middleware Lane — fields the worker shouldn't have to think
/// about.
/// ``HeddleWorker`` is the bridge: it receives a
/// ``TaskMessage``, calls `process(payload:metadata:)`, and assembles
/// a ``TaskResult`` from the returned `WorkerOutput` plus the
/// inbound envelope's routing context.
///
/// ## Why split it out
///
/// The alternative — having `process(payload:metadata:)` return
/// ``TaskResult`` directly — would force worker authors to populate
/// every routing and timing field on every call, duplicating work
/// the base class can do once. Worse, mistakes in those fields
/// (a wrong taskId, a dropped Middleware-Lane key) would
/// silently break message routing or tracing. Centralising the
/// envelope construction in the base class makes the worker's job
/// "produce typed output + optional metrics" and nothing else.
///
/// ## Cross-language equivalence (C6)
///
/// The .NET SDK defines a parallel `WorkerOutput<TOutput>` with the
/// same role. The two diverge on idiom — .NET uses
/// `Dictionary<string, long>?` and `JsonObject?` (nullable with
/// null-default), Swift uses non-optional types defaulting to empty
/// collections. Both produce the same wire output: each base class
/// normalises them when assembling the `TaskResult`. The difference is language-idiomatic, not a contract
/// divergence.
///
/// - Parameters:
///   - Output: The worker's typed domain output. Must serialise to a
///     JSON object (the base class checks this and fails the task
///     with a clear error if the serialised form is anything other
///     than an object).
public struct WorkerOutput<Output: Encodable & Sendable>: Sendable {
    /// The worker's typed domain output. Required.
    public var output: Output
    /// Optional identifier of the LLM model used to produce this
    /// output, for workers that delegate to an LLM. Surfaces in the
    /// ``TaskResult/modelUsed`` field of the wire envelope.
    public var modelUsed: String?
    /// Optional token-usage metrics. As upstream, the result carries
    /// exactly `prompt_tokens` and `completion_tokens` in
    /// ``TaskResult/tokenUsage``, each defaulting to 0; other keys are
    /// not carried. Default empty.
    public var tokenUsage: [String: Int]
    /// Optional free-form per-task metadata. Surfaces in
    /// ``TaskResult/metadata``. Use for worker-specific diagnostics,
    /// intermediate confidence scores, etc. — anything that should
    /// travel with the result but isn't part of the typed
    /// ``output``. Default empty.
    public var metadata: [String: JSONValue]

    public init(
        output: Output,
        modelUsed: String? = nil,
        tokenUsage: [String: Int] = [:],
        metadata: [String: JSONValue] = [:]
    ) {
        self.output = output
        self.modelUsed = modelUsed
        self.tokenUsage = tokenUsage
        self.metadata = metadata
    }
}

public enum HeddleClock {
    public static func nowIso8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
