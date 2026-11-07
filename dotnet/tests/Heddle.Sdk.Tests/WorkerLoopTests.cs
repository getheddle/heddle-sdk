using System.Text.Json.Nodes;
using Heddle.Sdk;
using Xunit;
using HeddleTaskStatus = Heddle.Sdk.TaskStatus;

namespace Heddle.Sdk.Tests;

public sealed class WorkerLoopTests
{
    [Fact]
    public void SubjectHelpersMatchHeddleConventions()
    {
        Assert.Equal(
            "heddle.tasks.image_classifier.local",
            HeddleSubjects.WorkerTasks("image_classifier", "local"));
        Assert.Equal("heddle.results.default", HeddleSubjects.Results(null));
        Assert.Equal("heddle.results.goal-1", HeddleSubjects.Results("goal-1"));
        Assert.Equal(
            "processors-image_classifier",
            HeddleSubjects.ProcessorQueueGroup("image_classifier"));
    }

    [Fact]
    public async Task InMemoryTransportRoutesQueueGroupsRoundRobin()
    {
        await using var transport = new InMemoryHeddleTransport();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await using var first = transport
            .SubscribeAsync("heddle.test", "processors-echo", timeout.Token)
            .GetAsyncEnumerator(timeout.Token);
        await using var second = transport
            .SubscribeAsync("heddle.test", "processors-echo", timeout.Token)
            .GetAsyncEnumerator(timeout.Token);

        await transport.PublishAsync("heddle.test", "one"u8.ToArray(), timeout.Token);
        await transport.PublishAsync("heddle.test", "two"u8.ToArray(), timeout.Token);

        var firstMessage = await NextMessageAsync(first);
        var secondMessage = await NextMessageAsync(second);

        Assert.Equal("one", StringPayload(firstMessage));
        Assert.Equal("two", StringPayload(secondMessage));
    }

    [Fact]
    public async Task WorkerRunPublishesFramedResultCarryingTheLane()
    {
        var frame = MakeTaskFrame();
        var (envelope, body) = await RoundTripAsync(new TestEchoWorker(), HeddleWire.Serialize(frame));
        var result = Assert.IsType<TaskResult>(body);

        Assert.Equal(PayloadTypes.TaskResult, envelope.PayloadType);
        Assert.NotEqual(frame.MessageId, envelope.MessageId);
        Assert.Equal(envelope.OccurredAt, envelope.RecordedAt);
        Assert.Null(envelope.Origin);
        Assert.Null(envelope.CorrelationId);
        Assert.Null(envelope.CausationId);
        Assert.Equal(frame.Lane.Keys.OrderBy(k => k), envelope.Lane.Keys.OrderBy(k => k));
        foreach (var (key, value) in frame.Lane)
        {
            Assert.True(WireConformanceTests.JsonValueEquals(value, envelope.Lane[key]), key);
        }

        Assert.Equal("task-1", result.TaskId);
        Assert.Equal("goal-1", result.ParentTaskId);
        Assert.Equal("echo", result.WorkerType);
        Assert.Equal(HeddleTaskStatus.Completed, result.Status);
        Assert.Equal("HELLO", result.Output?["text"]?.GetValue<string>());
        Assert.Equal(["completion_tokens", "prompt_tokens"], result.TokenUsage.Keys.OrderBy(k => k));
        Assert.Equal("local", result.Metadata["seen_tier"]?.GetValue<string>());
    }

    [Fact]
    public async Task InputValidationFailurePublishesFailedResult()
    {
        var frame = MakeTaskFrame(new JsonObject { ["wrong"] = 1 });
        var (_, body) = await RoundTripAsync(new TestEchoWorker(), HeddleWire.Serialize(frame));
        var result = Assert.IsType<TaskResult>(body);

        Assert.Equal(HeddleTaskStatus.Failed, result.Status);
        Assert.StartsWith("Input validation:", result.Error);
        Assert.Equal(["completion_tokens", "prompt_tokens"], result.TokenUsage.Keys.OrderBy(k => k));
    }

