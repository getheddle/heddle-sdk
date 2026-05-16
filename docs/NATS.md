# NATS Transports

The core SDK packages stay broker-neutral. Use the NATS adapter packages when a
native worker needs to join a live Heddle bus, Workshop session, router, or
orchestrator. The .NET adapter is live-runtime ready today. The Swift adapter
wraps the official `nats-io/nats.swift` client and currently builds the real
binding on macOS.

## Packages

| Language | Core package | NATS adapter | Official client | Current status |
|----------|--------------|--------------|-----------------|----------------|
| .NET | `Heddle.Sdk` | `Heddle.Sdk.Nats` | `NATS.Client.Core` | Live-runtime ready |
| Swift | `HeddleActor` | `HeddleActorNATS` | `nats-io/nats.swift` | Real binding on macOS; Linux package surface only |

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

Use the product. When consuming via the local path above, the `package:`
identifier is the directory name (`swift-nats`). When consuming via the
Git URL form (see SWIFT.md), it is the repo slug (`heddle-sdk`).

```swift
// Local-path consumption (matches the dependency block above):
.product(name: "HeddleActorNATS", package: "swift-nats")

// Git-URL consumption:
// .product(name: "HeddleActorNATS", package: "heddle-sdk")
```

Run the worker:

```swift
import HeddleActorNATS

let transport = NatsTransport(url: URL(string: "nats://localhost:4222")!)
try await transport.connect()
try await EchoWorker().run(transport: transport)
```

The Swift adapter wraps the official `nats-io/nats.swift` client, which
currently publishes Apple-platform targets. CI builds the real adapter on macOS;
Linux workers should use `InMemoryTransport` for workshop-local testing until
the official Swift client grows Linux support. Even on Linux, resolving the
adapter package currently requires a Swift 6.2+ toolchain because transitive
`nats.swift` dependencies publish Swift tools 6.2 manifests.

## Subject contract

Adapters carry raw Heddle JSON envelopes on NATS Core subjects:

- workers subscribe to `heddle.tasks.{worker_type}.{tier}`
- workers join queue group `processors-{worker_type}`
- workers publish results to `heddle.results.{parent_task_id}`
- malformed payloads are skipped by the worker base
- `_trace_context` is preserved in `TaskResult`

NATS Core is at-most-once. Start subscribers before publishing tasks.
