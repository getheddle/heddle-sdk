# Examples

The examples live under `examples/` and are meant to be copied.

## Echo worker

Both examples:

1. Define a typed payload.
2. Define a typed output.
3. Subclass the language worker base.
4. Supply shallow input/output schemas.
5. Subscribe through the SDK in-memory transport.
6. Publish a `TaskMessage`.
7. Print the resulting `TaskResult`.

Run them:

```bash
dotnet run --project examples/dotnet/EchoWorker/EchoWorker.csproj
swift run --package-path examples/swift/echo-worker EchoWorker
```

## Moving from example to live runtime

Replace the in-memory transport with a broker-backed transport:

| Example mode | Live runtime mode |
|--------------|-------------------|
| Build a `TaskMessage` in `main` | Receive `TaskMessage` from the Heddle router |
| Use `InMemoryHeddleTransport` / `InMemoryTransport` | Use a shared broker transport, usually NATS |
| Call `RunAsync(...)` / `run(transport:)` | Keep the same worker run-loop call |
| Print the result from a local subscriber | Publish to `heddle.results.{parent_task_id}` |

The worker subclass does not change.
See [NATS Transports](NATS.md) for the shipped adapter packages.

## Worker config in Heddle

Foreign workers still need a Heddle worker config so the router knows where to
send tasks:

```yaml
name: echo
worker_kind: processor
default_model_tier: local

input_schema:
  type: object
  required: [text]
  properties:
    text: {type: string}

output_schema:
  type: object
  required: [text, length]
  properties:
    text: {type: string}
    length: {type: integer}

implementation:
  runtime: swift
  entry: ./bin/EchoWorker
```

The `implementation` block is informational today. Heddle's router cares about
the worker name, kind, tier, and schemas.
