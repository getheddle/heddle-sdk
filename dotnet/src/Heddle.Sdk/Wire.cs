// The Heddle v1 wire frame (WireEnvelope) and its strict codec.
//
// Mirrors heddle/src/heddle/core/envelope.py. Every message on the bus is
// a frame: identity, causation, two timestamps, a payload_type
// discriminator, the typed body in `payload`, and the Middleware Lane
// (top-level `_`-prefixed keys, carried as opaque JSON).
//
// Parsing has two steps, as upstream: validate the frame, then pick the
// body model by payload_type and validate the body. Errors carry the
// layer that rejected the message (frame / body / dispatch), matching the
// `rejected_at` column of schemas/v1/fixtures/manifest.json.
//
// The codec is hand-written over System.Text.Json.Nodes rather than
// attribute binding. That keeps the rules identical to the Swift and JVM
// SDKs and keeps System.Text.Json's lenient defaults (numbers from
// strings, case-insensitive names) away from the wire. See
// schemas/v1/fixtures/README.md for the rules this file implements.

using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Heddle.Sdk;

/// <summary>The layer at which an inbound message was rejected.</summary>
public enum WireLayer
{
    /// <summary>The frame is invalid (missing or ill-typed field, unknown non-<c>_</c> key, bad timestamp).</summary>
    Frame,

    /// <summary>The frame is valid, but the body fails its model.</summary>
    Body,

    /// <summary>The frame is valid, but no body model is registered for its <c>payload_type</c>.</summary>
    Dispatch,
}

/// <summary>An inbound message that does not satisfy the v1 wire contract.</summary>
public sealed class WireFormatException(WireLayer layer, string message, Exception? inner = null)
    : Exception($"{layer.ToString().ToLowerInvariant()}: {message}", inner)
{
    /// <summary>The layer that rejected the message.</summary>
    public WireLayer Layer { get; } = layer;
}

/// <summary>The <c>payload_type</c> discriminators this SDK registers.</summary>
public static class PayloadTypes
{
    public const string TaskMessage = "core.TaskMessage";
    public const string TaskResult = "core.TaskResult";
    public const string OrchestratorGoal = "core.OrchestratorGoal";

    /// <summary>Every registered discriminator. Anything else is a dispatch rejection.</summary>
    public static readonly IReadOnlyList<string> All = [TaskMessage, TaskResult, OrchestratorGoal];
}

/// <summary>
/// The generic frame every Heddle message rides. The typed body is in
/// <see cref="Payload"/>; use <see cref="HeddleWire"/> to build and read frames.
/// </summary>
public sealed record WireEnvelope
{
    public string MessageId { get; init; } = Guid.NewGuid().ToString();

    /// <summary>Dotted discriminator, e.g. <c>core.TaskMessage</c>.</summary>
    public required string PayloadType { get; init; }

    /// <summary>The body as JSON. Validated by <see cref="HeddleWire.ParseBody"/>.</summary>
    public required JsonObject Payload { get; init; }

    public string? Origin { get; init; }

    public string? CorrelationId { get; init; }

    public string? CausationId { get; init; }

    /// <summary>Domain time: when the thing this message is about happened.</summary>
    public DateTimeOffset OccurredAt { get; init; }

    /// <summary>Bus time: when this message was recorded onto the transport.</summary>
    public DateTimeOffset RecordedAt { get; init; }

    /// <summary>
    /// The Middleware Lane: every top-level <c>_</c>-prefixed key, as opaque
    /// JSON, in arrival order. Actors that publish a message because of an
    /// inbound one copy this onto the new frame (heddle DESIGN_INVARIANTS #22).
    /// </summary>
    public IReadOnlyDictionary<string, JsonNode?> Lane { get; init; } = new Dictionary<string, JsonNode?>();
}

/// <summary>Strict reader and writer for the v1 wire frame and the core bodies.</summary>
public static class HeddleWire
{
    // Nesting limit for inbound JSON; System.Text.Json's default (64) is far
    // below Python's, which would reject deep but valid opaque input.
    private const int MaxDepth = 1000;

    private static readonly string[] FrameFields =
    [
        "message_id", "payload_type", "payload", "origin", "correlation_id",
        "causation_id", "occurred_at", "recorded_at",
    ];

