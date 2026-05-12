# .NET SDK

The .NET package is `Heddle.Sdk`. It provides contract records, subject helpers,
shallow schema validation, and a generic worker base.

## Add the package

For a local checkout:

```xml
<ProjectReference Include="../../dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj" />
```

Once packages are published, use the NuGet package:

```bash
dotnet add package Heddle.Sdk --prerelease
```

## Define payload and output records

```csharp
internal sealed record EchoPayload(string Text);

internal sealed record EchoOutput(string Text, int Length);
```

`TaskMessage.Payload` is a `JsonObject`; the worker base deserializes it into
`TPayload` using `HeddleJson.Options`. Output must serialize to a `JsonObject`.

## Implement a worker

```csharp
internal sealed class EchoWorker()
    : HeddleWorker<EchoPayload, EchoOutput>(workerType: "echo", tier: "local")
{
    protected override Task<WorkerOutput<EchoOutput>> ProcessAsync(
        EchoPayload payload,
        JsonObject metadata,
        CancellationToken cancellationToken)
    {
        return Task.FromResult(new WorkerOutput<EchoOutput>(
            new EchoOutput(payload.Text.ToUpperInvariant(), payload.Text.Length)));
    }
}
```

## Run with a transport

The core SDK defines the transport boundary:

```csharp
public interface IHeddleTransport : IAsyncDisposable
{
    Task PublishAsync(
        string subject,
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken = default);

    IAsyncEnumerable<HeddleMessage> SubscribeAsync(
        string subject,
        string? queueGroup = null,
        CancellationToken cancellationToken = default);
}
```

The core package includes an in-memory implementation for local examples and
tests:

```csharp
await using var transport = new InMemoryHeddleTransport();
await new EchoWorker().RunAsync(transport, cancellationToken);
```

A broker adapter can implement the same interface without changing worker code:

```csharp
await new EchoWorker().RunAsync(natsTransport, cancellationToken);
```

The checked-in example uses `InMemoryHeddleTransport` so it can run without
NATS while still exercising the transport loop:

```bash
dotnet run --project examples/dotnet/EchoWorker/EchoWorker.csproj
```

## .NET notes

- The SDK targets `net8.0`.
- JSON uses `System.Text.Json`.
- Enum values are serialized as snake/lowercase strings compatible with Heddle's
  wire schema.
- Override `ResetAsync(...)` to clear temporary resources after each task.
- Override `OnMalformedMessageAsync(...)` to log malformed input without
  crashing the subscription loop.
- `InMemoryHeddleTransport` is process-local. Use a shared broker transport for
  a native worker that needs to talk to a running Heddle or Workshop process.
