using System.Text.Json;
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
    public void TaskMessageRoundTripUsesSnakeCaseWireKeys()
    {
        var task = MakeTaskMessage();
        var data = HeddleJson.SerializeToBytes(task);
        var json = JsonSerializer.Deserialize<JsonObject>(data, HeddleJson.Options)
            ?? throw new JsonException("Unable to read task JSON.");

        Assert.Equal("task-1", json["task_id"]?.GetValue<string>());
        Assert.Equal("goal-1", json["parent_task_id"]?.GetValue<string>());
        Assert.Equal("echo", json["worker_type"]?.GetValue<string>());
        Assert.NotNull(json["_trace_context"]);

        var decoded = HeddleJson.Deserialize<TaskMessage>(data);
        Assert.Equal(task.TaskId, decoded.TaskId);
        Assert.Equal("hello", decoded.Payload["text"]?.GetValue<string>());
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
    public async Task WorkerRunPublishesResultThroughInMemoryTransport()
    {
        await using var transport = new InMemoryHeddleTransport();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var worker = new TestEchoWorker();
        var task = MakeTaskMessage();

        await using var resultMessages = transport
            .SubscribeAsync(
                HeddleSubjects.Results(task.ParentTaskId),
                cancellationToken: timeout.Token)
            .GetAsyncEnumerator(timeout.Token);

        var workerLoop = worker.RunAsync(transport, timeout.Token);
        await WaitForSubscriptionAsync(transport, worker, timeout.Token);

        await transport.PublishAsync(
            worker.Subject,
            HeddleJson.SerializeToBytes(task),
            timeout.Token);

        var message = await NextMessageAsync(resultMessages);
        var result = HeddleJson.Deserialize<TaskResult>(message.Payload.Span);

        Assert.Equal(HeddleTaskStatus.Completed, result.Status);
        Assert.Equal("HELLO", result.Output?["text"]?.GetValue<string>());
        Assert.Equal(5, result.Output?["length"]?.GetValue<int>());
        Assert.Equal(task.TraceContext, result.TraceContext);

        await transport.DisposeAsync();
        await workerLoop.WaitAsync(TimeSpan.FromSeconds(5));
    }

    private static TaskMessage MakeTaskMessage()
    {
        return new TaskMessage
        {
            TaskId = "task-1",
            ParentTaskId = "goal-1",
            WorkerType = "echo",
            ModelTier = ModelTier.Local,
            Payload = new JsonObject
            {
                ["text"] = "hello",
            },
            TraceContext = new Dictionary<string, string>
            {
                ["traceparent"] = "00-abc-def-01",
            },
        };
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
                    new EchoOutput(payload.Text.ToUpperInvariant(), payload.Text.Length)));
        }
    }
}
