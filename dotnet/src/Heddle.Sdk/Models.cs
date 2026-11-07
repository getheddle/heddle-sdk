// Language-native types for Heddle's v1 wire bodies (TaskMessage,
// TaskResult, OrchestratorGoal), the standalone CheckpointState, and the
// SDK-internal WorkerOutput<T> ergonomic shape.
//
// The bodies mirror heddle/src/heddle/core/messages.py via
// schemas/v1/*.schema.json. They travel inside a WireEnvelope frame
// (Wire.cs) and are read and written only by HeddleWire, which applies the
// contract's strict typing. When the upstream schemas change, run
// `python tools/sync_schemas.py --update --upstream ../heddle` from the repo
// root, align this file and Wire.cs, and re-run the fixture tests. See
// docs/CONTRACT_EVOLUTION.md.
//
// Bodies carry no timestamps and no Middleware-Lane keys: both live on the
// frame (WireEnvelope.OccurredAt / RecordedAt / Lane).

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
/// Body of a unit of work dispatched to a worker
/// (<c>payload_type</c> <c>core.TaskMessage</c>).
/// </summary>
/// <remarks>
/// Mirrors <c>heddle.core.messages.TaskMessage</c>. Foreign processor
/// workers receive it, framed, on <c>heddle.tasks.{worker_type}.{tier}</c>
/// and reply with a framed <see cref="TaskResult"/> on
/// <c>heddle.results.{parent_task_id or "default"}</c>.
///
/// Worker authors implementing <see cref="HeddleWorker{TPayload, TOutput}"/>
/// do not construct TaskMessage themselves: the base class parses the frame,
/// deserialises <see cref="Input"/> into the worker's native <c>TPayload</c>,
/// and passes it to <c>ProcessAsync</c>. Direct construction is for tests
/// and tooling; frame it with <see cref="HeddleWire.Wrap"/>.
/// </remarks>
public sealed record TaskMessage
{
    public string TaskId { get; init; } = Guid.NewGuid().ToString();

    public string? ParentTaskId { get; init; }

    public required string WorkerType { get; init; }

    /// <summary>The worker's input, as opaque JSON (formerly <c>payload</c>).</summary>
    public required JsonObject Input { get; init; }

    public ModelTier ModelTier { get; init; } = ModelTier.Standard;

    public TaskPriority Priority { get; init; } = TaskPriority.Normal;

    public string? RequestId { get; init; }

    public JsonObject Metadata { get; init; } = [];
}

/// <summary>
/// Body of a worker's response to a <see cref="TaskMessage"/>
/// (<c>payload_type</c> <c>core.TaskResult</c>).
/// </summary>
/// <remarks>
/// Mirrors <c>heddle.core.messages.TaskResult</c>. Worker authors do not
/// construct TaskResult directly: they return a
/// <see cref="WorkerOutput{TOutput}"/> from <c>ProcessAsync</c>, and
/// <see cref="HeddleWorker{TPayload, TOutput}.HandleAsync"/> assembles the
/// result (routing fields, status, timing, token usage). The worker loop
/// then frames it, copying the inbound frame's Middleware Lane.
/// </remarks>
public sealed record TaskResult
{
    public required string TaskId { get; init; }

    public string? ParentTaskId { get; init; }

    public required string WorkerType { get; init; }

    public required TaskStatus Status { get; init; }

    public JsonObject? Output { get; init; }

    public string? Error { get; init; }

    public string? ModelUsed { get; init; }

    public Dictionary<string, long> TokenUsage { get; init; } = [];

    public JsonObject Metadata { get; init; } = [];

    public long ProcessingTimeMs { get; init; }
}

/// <summary>
/// Body of a higher-level goal handed to an orchestrator
/// (<c>payload_type</c> <c>core.OrchestratorGoal</c>).
/// </summary>
/// <remarks>
/// Mirrors <c>heddle.core.messages.OrchestratorGoal</c>. Orchestration
/// happens on the Python side; the model exists so cross-language tooling
/// (CLI clients, scripted submitters) can submit goals on
/// <c>heddle.goals.incoming</c>.
/// </remarks>
public sealed record OrchestratorGoal
{
    public string GoalId { get; init; } = Guid.NewGuid().ToString();

    public required string Instruction { get; init; }

    public JsonObject Context { get; init; } = [];

    public string? RequestId { get; init; }

    public TaskPriority Priority { get; init; } = TaskPriority.Normal;
}

/// <summary>
/// Compressed orchestrator state captured for self-summarisation.
/// </summary>
/// <remarks>
/// Mirrors <c>heddle.core.messages.CheckpointState</c>. It is stored, not
/// sent on the bus, so it is not framed; it is read and written with
/// <see cref="HeddleJson"/>. Used by
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
/// response is <see cref="TaskResult"/>, framed by a
/// <see cref="WireEnvelope"/>: routing fields (task ID, parent task ID,
/// worker type), lifecycle status, timing, and the Middleware Lane —
/// fields the worker shouldn't have to think about. <see cref="HeddleWorker{TPayload, TOutput}.HandleAsync"/>
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
/// Worse, mistakes in those fields (a wrong task_id, a dropped
/// Middleware-Lane key) would silently break message routing
/// or tracing. Centralising the envelope construction in the base
/// class makes the worker's job "produce typed output + optional
/// metrics" and nothing else.
/// </para>
/// <para>
/// <b>Cross-language equivalence (C6):</b> the Swift SDK defines a
/// parallel <c>WorkerOutput&lt;Output&gt;</c> with the same role. The
/// two diverge on idiom — .NET uses <c>Dictionary&lt;string, long&gt;?</c>
/// and <c>JsonObject?</c> (nullable with null-default), Swift uses
/// non-optional types defaulting to empty collections. Both produce
/// the same wire output: <c>HandleAsync</c> normalises them when
/// assembling the <see cref="TaskResult"/>. The
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
    /// Optional token-usage metrics. As upstream, the result carries
    /// exactly <c>prompt_tokens</c> and <c>completion_tokens</c> in
    /// <see cref="TaskResult.TokenUsage"/>, each defaulting to 0; other
    /// keys are not carried.
    /// </summary>
    public Dictionary<string, long>? TokenUsage { get; init; }

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
