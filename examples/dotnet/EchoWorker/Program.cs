using System.Text.Json;
using System.Text.Json.Nodes;
using Heddle.Sdk;

var worker = new EchoWorker();
await using var transport = new InMemoryHeddleTransport();
using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));

var task = new TaskMessage
{
    TaskId = "task-echo-1",
    ParentTaskId = "goal-demo-1",
    WorkerType = "echo",
    ModelTier = ModelTier.Local,
    Payload = new JsonObject
    {
        ["text"] = "hello from .NET",
    },
    TraceContext = new Dictionary<string, string>
    {
        ["traceparent"] = "00-00000000000000000000000000000000-0000000000000000-01",
    },
};

var resultSubject = HeddleSubjects.Results(task.ParentTaskId);
await using var resultMessages = transport
    .SubscribeAsync(resultSubject, cancellationToken: timeout.Token)
    .GetAsyncEnumerator(timeout.Token);

var workerLoop = worker.RunAsync(transport, timeout.Token);
while (transport.SubscriberCount(worker.Subject, worker.QueueGroup) == 0)
{
    await Task.Delay(TimeSpan.FromMilliseconds(10), timeout.Token);
}

await transport.PublishAsync(
    worker.Subject,
    HeddleJson.SerializeToBytes(task),
    timeout.Token);

if (!await resultMessages.MoveNextAsync())
{
    throw new InvalidOperationException("Worker completed without publishing a result.");
}

var result = HeddleJson.Deserialize<TaskResult>(resultMessages.Current.Payload.Span);
Console.WriteLine(JsonSerializer.Serialize(result, HeddleJson.Options));

await transport.DisposeAsync();
try
{
    await workerLoop;
}
catch (OperationCanceledException)
{
    // The example cancels the loop after the single demonstration task.
}

internal sealed record EchoPayload(string Text);

internal sealed record EchoOutput(string Text, int Length);

internal sealed class EchoWorker()
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
        var output = new EchoOutput(
            Text: payload.Text.ToUpperInvariant(),
            Length: payload.Text.Length);

        return Task.FromResult(new WorkerOutput<EchoOutput>(output)
        {
            ModelUsed = "dotnet-example",
            Metadata = new JsonObject
            {
                ["example"] = "echo-worker",
            },
        });
    }
}
