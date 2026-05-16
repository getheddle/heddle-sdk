// Language-native types mirroring Heddle's wire-protocol envelopes
// (TaskMessage, TaskResult, OrchestratorGoal, CheckpointState) plus
// the SDK-internal WorkerOutput<Output> ergonomic shape.
//
// The wire envelopes are vendored from the canonical Pydantic models
// at heddle/src/heddle/core/messages.py via schemas/v1/*.schema.json.
// These Swift structs are derived; do not edit them in isolation.
// When the upstream schema changes, run `python tools/sync_schemas.py
// --update --upstream ../heddle` from the repo root and align this
// file with the regenerated schemas. See docs/CONTRACT_EVOLUTION.md.
//
// Field naming convention: camelCase Swift properties with explicit
// `CodingKeys` mapping to snake_case wire names. The wire form is
// authoritative.
//
// Underscore-prefixed wire keys (e.g. `_trace_context`) are the
// reserved middleware lane — see
// heddle-agent-toolkit/anchors/CONTRACT_MAP.md "Reserved middleware
// lane." SDKs preserve them on inbound and outbound envelopes; they
// are not part of the application contract.

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

/// Wire envelope for a unit of work dispatched to a worker.
///
/// Vendored from `heddle.core.messages.TaskMessage`. Foreign
/// processor workers receive a serialised `TaskMessage` from
/// `heddle.tasks.{worker_type}.{tier}` and reply with a ``TaskResult``
/// on `heddle.results.{parent_task_id or "default"}`.
///
/// Worker authors implementing ``HeddleWorker`` do not construct
/// `TaskMessage` themselves: the base class decodes it from the
/// inbound transport, deserialises ``payload`` into the worker's
/// native `Payload` type, and passes that typed payload to
/// `process(payload:metadata:)`. Direct construction is mostly for
/// tests and tooling.
public struct TaskMessage: Codable, Equatable, Sendable {
    public var taskId: String
    public var parentTaskId: String?
    public var workerType: String
    public var payload: [String: JSONValue]
    public var modelTier: ModelTier
    public var priority: TaskPriority
    public var createdAt: String
    public var requestId: String?
    public var metadata: [String: JSONValue]
    public var traceContext: [String: String]?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case parentTaskId = "parent_task_id"
        case workerType = "worker_type"
        case payload
        case modelTier = "model_tier"
        case priority
        case createdAt = "created_at"
        case requestId = "request_id"
        case metadata
        case traceContext = "_trace_context"
    }

    public init(
        taskId: String = UUID().uuidString,
        parentTaskId: String? = nil,
        workerType: String,
        payload: [String: JSONValue],
        modelTier: ModelTier = .standard,
        priority: TaskPriority = .normal,
        createdAt: String = HeddleClock.nowIso8601(),
        requestId: String? = nil,
        metadata: [String: JSONValue] = [:],
        traceContext: [String: String]? = nil
    ) {
        self.taskId = taskId
        self.parentTaskId = parentTaskId
        self.workerType = workerType
        self.payload = payload
        self.modelTier = modelTier
        self.priority = priority
        self.createdAt = createdAt
        self.requestId = requestId
        self.metadata = metadata
        self.traceContext = traceContext
    }
}

/// Wire envelope for a worker's response to a ``TaskMessage``.
///
/// Vendored from `heddle.core.messages.TaskResult`. Published by the
/// worker on `heddle.results.{parent_task_id or "default"}` after
/// `process(payload:metadata:)` returns (or throws / fails
/// validation, in which case ``status`` is `.failed` and ``error``
/// describes the cause).
///
/// Worker authors do not construct `TaskResult` directly. They
/// return a ``WorkerOutput`` from `process(payload:metadata:)`, and
/// ``HeddleWorker/handle(_:)-3xkrt`` assembles the `TaskResult`,
/// filling in routing fields (``taskId``, ``parentTaskId``,
/// ``workerType``), timing (``processingTimeMs``), status, and
/// propagated ``traceContext``. This separation keeps worker code
/// focused on domain output while the SDK owns the wire envelope.
public struct TaskResult: Codable, Equatable, Sendable {
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
    public var completedAt: String
    public var traceContext: [String: String]?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case parentTaskId = "parent_task_id"
        case workerType = "worker_type"
        case status
        case output
        case error
        case modelUsed = "model_used"
        case tokenUsage = "token_usage"
        case metadata
        case processingTimeMs = "processing_time_ms"
        case completedAt = "completed_at"
        case traceContext = "_trace_context"
    }

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
        processingTimeMs: Int = 0,
        completedAt: String = HeddleClock.nowIso8601(),
        traceContext: [String: String]? = nil
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
        self.completedAt = completedAt
        self.traceContext = traceContext
    }
}

/// Wire envelope for a higher-level goal handed to an orchestrator.
///
/// Vendored from `heddle.core.messages.OrchestratorGoal`. SDKs can
/// deserialise this envelope but the typical foreign-processor-worker
/// flow doesn't construct one — orchestration happens on the Python
/// side. Provided so cross-language tooling (CLI clients, scripted
/// submitters) can encode goals in the same byte-identical form
/// Heddle's orchestrators expect.
public struct OrchestratorGoal: Codable, Equatable, Sendable {
    public var goalId: String
    public var instruction: String
    public var context: [String: JSONValue]
    public var requestId: String?
    public var priority: TaskPriority
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case goalId = "goal_id"
        case instruction
        case context
        case requestId = "request_id"
        case priority
        case createdAt = "created_at"
    }
}

/// Compressed orchestrator state captured for self-summarisation.
///
/// Vendored from `heddle.core.messages.CheckpointState`. Used by
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
/// Heddle bus. The wire envelope for a worker's response is
/// ``TaskResult``, which carries routing fields (task ID, parent
/// task ID, worker type), lifecycle status, timing, and trace
/// context — fields the worker shouldn't have to think about.
/// ``HeddleWorker/handle(_:)-3xkrt`` is the bridge: it receives a
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
/// (a wrong taskId, a missing traceContext propagation) would
/// silently break message routing or tracing. Centralising the
/// envelope construction in the base class makes the worker's job
/// "produce typed output + optional metrics" and nothing else.
///
/// ## Cross-language equivalence (C6)
///
/// The .NET SDK defines a parallel `WorkerOutput<TOutput>` with the
/// same role. The two diverge on idiom — .NET uses
/// `Dictionary<string, int>?` and `JsonObject?` (nullable with
/// null-default), Swift uses non-optional types defaulting to empty
/// collections. Both produce the same wire output: the .NET base
/// class normalises nulls to empty collections when assembling the
/// `TaskResult`, and Swift's empty defaults serialise to the same
/// wire shape. The difference is language-idiomatic, not a contract
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
    /// Optional token-usage metrics (typical keys: `prompt_tokens`,
    /// `completion_tokens`). Surfaces in ``TaskResult/tokenUsage``.
    /// Default empty.
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

