// Language-native types mirroring Heddle's wire-protocol envelopes
// (TaskMessage, TaskResult, OrchestratorGoal, CheckpointState) plus
// the SDK-internal WorkerOutput<T> ergonomic shape.
//
// The wire envelopes are vendored from the canonical Pydantic models
// at heddle/src/heddle/core/messages.py via schemas/v1/*.schema.json.
// These C# records are derived; do not edit them in isolation. When
// the upstream schema changes, run `python tools/sync_schemas.py
// --update --upstream ../heddle` from the repo root and align this
// file with the regenerated schemas. See docs/CONTRACT_EVOLUTION.md.
//
// Field naming convention: PascalCase C# properties with
// [JsonPropertyName(...)] attributes pointing at the snake_case wire
// names. The wire form is authoritative.
//
// Underscore-prefixed wire keys (e.g. ``_trace_context``) are the
// reserved middleware lane — see
// heddle-agent-toolkit/anchors/CONTRACT_MAP.md "Reserved middleware
// lane." SDKs preserve them on inbound and outbound envelopes; they
// are not part of the application contract.

using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Heddle.Sdk;

/// <summary>
/// Hint to the router about which class of LLM backend a task expects.
/// </summary>
/// <remarks>
/// Heddle's router uses (worker_type, model_tier) as the deterministic
/// routing key. Foreign processor workers without an LLM dependency
/// typically run as <see cref="Local"/>; LLM workers may declare a
/// different tier so the router can dispatch to the appropriate
/// backend pool. The literal values are part of the wire contract.
/// </remarks>
public enum ModelTier
{
    Local,
    Standard,
    Frontier,
}

/// <summary>
/// Priority hint for scheduling and (future) preemption decisions.
/// </summary>
/// <remarks>
/// Today Heddle's router treats priority as informational — it does
/// not preempt running tasks. The field is part of the wire contract
/// so producers and orchestrators can express intent that future
/// scheduling layers may honour.
/// </remarks>
public enum TaskPriority
{
    Low,
    Normal,
    High,
    Critical,
}

/// <summary>
/// Lifecycle state carried on <see cref="TaskResult"/>.
/// </summary>
/// <remarks>
/// Worker code does not construct these directly when using
/// <see cref="HeddleWorker{TPayload, TOutput}"/>; the base class
/// derives the right status from the outcome of <c>ProcessAsync</c>
/// (Completed on return, Failed on exception or validation error).
/// Pending and Processing are reserved for orchestrator-side state
/// tracking; workers do not emit them.
/// </remarks>
public enum TaskStatus
{
    Pending,
    Processing,
    Completed,
    Failed,
}

/// <summary>
/// Wire envelope for a unit of work dispatched to a worker.
/// </summary>
/// <remarks>
/// Vendored from <c>heddle.core.messages.TaskMessage</c>. Foreign
/// processor workers receive a serialized TaskMessage from
/// <c>heddle.tasks.{worker_type}.{tier}</c> and reply with a
/// <see cref="TaskResult"/> on
/// <c>heddle.results.{parent_task_id or "default"}</c>.
///
/// Worker authors implementing <see cref="HeddleWorker{TPayload, TOutput}"/>
/// do not construct TaskMessage themselves: the base class decodes
/// it from the inbound transport, deserialises <see cref="Payload"/>
/// into the worker's native <c>TPayload</c>, and passes that typed
/// payload to <c>ProcessAsync</c>. Direct TaskMessage construction
/// is mostly for tests and tooling.
/// </remarks>
public sealed record TaskMessage
{
    [JsonPropertyName("task_id")]
    public string TaskId { get; init; } = Guid.NewGuid().ToString();

    [JsonPropertyName("parent_task_id")]
    public string? ParentTaskId { get; init; }

    [JsonPropertyName("worker_type")]
    public string WorkerType { get; init; } = "";

    [JsonPropertyName("payload")]
    public JsonObject Payload { get; init; } = [];

    [JsonPropertyName("model_tier")]
    public ModelTier ModelTier { get; init; } = ModelTier.Standard;

    [JsonPropertyName("priority")]
    public TaskPriority Priority { get; init; } = TaskPriority.Normal;

    [JsonPropertyName("created_at")]
    public string CreatedAt { get; init; } = HeddleJson.NowIso8601();

    [JsonPropertyName("request_id")]
    public string? RequestId { get; init; }

    [JsonPropertyName("metadata")]
    public JsonObject Metadata { get; init; } = [];

