using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Heddle.Sdk;

/// <summary>
/// Transport-agnostic base class for foreign processor workers.
/// Subclass, override <see cref="ProcessAsync"/>, and call
/// <see cref="RunAsync"/> against any <see cref="IHeddleTransport"/>.
/// </summary>
/// <remarks>
/// <para>
/// <b>What you implement:</b> the abstract
/// <see cref="ProcessAsync"/> method. You receive a typed
/// <typeparamref name="TPayload"/> deserialised from the inbound
/// <see cref="TaskMessage.Payload"/>, plus the task's metadata
/// dictionary. You return a <see cref="WorkerOutput{TOutput}"/>
/// containing your typed domain output and optional metrics.
/// </para>
/// <para>
/// <b>What the base class handles for you:</b>
/// <list type="bullet">
/// <item>Subscribing to the right wire subject
///   (<c>heddle.tasks.{worker_type}.{tier}</c>) with the right queue
///   group (<c>processors-{worker_type}</c>).</item>
/// <item>Decoding inbound <see cref="TaskMessage"/> bytes and skipping
///   malformed messages without crashing the subscription loop
///   (calls <see cref="OnMalformedMessageAsync"/> for hooks).</item>
/// <item>Shallow JSON-Schema validation of the input payload
///   against <see cref="InputSchema"/>, if provided.</item>
/// <item>Deserialising the payload to <typeparamref name="TPayload"/>.</item>
/// <item>Calling <see cref="ProcessAsync"/>.</item>
/// <item>Encoding the output and shallow-validating against
///   <see cref="OutputSchema"/>, if provided.</item>
/// <item>Constructing the wire <see cref="TaskResult"/> envelope:
///   copying routing fields from the inbound task
///   (<c>TaskId</c>, <c>ParentTaskId</c>, <c>WorkerType</c>),
///   propagating <c>_trace_context</c>, measuring elapsed time,
///   pulling typed output + metrics from your <see cref="WorkerOutput{TOutput}"/>.</item>
/// <item>Publishing the result to
///   <c>heddle.results.{parent_task_id or "default"}</c>.</item>
/// <item>Calling <see cref="ResetAsync"/> between tasks — workers are
///   stateless in every language SDK (cross-repo invariant C3); the
///   base class enforces this regardless of your subclass discipline.</item>
/// <item>Converting exceptions during <see cref="ProcessAsync"/> into
///   <see cref="TaskResult"/> with <see cref="TaskStatus.Failed"/>
///   plus the exception message. Processing failures never crash
///   the worker; the subscription loop continues.</item>
/// </list>
/// </para>
/// <para>
/// <b>What you DON'T do:</b> construct <see cref="TaskMessage"/> or
/// <see cref="TaskResult"/> directly, manage subscription lifecycles,
/// emit trace spans (that's the OTel layer's job), or persist state
/// between tasks (workers are stateless).
/// </para>
/// <para>
/// <b>Transports:</b> ship as separate packages.
/// <c>Heddle.Sdk.Nats</c> provides a live NATS adapter;
/// <c>InMemoryHeddleTransport</c> is for tests and same-process
/// examples. The base class is transport-agnostic by design (cross-
/// repo invariant C5).
/// </para>
/// </remarks>
/// <typeparam name="TPayload">
/// The native type for the worker's input payload. Must be
/// deserialisable from the JSON object on <c>TaskMessage.payload</c>.
/// </typeparam>
/// <typeparam name="TOutput">
/// The native type for the worker's output. Must serialise to a JSON
/// object (the base class checks this and fails the task with a
/// clear error if not).
/// </typeparam>
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

    /// <summary>
    /// Implement this. Process one typed payload and return one typed
    /// output (wrapped in <see cref="WorkerOutput{TOutput}"/> for
    /// optional metrics).
    /// </summary>
    /// <param name="payload">
    /// The deserialised inbound payload. Has already passed shallow
    /// input-schema validation if <see cref="InputSchema"/> was set.
    /// </param>
    /// <param name="metadata">
    /// Free-form per-task metadata attached by the producer (typically
    /// orchestrator-level routing hints, retry counters, etc.). Pass
    /// through or ignore.
    /// </param>
    /// <param name="cancellationToken">
    /// Honoured by the subscription loop. Long-running work should
    /// respect this so the worker shuts down promptly on cancel.
    /// </param>
    /// <returns>
    /// A <see cref="WorkerOutput{TOutput}"/> containing the typed
    /// domain output plus optional model/usage/metadata fields. The
    /// base class transforms this into the wire
    /// <see cref="TaskResult"/>.
    /// </returns>
    /// <remarks>
    /// Throw on processing failure. The base class converts exceptions
    /// to <see cref="TaskResult"/> with <see cref="TaskStatus.Failed"/>
    /// and the exception message; the subscription loop is unaffected.
    /// Do NOT catch exceptions just to swallow them — return-with-error
    /// is what the wire contract expects.
    /// </remarks>
    protected abstract Task<WorkerOutput<TOutput>> ProcessAsync(
        TPayload payload,
        JsonObject metadata,
        CancellationToken cancellationToken);

    /// <summary>
    /// Optional hook called between tasks to clear any state that
    /// crept in during <see cref="ProcessAsync"/>. Workers are
    /// stateless in every language SDK (cross-repo invariant C3);
    /// override this if your subclass holds per-task scratch state
    /// (caches, buffers) that must be reset.
    /// </summary>
    /// <remarks>
    /// The base class calls this unconditionally after every task,
    /// success or failure. Default implementation is a no-op.
    /// </remarks>
    protected virtual Task ResetAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }

    /// <summary>
    /// Optional hook called when the inbound transport message can't
    /// be decoded as a <see cref="TaskMessage"/>. Override to log,
    /// emit a metric, or report to a dead-letter sink.
    /// </summary>
    /// <remarks>
    /// Malformed messages are skipped, not process-fatal — the
    /// subscription loop continues. This mirrors Heddle's framework
    /// invariant: a single bad message must not take down a worker
    /// replica.
    /// </remarks>
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
