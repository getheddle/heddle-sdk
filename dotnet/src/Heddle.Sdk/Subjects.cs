namespace Heddle.Sdk;

/// <summary>
/// Heddle NATS subject and queue-group conventions.
/// </summary>
public static class HeddleSubjects
{
    public const string IncomingTasks = "heddle.tasks.incoming";
    public const string DeadLetters = "heddle.tasks.dead_letter";
    public const string IncomingGoals = "heddle.goals.incoming";
    public const string ControlReload = "heddle.control.reload";

    public static string WorkerTasks(string workerType, string tier)
    {
        return $"heddle.tasks.{workerType}.{tier}";
    }

    public static string Results(string? parentTaskId)
    {
        return $"heddle.results.{parentTaskId ?? "default"}";
    }

    public static string ProcessorQueueGroup(string workerType)
    {
        return $"processors-{workerType}";
    }

    public static string LlmWorkerQueueGroup(string workerType)
    {
        return $"workers-{workerType}";
    }
}

/// <summary>
/// Subject helpers for the <c>heddle.contrib.events</c> wire contract.
/// </summary>
/// <remarks>
/// Mirrors <c>heddle.core.subjects</c> in the upstream Python repo.
/// Patterns:
/// <code>
/// heddle.events.{aggregateType}.{aggregateId}.{eventType}
/// heddle.commands.{aggregateType}.{aggregateId}.{commandType}
/// heddle.rejections.{aggregateType}.{aggregateId}.{commandType}
/// </code>
/// Stream names follow <c>HEDDLE_{KIND}_{AGGREGATE_TYPE_UPPER}</c>.
/// </remarks>
public static class EventSubjects
{
    private static readonly char[] Forbidden = { '.', ' ', '*', '>' };

    private static void Validate(string value, string label)
    {
        if (string.IsNullOrEmpty(value))
        {
            throw new ArgumentException($"{label} must not be empty", label);
        }
        if (value.IndexOfAny(Forbidden) >= 0)
        {
            throw new ArgumentException(
                $"{label}=\"{value}\" contains forbidden NATS subject chars",
                label);
        }
    }

    public static string Event(string aggregateType, string aggregateId, string eventType)
    {
        Validate(aggregateType, nameof(aggregateType));
        Validate(aggregateId, nameof(aggregateId));
        Validate(eventType, nameof(eventType));
        return $"heddle.events.{aggregateType}.{aggregateId}.{eventType}";
    }

    public static string Command(string aggregateType, string aggregateId, string commandType)
    {
        Validate(aggregateType, nameof(aggregateType));
        Validate(aggregateId, nameof(aggregateId));
        Validate(commandType, nameof(commandType));
        return $"heddle.commands.{aggregateType}.{aggregateId}.{commandType}";
    }

    public static string Rejection(string aggregateType, string aggregateId, string commandType)
    {
        Validate(aggregateType, nameof(aggregateType));
        Validate(aggregateId, nameof(aggregateId));
        Validate(commandType, nameof(commandType));
        return $"heddle.rejections.{aggregateType}.{aggregateId}.{commandType}";
    }

    public static string EventStream(string aggregateType)
    {
        Validate(aggregateType, nameof(aggregateType));
        return $"HEDDLE_EVENTS_{aggregateType.ToUpperInvariant()}";
    }

    public static string CommandStream(string aggregateType)
    {
        Validate(aggregateType, nameof(aggregateType));
        return $"HEDDLE_COMMANDS_{aggregateType.ToUpperInvariant()}";
    }

    public static string RejectionStream(string aggregateType)
    {
        Validate(aggregateType, nameof(aggregateType));
        return $"HEDDLE_REJECTIONS_{aggregateType.ToUpperInvariant()}";
    }

    public static string EventFilter(string aggregateType)
    {
        Validate(aggregateType, nameof(aggregateType));
        return $"heddle.events.{aggregateType}.>";
    }

    public static string CommandFilter(string aggregateType)
    {
        Validate(aggregateType, nameof(aggregateType));
        return $"heddle.commands.{aggregateType}.>";
    }

    public static string RejectionFilter(string aggregateType)
    {
        Validate(aggregateType, nameof(aggregateType));
        return $"heddle.rejections.{aggregateType}.>";
    }
}

