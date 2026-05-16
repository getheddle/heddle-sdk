# Concepts

Heddle SDKs are not Python bindings. They are typed views over Heddle's wire
protocol.

The useful boundary is:

```text
Heddle runtime           Heddle SDK worker
----------------        ----------------------------
Router                   Decodes TaskMessage JSON
Orchestrator             Validates payload shape
NATS bus         <---->  Processes a native payload
Python workers           Encodes TaskResult JSON
Workshop                 Publishes to result subject
```

## The envelope and the payload

Every task has two layers:

| Layer | Meaning |
|-------|---------|
| Envelope | Routing, lifecycle, metadata, trace context. Stable across worker types. |
| Payload | Worker-specific JSON object. Validated by the worker's input schema. |

`TaskMessage` is the request envelope. `TaskResult` is the response envelope.
Both use snake_case wire keys, even when the language API uses PascalCase or
camelCase names.

## Subjects

| Subject | Purpose |
|---------|---------|
| `heddle.tasks.incoming` | Client or orchestrator publishes tasks for routing. |
| `heddle.tasks.{worker_type}.{tier}` | Router dispatches tasks to worker replicas. |
| `heddle.results.{parent_task_id}` | Worker publishes a result for an orchestrator goal. |
| `heddle.results.default` | Worker publishes a standalone result. |
| `heddle.tasks.dead_letter` | Router publishes unroutable or rate-limited tasks. |
| `heddle.control.reload` | Optional hot-reload broadcast. |

Foreign processor workers should subscribe to
`heddle.tasks.{worker_type}.{tier}` with queue group
`processors-{worker_type}`. Queue groups prevent every replica from receiving
the same task.

## Transports

SDK workers depend on a small publish/subscribe transport boundary, not on a
specific broker client. The checked-in .NET and Swift packages include
process-local in-memory transports for tests and examples. Those transports
match Heddle's local `InMemoryBus` queue-group behavior, but they do not cross
process boundaries.

Use a shared broker transport, usually NATS, when a native worker needs to
participate in a live Heddle or Workshop runtime.

## Worker lifecycle