    [JsonPropertyName("_trace_context")]
    public Dictionary<string, string>? TraceContext { get; init; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtensionData { get; init; }
}

/// <summary>
/// Wire envelope for a worker's response to a <see cref="TaskMessage"/>.
/// </summary>
/// <remarks>
/// Vendored from <c>heddle.core.messages.TaskResult</c>. Published by
/// the worker on <c>heddle.results.{parent_task_id or "default"}</c>
/// after <c>ProcessAsync</c> returns (or throws / fails validation,
/// in which case <see cref="Status"/> is <see cref="TaskStatus.Failed"/>
/// and <see cref="Error"/> describes the cause).
///
/// Worker authors do not construct TaskResult directly. They return
/// a <see cref="WorkerOutput{TOutput}"/> from <c>ProcessAsync</c>,
/// and <see cref="HeddleWorker{TPayload, TOutput}.HandleAsync"/>
/// assembles the TaskResult, filling in routing fields
/// (<see cref="TaskId"/>, <see cref="ParentTaskId"/>,
/// <see cref="WorkerType"/>), timing (<see cref="ProcessingTimeMs"/>),
/// status, and propagated <see cref="TraceContext"/>. This separation
/// keeps worker code focused on domain output while the SDK owns the
/// wire envelope.
/// </remarks>
public sealed record TaskResult
{
    [JsonPropertyName("task_id")]
    public string TaskId { get; init; } = "";

    [JsonPropertyName("parent_task_id")]
    public string? ParentTaskId { get; init; }

    [JsonPropertyName("worker_type")]
    public string WorkerType { get; init; } = "";

    [JsonPropertyName("status")]
    public TaskStatus Status { get; init; }

    [JsonPropertyName("output")]
    public JsonObject? Output { get; init; }

    [JsonPropertyName("error")]
    public string? Error { get; init; }

    [JsonPropertyName("model_used")]
    public string? ModelUsed { get; init; }

    [JsonPropertyName("token_usage")]
    public Dictionary<string, int> TokenUsage { get; init; } = [];

    [JsonPropertyName("metadata")]
    public JsonObject Metadata { get; init; } = [];

    [JsonPropertyName("processing_time_ms")]
    public int ProcessingTimeMs { get; init; }

    [JsonPropertyName("completed_at")]
    public string CompletedAt { get; init; } = HeddleJson.NowIso8601();

    [JsonPropertyName("_trace_context")]
    public Dictionary<string, string>? TraceContext { get; init; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtensionData { get; init; }
}

/// <summary>
/// Wire envelope for a higher-level goal handed to an orchestrator.
/// </summary>
/// <remarks>
/// Vendored from <c>heddle.core.messages.OrchestratorGoal</c>. SDKs
/// can deserialise this envelope but the typical foreign-processor-
/// worker flow doesn't construct one — orchestration happens on the
/// Python side. Provided so cross-language tooling (CLI clients,
/// scripted submitters) can encode goals in the same byte-identical
/// form Heddle's orchestrators expect.
/// </remarks>
public sealed record OrchestratorGoal
{
    [JsonPropertyName("goal_id")]
    public string GoalId { get; init; } = Guid.NewGuid().ToString();

    [JsonPropertyName("instruction")]
    public string Instruction { get; init; } = "";

    [JsonPropertyName("context")]
    public JsonObject Context { get; init; } = [];

    [JsonPropertyName("request_id")]
    public string? RequestId { get; init; }

    [JsonPropertyName("priority")]
    public TaskPriority Priority { get; init; } = TaskPriority.Normal;

    [JsonPropertyName("created_at")]
    public string CreatedAt { get; init; } = HeddleJson.NowIso8601();
}

/// <summary>
/// Compressed orchestrator state captured for self-summarisation.
/// </summary>
/// <remarks>
/// Vendored from <c>heddle.core.messages.CheckpointState</c>. Used by
/// Heddle's <c>CheckpointManager</c> on the Python side when an
/// orchestrator's conversation history exceeds a token threshold:
/// the manager compresses history into this structure and persists
/// it (typically to Valkey via the <c>checkpoint</c> KV store
/// domain). The orchestrator can then resume with a fresh context
/// composed of the checkpoint plus a recent-interactions window.
///
/// SDK consumers rarely construct this directly; the model exists so
/// foreign tooling can inspect checkpoint payloads on the wire.
/// </remarks>
public sealed record CheckpointState
{
    [JsonPropertyName("goal_id")]
    public string GoalId { get; init; } = "";

    [JsonPropertyName("original_instruction")]
    public string OriginalInstruction { get; init; } = "";

    [JsonPropertyName("executive_summary")]
    public string ExecutiveSummary { get; init; } = "";

