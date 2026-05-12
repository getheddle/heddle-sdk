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