![Worker lifecycle](images/worker-lifecycle.svg#only-light)
![Worker lifecycle](images/worker-lifecycle-dark.svg#only-dark)

The SDK worker base follows the upstream Heddle lifecycle:

1. Receive bytes from a transport.
2. Decode a `TaskMessage`.
3. Skip malformed input and keep the loop alive.
4. Run shallow input validation.
5. Decode the worker payload into a native type.
6. Process the payload.
7. Encode output and verify it is a JSON object.
8. Run shallow output validation.
9. Publish a `TaskResult`.
10. Reset before the next task.

## Writing a worker — the SDK author's API

The boundary between "what the SDK does for you" and "what you
implement" is intentionally tight. You implement one method; the base
class handles everything else.

### What you implement

```csharp
// .NET
protected override Task<WorkerOutput<MyOutput>> ProcessAsync(
    MyPayload payload,
    JsonObject metadata,
    CancellationToken cancellationToken)
```

```swift
// Swift
override func process(
    payload: MyPayload,
    metadata: [String: JSONValue]
) async throws -> WorkerOutput<MyOutput>
```

You receive a **typed payload** (already deserialised from the wire,
already shallow-validated against your `InputSchema` / `inputSchema`
if you provided one) and the inbound task's metadata dictionary. You
return a `WorkerOutput<MyOutput>` containing your typed domain output
plus optional metrics (`ModelUsed` / `modelUsed`, `TokenUsage` /
`tokenUsage`, `Metadata` / `metadata`).

### Wire envelope vs. SDK return type

This split is the most important thing to internalise:

| | Wire envelope (on NATS) | SDK return type (in code) |
|---|---|---|
| **.NET** | `TaskResult` | `WorkerOutput<TOutput>` |
| **Swift** | `TaskResult` | `WorkerOutput<Output>` |
| **Constructed by** | the base class | your `ProcessAsync` / `process` |
| **Contains** | routing fields, status, timing, trace context, output, metrics | typed output + optional metrics |
| **Serialised to the bus?** | **yes** | **no, never** |

`WorkerOutput` is the SDK's ergonomic shape for "what a worker
produces." The base class transforms it into `TaskResult` for the
wire — filling in `task_id`, `parent_task_id`, `worker_type`,
`status`, `processing_time_ms`, `_trace_context`, and your typed
output as the `output` field. If you ever see `WorkerOutput` on the
wire, that's a bug.

### What the base class handles for you

The base class (`HeddleWorker<TPayload, TOutput>` in .NET,
`HeddleWorker<Payload, Output>` in Swift) owns:

- **Subscription**: subscribes to
  `heddle.tasks.{worker_type}.{tier}` with queue group
  `processors-{worker_type}`. Queue groups give you free horizontal
  scaling — run N replicas, each gets ~1/N of the tasks.
- **Malformed-message resilience**: bad inbound bytes call a hook
  (`OnMalformedMessageAsync` / `malformedMessage(_:)`) and the
  subscription loop keeps running. A single bad message must not take
  down a worker replica.
- **Shallow input/output validation**: against the schemas you pass
  to the constructor. "Shallow" means top-level required fields and
  type checks only — matches Heddle's runtime behaviour. Deeper
  domain validation belongs inside your `ProcessAsync` / `process`.
- **Timing**: measures elapsed processing time and emits it as
  `processing_time_ms` on the wire envelope.
- **Trace context propagation**: copies `_trace_context` from the
  inbound `TaskMessage` to the outbound `TaskResult`. Tracing
  middleware injects/extracts this field — see
  [`heddle-agent-toolkit/anchors/CONTRACT_MAP.md`](https://github.com/getheddle/heddle-agent-toolkit/blob/main/anchors/CONTRACT_MAP.md)
  "Reserved middleware lane."
- **Failure handling**: exceptions or thrown errors during your
  `ProcessAsync` / `process` are converted to `TaskResult` with
  `status = failed` and the error message. **Don't catch exceptions
  just to swallow them** — return-with-error is what the wire
  contract expects.
- **Reset**: calls `ResetAsync` / `reset()` unconditionally between
  tasks. Workers are stateless in every language SDK (cross-repo
  invariant C3); the base class enforces this regardless of your
  subclass discipline.

### What you do NOT do

- Construct `TaskMessage` or `TaskResult` directly. (Both can be
  built for tests and tooling, but in worker code you never touch
  them — the base class hands you a payload and takes back a
  `WorkerOutput`.)
- Manage transport subscription lifecycles.
- Emit trace spans manually — that's the OTel layer's job.
- Persist state between tasks.

### Example

The end-to-end shape, with the worker doing the minimum:

```csharp
// .NET — see examples/dotnet/EchoWorker/Program.cs
public sealed class EchoWorker : HeddleWorker<EchoPayload, EchoOutput>
{
    public EchoWorker() : base("echo", tier: "local") {}

    protected override Task<WorkerOutput<EchoOutput>> ProcessAsync(
        EchoPayload payload,
        JsonObject metadata,
        CancellationToken cancellationToken)
    {
        var output = new EchoOutput { Echo = payload.Text };
        return Task.FromResult(new WorkerOutput<EchoOutput>(output));
    }
}
```

```swift
// Swift — see examples/swift/echo-worker/Sources/EchoWorker/main.swift
final class EchoWorker: HeddleWorker<EchoPayload, EchoOutput> {
    init() { super.init(workerType: "echo", tier: "local") }

    override func process(
        payload: EchoPayload,
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<EchoOutput> {
        WorkerOutput(output: EchoOutput(text: payload.text.uppercased()))
    }
}
```

That's the full surface. Domain logic goes inside `ProcessAsync` /
`process`; everything else is handled.

## Shallow schema validation

Heddle intentionally validates only the contract boundary:

- required top-level fields
- top-level JSON type checks

It does not implement full JSON Schema in the SDK core. That matches the Python
runtime and keeps foreign workers predictable. A worker may add stricter
domain validation inside `process`, but that stricter behavior should be local
to the worker.

## Trace context

Trace context rides as top-level `_trace_context`. SDKs preserve it on
`TaskResult`. A transport adapter or worker can integrate with OpenTelemetry,
but preserving the field verbatim is the minimum compatibility requirement.