    // RFC 3339 date-time with a mandatory offset (envelope.py `_RFC3339`).
    // ASCII digits only: .NET's \d also matches other Unicode digits.
    private static readonly Regex Rfc3339 = new(
        @"^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?(?:([Zz])|([+-])([0-9]{2}):([0-9]{2}))\z",
        RegexOptions.CultureInvariant);

    // ------------------------------------------------------------------
    // Frame
    // ------------------------------------------------------------------

    /// <summary>Two-step parse: the frame, then the body chosen by <c>payload_type</c>.</summary>
    /// <exception cref="WireFormatException">The message violates the contract; see <see cref="WireFormatException.Layer"/>.</exception>
    public static (WireEnvelope Envelope, object Body) Parse(ReadOnlySpan<byte> utf8Json)
    {
        var envelope = ParseFrame(utf8Json);
        return (envelope, ParseBody(envelope));
    }

    /// <summary>Validate the frame only. The body stays unvalidated JSON.</summary>
    public static WireEnvelope ParseFrame(ReadOnlySpan<byte> utf8Json)
    {
        JsonObject root;
        try
        {
            root = JsonNode.Parse(utf8Json, documentOptions: new JsonDocumentOptions { MaxDepth = MaxDepth }) as JsonObject
                ?? throw new WireFormatException(WireLayer.Frame, "message is not a JSON object");
            // JsonObject materializes lazily; walking the whole tree here
            // surfaces duplicate keys at any depth now, not later.
            _ = root.ToJsonString();
        }
        catch (Exception ex) when (ex is JsonException or ArgumentException or InvalidOperationException)
        {
            throw new WireFormatException(WireLayer.Frame, "message is not valid JSON", ex);
        }

        return ParseFrame(root);
    }

    /// <summary>Validate a frame that is already a JSON object.</summary>
    public static WireEnvelope ParseFrame(JsonObject root)
    {
        var lane = new Dictionary<string, JsonNode?>();
        var unknown = new List<string>();
        foreach (var (key, value) in root)
        {
            if (key.StartsWith('_'))
            {
                lane[key] = value?.DeepClone();
            }
            else if (Array.IndexOf(FrameFields, key) < 0)
            {
                unknown.Add(key);
            }
        }

        if (unknown.Count > 0)
        {
            unknown.Sort(StringComparer.Ordinal);
            throw new WireFormatException(
                WireLayer.Frame,
                $"unknown top-level key(s) [{string.Join(", ", unknown)}]; only declared fields and `_`-prefixed Middleware-Lane keys are accepted");
        }

        var payloadType = root.ContainsKey("payload_type")
            ? Str(root, "payload_type", WireLayer.Frame)
            : throw new WireFormatException(WireLayer.Frame, "payload_type is required");
        var payload = root.ContainsKey("payload")
            ? Obj(root, "payload", WireLayer.Frame)
            : throw new WireFormatException(WireLayer.Frame, "payload is required");

        DateTimeOffset occurred, recorded;
        var hasOccurred = root.ContainsKey("occurred_at");
        var hasRecorded = root.ContainsKey("recorded_at");
        if (!hasOccurred && !hasRecorded)
        {
            occurred = recorded = Now();
        }
        else
        {
            // A present key must be a valid timestamp: an explicit null is not "absent".
            occurred = hasOccurred ? Timestamp(root, "occurred_at") : Timestamp(root, "recorded_at");
            recorded = hasRecorded ? Timestamp(root, "recorded_at") : occurred;
        }

        return new WireEnvelope
        {
            MessageId = root.ContainsKey("message_id") ? Str(root, "message_id", WireLayer.Frame) : Guid.NewGuid().ToString(),
            PayloadType = payloadType,
            Payload = (JsonObject)payload.DeepClone(),
            Origin = OptStr(root, "origin", WireLayer.Frame),
            CorrelationId = OptStr(root, "correlation_id", WireLayer.Frame),
            CausationId = OptStr(root, "causation_id", WireLayer.Frame),
            OccurredAt = occurred,
            RecordedAt = recorded,
            Lane = lane,
        };
    }

    /// <summary>Validate the body for the frame's <c>payload_type</c> (step two).</summary>
    public static object ParseBody(WireEnvelope envelope)
    {
        return envelope.PayloadType switch
        {
            PayloadTypes.TaskMessage => ReadTaskMessage(envelope.Payload),
            PayloadTypes.TaskResult => ReadTaskResult(envelope.Payload),
            PayloadTypes.OrchestratorGoal => ReadOrchestratorGoal(envelope.Payload),
            _ => throw new WireFormatException(
                WireLayer.Dispatch,
                $"no payload model registered for '{envelope.PayloadType}'"),
        };
    }

