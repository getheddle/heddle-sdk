using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Heddle.Sdk;

public enum ModelTier
{
    Local,
    Standard,
    Frontier,
}

public enum TaskPriority
{
    Low,
    Normal,
    High,
    Critical,
}

public enum TaskStatus
{
    Pending,
    Processing,
    Completed,
    Failed,
}

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

public sealed record WorkerOutput<TOutput>(TOutput Output)
{
    public string? ModelUsed { get; init; }

    public Dictionary<string, int>? TokenUsage { get; init; }

    public JsonObject? Metadata { get; init; }
}