    [JsonPropertyName("completed_tasks")]
    public List<JsonObject> CompletedTasks { get; init; } = [];

    [JsonPropertyName("pending_tasks")]
    public List<JsonObject> PendingTasks { get; init; } = [];

    [JsonPropertyName("open_issues")]
    public List<string> OpenIssues { get; init; } = [];

    [JsonPropertyName("decisions_made")]
    public List<string> DecisionsMade { get; init; } = [];

    [JsonPropertyName("context_token_count")]
    public int ContextTokenCount { get; init; }

    [JsonPropertyName("checkpoint_number")]
    public int CheckpointNumber { get; init; }

    [JsonPropertyName("created_at")]
    public string CreatedAt { get; init; } = HeddleJson.NowIso8601();
}

/// <summary>
/// SDK-ergonomic return type for <see cref="HeddleWorker{TPayload, TOutput}.ProcessAsync"/>.
/// <b>Not a wire type.</b>
/// </summary>
/// <remarks>
/// <para>
/// <b>What it is:</b> a small typed wrapper around the worker's
/// domain output (<see cref="Output"/>) plus optional metrics
/// (<see cref="ModelUsed"/>, <see cref="TokenUsage"/>,
/// <see cref="Metadata"/>). Worker authors construct one and return
/// it from <c>ProcessAsync</c>.
/// </para>
/// <para>
/// <b>What it is not:</b> a wire envelope. WorkerOutput is never
/// serialised onto the Heddle bus. The wire envelope for a worker's
/// response is <see cref="TaskResult"/>, which carries routing fields
/// (task ID, parent task ID, worker type), lifecycle status, timing,
/// and trace context — fields the worker shouldn't have to think
/// about. <see cref="HeddleWorker{TPayload, TOutput}.HandleAsync"/>
/// is the bridge: it receives a <see cref="TaskMessage"/>, calls
/// <c>ProcessAsync</c>, and assembles a <see cref="TaskResult"/>
/// from the returned WorkerOutput plus the inbound envelope's
/// routing context.
/// </para>
/// <para>
/// <b>Why split it out:</b> the alternative — having
/// <c>ProcessAsync</c> return <see cref="TaskResult"/> directly —
/// would force worker authors to populate every routing and timing
/// field on every call, duplicating work the base class can do once.
/// Worse, mistakes in those fields (a wrong task_id, a missing
/// trace_context propagation) would silently break message routing
/// or tracing. Centralising the envelope construction in the base
/// class makes the worker's job "produce typed output + optional
/// metrics" and nothing else.
/// </para>
/// <para>
/// <b>Cross-language equivalence (C6):</b> the Swift SDK defines a
/// parallel <c>WorkerOutput&lt;Output&gt;</c> with the same role. The
/// two diverge on idiom — .NET uses <c>Dictionary&lt;string, int&gt;?</c>
/// and <c>JsonObject?</c> (nullable with null-default), Swift uses
/// non-optional types defaulting to empty collections. Both produce
/// the same wire output: <c>HandleAsync</c> normalises nulls to empty
/// collections when assembling the <see cref="TaskResult"/>. The
/// difference is language-idiomatic, not a contract divergence.
/// </para>
/// </remarks>
/// <typeparam name="TOutput">
/// The worker's typed domain output. Must serialise to a JSON object
/// (the base class checks this and fails the task with a clear error
/// if the serialised form is anything other than an object).
/// </typeparam>
public sealed record WorkerOutput<TOutput>(TOutput Output)
{
    /// <summary>
    /// Optional identifier of the LLM model used to produce this output,
    /// for workers that delegate to an LLM. Surfaces in the
    /// <see cref="TaskResult.ModelUsed"/> field of the wire envelope.
    /// </summary>
    public string? ModelUsed { get; init; }

    /// <summary>
    /// Optional token-usage metrics (typical keys: <c>prompt_tokens</c>,
    /// <c>completion_tokens</c>). Surfaces in
    /// <see cref="TaskResult.TokenUsage"/>; null is normalised to an
    /// empty dictionary by the base class.
    /// </summary>
    public Dictionary<string, int>? TokenUsage { get; init; }

    /// <summary>
    /// Optional free-form per-task metadata. Surfaces in
    /// <see cref="TaskResult.Metadata"/>; null is normalised to an
    /// empty <see cref="JsonObject"/>. Use for worker-specific
    /// diagnostics, intermediate confidence scores, etc. — anything
    /// that should travel with the result but isn't part of the
    /// typed <see cref="Output"/>.
    /// </summary>
    public JsonObject? Metadata { get; init; }
}

