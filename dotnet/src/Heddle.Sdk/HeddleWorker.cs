using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Heddle.Sdk;

/// <summary>
/// Transport-agnostic base class for foreign processor workers.
/// </summary>
public abstract class HeddleWorker<TPayload, TOutput>
{
    protected HeddleWorker(
        string workerType,
        string tier = "local",
        JsonObject? inputSchema = null,
        JsonObject? outputSchema = null)
    {
        WorkerType = workerType;
        Tier = tier;
        InputSchema = inputSchema;
        OutputSchema = outputSchema;
    }

    public string WorkerType { get; }

    public string Tier { get; }

    public JsonObject? InputSchema { get; }

    public JsonObject? OutputSchema { get; }

    public string Subject => HeddleSubjects.WorkerTasks(WorkerType, Tier);

    public string QueueGroup => HeddleSubjects.ProcessorQueueGroup(WorkerType);

    public async Task RunAsync(
        IHeddleTransport transport,
        CancellationToken cancellationToken = default)
    {
        await foreach (var message in transport
            .SubscribeAsync(Subject, QueueGroup, cancellationToken)
            .WithCancellation(cancellationToken))
        {
            TaskMessage task;
            try
            {
                task = HeddleJson.Deserialize<TaskMessage>(message.Payload.Span);
            }
            catch (Exception ex) when (ex is JsonException or NotSupportedException)
            {
                await OnMalformedMessageAsync(message, ex, cancellationToken);
                continue;
            }

            var result = await HandleAsync(task, cancellationToken);
            var subject = HeddleSubjects.Results(task.ParentTaskId);
            await transport.PublishAsync(
                subject,
                HeddleJson.SerializeToBytes(result),
                cancellationToken);
        }
    }

    public async Task<TaskResult> HandleAsync(
        TaskMessage task,
        CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            var inputErrors = ShallowSchemaValidator.Validate(task.Payload, InputSchema, "input");
            if (inputErrors.Count > 0)
            {
                return Failed(task, $"Input validation: {string.Join("; ", inputErrors)}");
            }

            var payload = task.Payload.Deserialize<TPayload>(HeddleJson.Options);
            if (payload is null)
            {
                return Failed(task, $"Unable to deserialize payload as {typeof(TPayload).Name}");
            }

            var output = await ProcessAsync(payload, task.Metadata, cancellationToken);
            var outputNode = JsonSerializer.SerializeToNode(output.Output, HeddleJson.Options);
            if (outputNode is not JsonObject outputObject)
            {
                return Failed(task, "Worker output must serialize to a JSON object");
            }

            var outputErrors = ShallowSchemaValidator.Validate(outputObject, OutputSchema, "output");
            if (outputErrors.Count > 0)
            {
                return Failed(task, $"Output validation: {string.Join("; ", outputErrors)}");
            }

            stopwatch.Stop();
            return new TaskResult
            {
                TaskId = task.TaskId,
                ParentTaskId = task.ParentTaskId,
                WorkerType = task.WorkerType,
                Status = TaskStatus.Completed,
                Output = outputObject,
                ModelUsed = output.ModelUsed,
                TokenUsage = output.TokenUsage ?? [],
                Metadata = output.Metadata ?? [],
                ProcessingTimeMs = (int)stopwatch.ElapsedMilliseconds,
                TraceContext = task.TraceContext,
            };
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Failed(task, ex.Message);
        }
        finally
        {
            await ResetAsync(cancellationToken);
        }
    }

    protected abstract Task<WorkerOutput<TOutput>> ProcessAsync(
        TPayload payload,
        JsonObject metadata,
        CancellationToken cancellationToken);

    protected virtual Task ResetAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }

    protected virtual Task OnMalformedMessageAsync(
        HeddleMessage message,
        Exception exception,
        CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }

    private static TaskResult Failed(TaskMessage task, string error)
    {
        return new TaskResult
        {
            TaskId = task.TaskId,
            ParentTaskId = task.ParentTaskId,
            WorkerType = task.WorkerType,
            Status = TaskStatus.Failed,
            Error = error,
            TokenUsage = [],
            Metadata = [],
            TraceContext = task.TraceContext,
        };
    }
}