    [Theory]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"text":"hi"}},"bogus":1}""", WireLayer.Frame)]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"text":"hi"}},"occurred_at":"2026-01-01T00:00:00"}""", WireLayer.Frame)]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{"input":{"text":"hi"}}}""", WireLayer.Body)]
    [InlineData("""{"payload_type":"core.TaskResult","payload":{"task_id":"t","worker_type":"echo","status":"completed"}}""", WireLayer.Dispatch)]
    [InlineData("""{"payload_type":"events.Event","payload":{}}""", WireLayer.Dispatch)]
    [InlineData("""not json""", WireLayer.Frame)]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"text":"hi"}},"occurred_at":"２０26-01-01T00:00:00Z"}""", WireLayer.Frame)]
    [InlineData("""{"payload_type":"core.TaskMessage","payload":{"worker_type":"echo","input":{"text":"hi"},"input":{"text":"again"}}}""", WireLayer.Frame)]
    public async Task MalformedMessagesAreSkippedAndTheLoopContinues(string raw, WireLayer layer)
    {
        await using var transport = new InMemoryHeddleTransport();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var worker = new TestEchoWorker();
        await using var results = transport
            .SubscribeAsync(HeddleSubjects.Results("goal-1"), cancellationToken: timeout.Token)
            .GetAsyncEnumerator(timeout.Token);
        var loop = worker.RunAsync(transport, timeout.Token);
        await WaitForSubscriptionAsync(transport, worker, timeout.Token);

        await transport.PublishAsync(worker.Subject, System.Text.Encoding.UTF8.GetBytes(raw), timeout.Token);
        await transport.PublishAsync(worker.Subject, HeddleWire.Serialize(MakeTaskFrame()), timeout.Token);

        var (_, body) = HeddleWire.Parse((await NextMessageAsync(results)).Payload.Span);
        Assert.Equal(HeddleTaskStatus.Completed, Assert.IsType<TaskResult>(body).Status);
        var malformed = Assert.Single(worker.Malformed);
        Assert.Equal(layer, Assert.IsType<WireFormatException>(malformed).Layer);

        await transport.DisposeAsync();
        await loop.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Theory]
    [InlineData("valid/task_message_full.json")]
    [InlineData("valid/task_message_middleware_lane.json")]
    [InlineData("valid/task_message_minimal_defaults.json")]
    [InlineData("valid/task_message_unknown_body_key.json")]
    public async Task EveryValidTaskFixtureYieldsAParseableResult(string file)
    {
        var bytes = File.ReadAllBytes(Path.Combine(WireConformanceTests.FixtureDir, file));
        var inbound = HeddleWire.ParseFrame(bytes);
        var task = (TaskMessage)HeddleWire.ParseBody(inbound);
        var worker = new PassThroughWorker(task.WorkerType, WireEnum.ToWire(task.ModelTier));

        var (envelope, body) = await RoundTripAsync(worker, bytes, task.ParentTaskId);

        Assert.Equal(PayloadTypes.TaskResult, envelope.PayloadType);
        Assert.Equal(task.TaskId, Assert.IsType<TaskResult>(body).TaskId);
        Assert.Equal(inbound.Lane.Keys.OrderBy(k => k), envelope.Lane.Keys.OrderBy(k => k));
    }

    private static async Task<(WireEnvelope Envelope, object Body)> RoundTripAsync<TPayload, TOutput>(
        HeddleWorker<TPayload, TOutput> worker,
        byte[] frame,
        string? parentTaskId = "goal-1")
    {
        await using var transport = new InMemoryHeddleTransport();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await using var results = transport
            .SubscribeAsync(HeddleSubjects.Results(parentTaskId), cancellationToken: timeout.Token)
            .GetAsyncEnumerator(timeout.Token);
        var loop = worker.RunAsync(transport, timeout.Token);
        while (transport.SubscriberCount(worker.Subject, worker.QueueGroup) == 0)
        {
            await Task.Delay(TimeSpan.FromMilliseconds(10), timeout.Token);
        }

        await transport.PublishAsync(worker.Subject, frame, timeout.Token);
        var message = await NextMessageAsync(results);

        await transport.DisposeAsync();
        await loop.WaitAsync(TimeSpan.FromSeconds(5));
        return HeddleWire.Parse(message.Payload.Span);
    }

    private static WireEnvelope MakeTaskFrame(JsonObject? input = null)
    {
        var task = new TaskMessage
        {
            TaskId = "task-1",
            ParentTaskId = "goal-1",
            WorkerType = "echo",
            ModelTier = ModelTier.Local,
            Input = input ?? new JsonObject { ["text"] = "hello" },
        };
        return HeddleWire.Wrap(
            task,
            new Dictionary<string, JsonNode?>
            {
                ["_trace_context"] = new JsonObject { ["traceparent"] = "00-abc-def-01" },
                ["_x_custom"] = new JsonArray(1, "two", null),
            },
            origin: "test",
            correlationId: "corr-1");
    }

    private static async Task WaitForSubscriptionAsync(
        InMemoryHeddleTransport transport,
        TestEchoWorker worker,
        CancellationToken cancellationToken)
    {
        while (transport.SubscriberCount(worker.Subject, worker.QueueGroup) == 0)
        {
            await Task.Delay(TimeSpan.FromMilliseconds(10), cancellationToken);
        }
    }

    private static async Task<HeddleMessage> NextMessageAsync(
        IAsyncEnumerator<HeddleMessage> enumerator)
    {
        if (!await enumerator.MoveNextAsync())
        {
            throw new InvalidOperationException("Message stream closed before producing a message.");
        }

        return enumerator.Current;
    }

    private static string StringPayload(HeddleMessage message)
    {
        return System.Text.Encoding.UTF8.GetString(message.Payload.Span);
    }

    private sealed record EchoPayload(string Text);

    private sealed record EchoOutput(string Text, int Length);

    private sealed class PassThroughWorker(string workerType, string tier)
        : HeddleWorker<JsonObject, JsonObject>(workerType, tier)
    {
        protected override Task<WorkerOutput<JsonObject>> ProcessAsync(
            JsonObject payload,
            JsonObject metadata,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new WorkerOutput<JsonObject>(payload));
        }
    }

    private sealed class TestEchoWorker()
        : HeddleWorker<EchoPayload, EchoOutput>(
            workerType: "echo",
            tier: "local",
            inputSchema: new JsonObject
            {
                ["type"] = "object",
                ["required"] = new JsonArray("text"),
                ["properties"] = new JsonObject
                {
                    ["text"] = new JsonObject { ["type"] = "string" },
                },
            },
            outputSchema: new JsonObject
            {
                ["type"] = "object",
                ["required"] = new JsonArray("text", "length"),
                ["properties"] = new JsonObject
                {
                    ["text"] = new JsonObject { ["type"] = "string" },
                    ["length"] = new JsonObject { ["type"] = "integer" },
                },
            })
    {
        protected override Task<WorkerOutput<EchoOutput>> ProcessAsync(
            EchoPayload payload,
            JsonObject metadata,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                new WorkerOutput<EchoOutput>(
                    new EchoOutput(payload.Text.ToUpperInvariant(), payload.Text.Length))
                {
                    Metadata = new JsonObject { ["seen_tier"] = metadata["model_tier"]?.DeepClone() },
                });
        }

        public List<Exception> Malformed { get; } = [];

        protected override Task OnMalformedMessageAsync(
            HeddleMessage message,
            Exception exception,
            CancellationToken cancellationToken)
        {
            Malformed.Add(exception);
            return Task.CompletedTask;
        }
    }
}
