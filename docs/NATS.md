# NATS Transports

The core SDK packages stay broker-neutral. Use the NATS adapter packages when a
.NET or Swift worker needs to join a live Heddle bus, Workshop session, router,
or orchestrator.

## Packages

| Language | Core package | NATS adapter | Official client |
|----------|--------------|--------------|-----------------|
| .NET | `Heddle.Sdk` | `Heddle.Sdk.Nats` | `NATS.Client.Core` |
| Swift | `HeddleActor` | `HeddleActorNATS` | `nats-io/nats.swift` |

The worker subclass does not change when switching from in-memory to NATS.
Only the transport construction changes.

## Start NATS

```bash
docker run --rm -p 4222:4222 nats:latest
```

Or with a local install:

```bash
nats-server
```

## Run Heddle against NATS

From the sibling `heddle` repository:

```bash
uv run heddle router --nats-url nats://localhost:4222
uv run heddle workshop --nats-url nats://localhost:4222
```

Workshop can still run without NATS for local testing. Supplying `--nats-url`
is what lets external SDK workers share the live bus.

## .NET adapter

Reference both packages:

```xml
<ProjectReference Include="../../dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj" />
<ProjectReference Include="../../dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj" />
```

Run the worker:

```csharp
using Heddle.Sdk.Nats;

await using var transport = new NatsHeddleTransport("nats://localhost:4222");
await transport.ConnectAsync(cancellationToken);
await new EchoWorker().RunAsync(transport, cancellationToken);
```

## Swift adapter

Add the adapter package alongside the core package:

```swift
dependencies: [
    .package(path: "../../swift-nats")
]
```

Use the product:

```swift
.product(name: "HeddleActorNATS", package: "HeddleActorNATS")
```

Run the worker:

```swift
import HeddleActorNATS

let transport = NatsTransport(url: URL(string: "nats://localhost:4222")!)
try await transport.connect()
try await EchoWorker().run(transport: transport)
```

On Linux, the Swift NATS dependency chain uses libsodium for NKey support.
Install the development headers before building:

```bash
sudo apt-get install libsodium-dev
```

## Subject contract

Adapters carry raw Heddle JSON envelopes on NATS Core subjects:

- workers subscribe to `heddle.tasks.{worker_type}.{tier}`
- workers join queue group `processors-{worker_type}`
- workers publish results to `heddle.results.{parent_task_id}`
- malformed payloads are skipped by the worker base
- `_trace_context` is preserved in `TaskResult`

NATS Core is at-most-once. Start subscribers before publishing tasks.
