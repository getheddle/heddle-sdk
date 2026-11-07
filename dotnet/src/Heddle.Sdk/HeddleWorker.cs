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
/// <see cref="TaskMessage.Input"/>, plus the task's metadata
/// dictionary (with <c>model_tier</c> added, as upstream). You return a <see cref="WorkerOutput{TOutput}"/>
/// containing your typed domain output and optional metrics.
/// </para>
/// <para>
/// <b>What the base class handles for you:</b>
/// <list type="bullet">
/// <item>Subscribing to the right wire subject
///   (<c>heddle.tasks.{worker_type}.{tier}</c>) with the right queue
///   group (<c>processors-{worker_type}</c>).</item>
/// <item>Parsing the inbound <see cref="WireEnvelope"/> frame and its
///   <see cref="TaskMessage"/> body, and skipping malformed messages
///   (invalid frame, invalid body, or any <c>payload_type</c> other than
///   <c>core.TaskMessage</c>) without crashing the subscription loop
///   (calls <see cref="OnMalformedMessageAsync"/> for hooks).</item>
/// <item>Shallow JSON-Schema validation of the input payload
///   against <see cref="InputSchema"/>, if provided.</item>
/// <item>Deserialising the payload to <typeparamref name="TPayload"/>.</item>
/// <item>Calling <see cref="ProcessAsync"/>.</item>
/// <item>Encoding the output and shallow-validating against
///   <see cref="OutputSchema"/>, if provided.</item>
/// <item>Constructing the <see cref="TaskResult"/> body: copying routing
///   fields from the inbound task (<c>TaskId</c>, <c>ParentTaskId</c>,
///   <c>WorkerType</c>), measuring elapsed time, and pulling typed output
///   and metrics from your <see cref="WorkerOutput{TOutput}"/>.</item>
/// <item>Framing the result with a fresh <c>message_id</c> and timestamps,
///   copying every <c>_</c>-prefixed Middleware-Lane key (for example
///   <c>_trace_context</c>) from the inbound frame, and publishing it to
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
/// deserialisable from the JSON object in <c>TaskMessage.input</c>.
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
            WireEnvelope envelope;
            TaskMessage task;
            try
            {
                envelope = HeddleWire.ParseFrame(message.Payload.Span);
                if (envelope.PayloadType != PayloadTypes.TaskMessage)
                {
                    throw new WireFormatException(
                        WireLayer.Dispatch,
                        $"expected payload_type '{PayloadTypes.TaskMessage}' on a task subject, got '{envelope.PayloadType}'");
                }

                task = (TaskMessage)HeddleWire.ParseBody(envelope);
            }
            catch (WireFormatException ex)
            {
                await OnMalformedMessageAsync(message, ex, cancellationToken);
                continue;
            }

            var result = await HandleAsync(task, cancellationToken);
            var subject = HeddleSubjects.Results(task.ParentTaskId);
            await transport.PublishAsync(
                subject,
                HeddleWire.Serialize(HeddleWire.Wrap(result, envelope.Lane)),
                cancellationToken);
        }
    }

    /// <summary>
    /// Run one task through validation, <see cref="ProcessAsync"/> and
    /// result assembly. Never throws for a processing failure: the result
    /// has <see cref="TaskStatus.Failed"/> instead.
    /// </summary>
    public async Task<TaskResult> HandleAsync(
        TaskMessage task,
        CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        long Elapsed() => stopwatch.ElapsedMilliseconds;
        try
        {
            var inputErrors = ShallowSchemaValidator.Validate(task.Input, InputSchema, "input");
            if (inputErrors.Count > 0)
            {
                return Result(task, TaskStatus.Failed, Elapsed(), error: $"Input validation: {string.Join("; ", inputErrors)}");
            }

            var payload = task.Input.Deserialize<TPayload>(HeddleJson.Options);
            if (payload is null)
            {
                return Result(task, TaskStatus.Failed, Elapsed(), error: $"Unable to deserialize input as {typeof(TPayload).Name}");
            }

            var metadata = (JsonObject)task.Metadata.DeepClone();
            metadata["model_tier"] = WireEnum.ToWire(task.ModelTier);
            var output = await ProcessAsync(payload, metadata, cancellationToken);
            var outputNode = JsonSerializer.SerializeToNode(output.Output, HeddleJson.Options);
            if (outputNode is not JsonObject outputObject)
            {
                return Result(task, TaskStatus.Failed, Elapsed(), error: "Worker output must serialize to a JSON object",
                    modelUsed: output.ModelUsed, tokens: output.TokenUsage);
            }

            var outputErrors = ShallowSchemaValidator.Validate(outputObject, OutputSchema, "output");
            if (outputErrors.Count > 0)
            {
                return Result(task, TaskStatus.Failed, Elapsed(), error: $"Output validation: {string.Join("; ", outputErrors)}",
                    modelUsed: output.ModelUsed, tokens: output.TokenUsage);
            }

            return Result(task, TaskStatus.Completed, Elapsed(), output: outputObject,
                modelUsed: output.ModelUsed, tokens: output.TokenUsage, metadata: output.Metadata);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Result(task, TaskStatus.Failed, Elapsed(), error: ex.Message);
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
    /// Optional hook called when the inbound transport message is not a
    /// valid framed <see cref="TaskMessage"/>. The exception is a
    /// <see cref="WireFormatException"/> naming the rejecting layer. Override to log,
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

    // Mirrors heddle.worker.base._publish_result: token_usage always carries
    // exactly prompt_tokens and completion_tokens, and metadata comes from the
    // worker's output (never the task's).
    private static TaskResult Result(
        TaskMessage task,
        TaskStatus status,
        long elapsedMs,
        JsonObject? output = null,
        string? error = null,
        string? modelUsed = null,
        Dictionary<string, long>? tokens = null,
        JsonObject? metadata = null)
    {
        return new TaskResult
        {
            TaskId = task.TaskId,
            ParentTaskId = task.ParentTaskId,
            WorkerType = task.WorkerType,
            Status = status,
            Output = output,
            Error = error,
            ModelUsed = modelUsed,
            TokenUsage = new Dictionary<string, long>
            {
                ["prompt_tokens"] = tokens?.GetValueOrDefault("prompt_tokens") ?? 0,
                ["completion_tokens"] = tokens?.GetValueOrDefault("completion_tokens") ?? 0,
            },
            Metadata = metadata ?? [],
            ProcessingTimeMs = elapsedMs,
        };
    }
}
