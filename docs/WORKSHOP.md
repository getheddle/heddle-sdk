# Workshop Compatibility

SDK workers use the same `TaskMessage`, `TaskResult`, subject names, and queue
groups as Heddle's Python workers. The worker code stays the same whether the
transport is in-memory for a local harness or broker-backed for a running
Heddle runtime.

## What in-memory means

Workshop can run on Heddle's Python `InMemoryBus`. That bus is a process-local
Python object, not an IPC service. A separate .NET or Swift process cannot
attach to that exact bus instance.

The SDK in-memory transports are the matching local-development shape:

| Use case | Transport |
|----------|-----------|
| Unit tests and examples | `InMemoryHeddleTransport` / `InMemoryTransport` |
| Workshop running fully in Python in one process | Heddle `InMemoryBus` |
| External .NET or Swift worker with live Workshop | `Heddle.Sdk.Nats` / `HeddleActorNATS` |

The in-memory transports intentionally match Heddle's local bus behavior:

- exact subject matching
- fire-and-forget publish semantics
- all ungrouped subscribers receive each message
- one member of each queue group receives each message, selected round-robin

## Local actor loop

.NET:

```csharp
await using var transport = new InMemoryHeddleTransport();
await new EchoWorker().RunAsync(transport, cancellationToken);
```

Swift:

```swift
let transport = InMemoryTransport()
try await EchoWorker().run(transport: transport)
```

Examples publish a single `TaskMessage` into those transports, wait for the
worker's `TaskResult`, and print the result JSON. That keeps the sample
dependency-free while still exercising the production worker loop.

## Live Workshop interop

For a native worker to participate in a running Workshop or Heddle runtime, run
both sides against the same broker. The subject contract does not change:

- subscribe to `heddle.tasks.{worker_type}.{tier}`
- use queue group `processors-{worker_type}`
- publish results to `heddle.results.{parent_task_id}`
- preserve `_trace_context` when it is present

The core packages deliberately avoid depending on a concrete NATS client. A
broker adapter should implement `IHeddleTransport` or `HeddleTransport`, then
pass that adapter to the same worker `RunAsync(...)` / `run(transport:)` call.

See [NATS Transports](NATS.md) for the concrete adapter packages and run
commands.
