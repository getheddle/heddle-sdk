using System.Text.Json.Nodes;
using Heddle.Sdk;
using Heddle.Sdk.Nats;

// Live-check echo worker (tools/live_check). Not an example: see examples/.
var url = Environment.GetEnvironmentVariable("NATS_URL") ?? "nats://localhost:4222";
await using var transport = new NatsHeddleTransport(url);
await transport.ConnectAsync();
var worker = new LiveEcho();
Console.WriteLine($"dotnet echo worker on {worker.Subject} ({worker.QueueGroup})");
await worker.RunAsync(transport);

internal sealed record EchoIn(string Text);
internal sealed record EchoOut(string Text, string Lang);

internal sealed class LiveEcho() : HeddleWorker<EchoIn, EchoOut>("echo-dotnet", "local")
{
    protected override Task<WorkerOutput<EchoOut>> ProcessAsync(EchoIn payload, JsonObject metadata, CancellationToken ct)
        => Task.FromResult(new WorkerOutput<EchoOut>(new EchoOut(payload.Text.ToUpperInvariant(), "dotnet")));

    protected override Task OnMalformedMessageAsync(HeddleMessage message, Exception exception, CancellationToken ct)
    {
        Console.WriteLine($"dotnet malformed: {exception.Message}");
        return Task.CompletedTask;
    }
}