    /// <summary>
    /// Build a frame around a typed body. Both timestamps take one fresh
    /// instant unless given. <paramref name="lane"/> is copied onto the frame.
    /// </summary>
    public static WireEnvelope Wrap(
        object body,
        IReadOnlyDictionary<string, JsonNode?>? lane = null,
        string? origin = null,
        string? correlationId = null,
        string? causationId = null)
    {
        var (payloadType, payload) = body switch
        {
            TaskMessage task => (PayloadTypes.TaskMessage, WriteTaskMessage(task)),
            TaskResult result => (PayloadTypes.TaskResult, WriteTaskResult(result)),
            OrchestratorGoal goal => (PayloadTypes.OrchestratorGoal, WriteOrchestratorGoal(goal)),
            _ => throw new ArgumentException($"{body.GetType().Name} is not a registered wire body", nameof(body)),
        };
        var now = Now();
        var copied = new Dictionary<string, JsonNode?>();
        foreach (var (key, value) in lane ?? new Dictionary<string, JsonNode?>())
        {
            if (!key.StartsWith('_'))
            {
                throw new ArgumentException($"lane key '{key}' must start with '_'", nameof(lane));
            }

            copied[key] = value?.DeepClone();
        }

        return new WireEnvelope
        {
            PayloadType = payloadType,
            Payload = payload,
            Origin = origin,
            CorrelationId = correlationId,
            CausationId = causationId,
            OccurredAt = now,
            RecordedAt = now,
            Lane = copied,
        };
    }

    /// <summary>The frame as a JSON object. Every field is written, nulls included.</summary>
    public static JsonObject ToJsonObject(WireEnvelope envelope)
    {
        var root = new JsonObject
        {
            ["message_id"] = envelope.MessageId,
            ["payload_type"] = envelope.PayloadType,
            ["payload"] = envelope.Payload.DeepClone(),
            ["origin"] = envelope.Origin,
            ["correlation_id"] = envelope.CorrelationId,
            ["causation_id"] = envelope.CausationId,
            ["occurred_at"] = FormatTimestamp(envelope.OccurredAt),
            ["recorded_at"] = FormatTimestamp(envelope.RecordedAt),
        };
        foreach (var (key, value) in envelope.Lane)
        {
            root[key] = value?.DeepClone();
        }

        return root;
    }

    /// <summary>The frame as UTF-8 JSON bytes, ready to publish.</summary>
    public static byte[] Serialize(WireEnvelope envelope)
    {
        return Encoding.UTF8.GetBytes(ToJsonObject(envelope).ToJsonString());
    }

    // ------------------------------------------------------------------
    // Timestamps
    // ------------------------------------------------------------------

    /// <summary>
    /// Parse an RFC 3339 date-time with a mandatory offset. Fractional
    /// seconds beyond microseconds are truncated, as upstream does. A leap
    /// second (<c>:60</c>) and impossible dates are rejected.
    /// </summary>
    public static bool TryParseTimestamp(string text, out DateTimeOffset value)
    {
        value = default;
        var match = Rfc3339.Match(text);
        if (!match.Success)
        {
            return false;
        }

        int Part(int group) => int.Parse(match.Groups[group].Value, CultureInfo.InvariantCulture);
        try
        {
            var local = new DateTime(Part(1), Part(2), Part(3), Part(4), Part(5), Part(6), DateTimeKind.Unspecified);
            var fraction = match.Groups[7].Success ? match.Groups[7].Value : "";
            var micros = fraction.Length == 0
                ? 0
                : int.Parse(fraction.PadRight(6, '0')[..6], CultureInfo.InvariantCulture);
            var offsetMinutes = 0;
            if (!match.Groups[8].Success)
            {
                var hours = Part(10);
                var minutes = Part(11);
                if (hours > 23 || minutes > 59)
                {
                    return false;
                }

                offsetMinutes = (hours * 60 + minutes) * (match.Groups[9].Value == "-" ? -1 : 1);
            }

            var utc = local.AddTicks(micros * 10L).AddMinutes(-offsetMinutes);
            value = new DateTimeOffset(DateTime.SpecifyKind(utc, DateTimeKind.Utc));
            return true;
        }
        catch (Exception ex) when (ex is ArgumentOutOfRangeException or FormatException or OverflowException)
        {
            return false;
        }
    }

    /// <summary>UTC, six fractional digits, <c>Z</c>. Any instant-equal form is conformant.</summary>
    public static string FormatTimestamp(DateTimeOffset value)
    {
        return value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.ffffff'Z'", CultureInfo.InvariantCulture);
    }

    private static DateTimeOffset Now()
    {
        var ticks = DateTimeOffset.UtcNow.UtcTicks;
        return new DateTimeOffset(ticks - (ticks % 10), TimeSpan.Zero);
    }

    private static DateTimeOffset Timestamp(JsonObject root, string key)
    {
        var text = Str(root, key, WireLayer.Frame);
        return TryParseTimestamp(text, out var value)
            ? value
            : throw new WireFormatException(WireLayer.Frame, $"{key} must be an RFC 3339 date-time string with a UTC offset");
    }

    // ------------------------------------------------------------------
    // Bodies (tolerant readers: unknown keys are ignored)
    // ------------------------------------------------------------------

    private static TaskMessage ReadTaskMessage(JsonObject p)
    {
        const WireLayer L = WireLayer.Body;
        return new TaskMessage
        {
            TaskId = p.ContainsKey("task_id") ? Str(p, "task_id", L) : Guid.NewGuid().ToString(),
            ParentTaskId = OptStr(p, "parent_task_id", L),
            WorkerType = Required(p, "worker_type", () => Str(p, "worker_type", L)),
            Input = Required(p, "input", () => (JsonObject)Obj(p, "input", L).DeepClone()),
            ModelTier = p.ContainsKey("model_tier") ? Enum<ModelTier>(p, "model_tier") : ModelTier.Standard,
            Priority = p.ContainsKey("priority") ? Enum<TaskPriority>(p, "priority") : TaskPriority.Normal,
            RequestId = OptStr(p, "request_id", L),
            Metadata = p.ContainsKey("metadata") ? (JsonObject)Obj(p, "metadata", L).DeepClone() : [],
        };
    }

    private static TaskResult ReadTaskResult(JsonObject p)
    {
        const WireLayer L = WireLayer.Body;
        var tokens = new Dictionary<string, long>();
        if (p.ContainsKey("token_usage"))
        {
            foreach (var (key, value) in Obj(p, "token_usage", L))
            {
                tokens[key] = Integer(value, $"token_usage.{key}");
            }
        }

        JsonObject? output = null;
        if (p["output"] is not null)
        {
            output = (JsonObject)Obj(p, "output", L).DeepClone();
        }

        return new TaskResult
        {
            TaskId = Required(p, "task_id", () => Str(p, "task_id", L)),
            ParentTaskId = OptStr(p, "parent_task_id", L),
            WorkerType = Required(p, "worker_type", () => Str(p, "worker_type", L)),
            Status = Required(p, "status", () => Enum<TaskStatus>(p, "status")),
            Output = output,
            Error = OptStr(p, "error", L),
            ModelUsed = OptStr(p, "model_used", L),
            TokenUsage = tokens,
            Metadata = p.ContainsKey("metadata") ? (JsonObject)Obj(p, "metadata", L).DeepClone() : [],
            ProcessingTimeMs = p.ContainsKey("processing_time_ms") ? Integer(p["processing_time_ms"], "processing_time_ms") : 0,
        };
    }

    private static OrchestratorGoal ReadOrchestratorGoal(JsonObject p)
    {
        const WireLayer L = WireLayer.Body;
        return new OrchestratorGoal
        {
            GoalId = p.ContainsKey("goal_id") ? Str(p, "goal_id", L) : Guid.NewGuid().ToString(),
            Instruction = Required(p, "instruction", () => Str(p, "instruction", L)),
            Context = p.ContainsKey("context") ? (JsonObject)Obj(p, "context", L).DeepClone() : [],
            RequestId = OptStr(p, "request_id", L),
            Priority = p.ContainsKey("priority") ? Enum<TaskPriority>(p, "priority") : TaskPriority.Normal,
        };
    }

    private static JsonObject WriteTaskMessage(TaskMessage t) => new()
    {
        ["task_id"] = t.TaskId,
        ["parent_task_id"] = t.ParentTaskId,
        ["worker_type"] = t.WorkerType,
        ["input"] = t.Input.DeepClone(),
        ["model_tier"] = WireEnum.ToWire(t.ModelTier),
        ["priority"] = WireEnum.ToWire(t.Priority),
        ["request_id"] = t.RequestId,
        ["metadata"] = t.Metadata.DeepClone(),
    };

    private static JsonObject WriteTaskResult(TaskResult r)
    {
        var tokens = new JsonObject();
        foreach (var (key, value) in r.TokenUsage)
        {
            tokens[key] = value;
        }

        return new JsonObject
        {
            ["task_id"] = r.TaskId,
            ["parent_task_id"] = r.ParentTaskId,
            ["worker_type"] = r.WorkerType,
            ["status"] = WireEnum.ToWire(r.Status),
            ["output"] = r.Output?.DeepClone(),
            ["error"] = r.Error,
            ["model_used"] = r.ModelUsed,
            ["token_usage"] = tokens,
            ["metadata"] = r.Metadata.DeepClone(),
            ["processing_time_ms"] = r.ProcessingTimeMs,
        };
    }

    private static JsonObject WriteOrchestratorGoal(OrchestratorGoal g) => new()
    {
        ["goal_id"] = g.GoalId,
        ["instruction"] = g.Instruction,
        ["context"] = g.Context.DeepClone(),
        ["request_id"] = g.RequestId,
        ["priority"] = WireEnum.ToWire(g.Priority),
    };

    // ------------------------------------------------------------------
    // Typed field readers
    // ------------------------------------------------------------------

    private static T Required<T>(JsonObject p, string key, Func<T> read)
    {
        return p.ContainsKey(key)
            ? read()
            : throw new WireFormatException(WireLayer.Body, $"{key} is required");
    }

    private static string Str(JsonObject o, string key, WireLayer layer)
    {
        if (o[key] is JsonValue value && value.GetValueKind() == JsonValueKind.String)
        {
            return value.GetValue<string>();
        }

        throw new WireFormatException(layer, $"{key} must be a string");
    }

    private static string? OptStr(JsonObject o, string key, WireLayer layer)
    {
        return o[key] is null ? null : Str(o, key, layer);
    }

    private static JsonObject Obj(JsonObject o, string key, WireLayer layer)
    {
        return o[key] as JsonObject ?? throw new WireFormatException(layer, $"{key} must be a JSON object");
    }

    private static TEnum Enum<TEnum>(JsonObject o, string key)
        where TEnum : struct, Enum
    {
        var text = Str(o, key, WireLayer.Body);
        return WireEnum.TryFromWire<TEnum>(text, out var value)
            ? value
            : throw new WireFormatException(WireLayer.Body, $"{key}: unknown value '{text}'");
    }

    /// <summary>
    /// A JSON integer. As in JSON Schema's <c>integer</c>, an integral number
    /// written as a float (<c>420.0</c>, <c>1e3</c>) is accepted; strings,
    /// booleans, fractions and null are rejected.
    /// </summary>
    private static long Integer(JsonNode? node, string path)
    {
        if (node is JsonValue value && value.GetValueKind() == JsonValueKind.Number)
        {
            if (value.TryGetValue<long>(out var direct))
            {
                return direct;
            }

            if (value.TryGetValue<JsonElement>(out var element))
            {
                if (element.TryGetInt64(out var asLong))
                {
                    return asLong;
                }

                if (element.TryGetDouble(out var asDouble) && IsIntegral(asDouble))
                {
                    return (long)asDouble;
                }
            }
            else if (value.TryGetValue<double>(out var d) && IsIntegral(d))
            {
                return (long)d;
            }
        }

        throw new WireFormatException(WireLayer.Body, $"{path} must be an integer");
    }

    private static bool IsIntegral(double d)
    {
        return !double.IsInfinity(d) && Math.Floor(d) == d && d >= long.MinValue && d < long.MaxValue;
    }
}

/// <summary>Lower-case wire spelling of the contract enums.</summary>
public static class WireEnum
{
    public static string ToWire<TEnum>(TEnum value)
        where TEnum : struct, Enum
    {
        return value.ToString().ToLowerInvariant();
    }

    public static bool TryFromWire<TEnum>(string text, out TEnum value)
        where TEnum : struct, Enum
    {
        foreach (var candidate in System.Enum.GetValues<TEnum>())
        {
            if (ToWire(candidate) == text)
            {
                value = candidate;
                return true;
            }
        }

        value = default;
        return false;
    }
}
