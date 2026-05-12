# Examples

The examples live under `examples/` and are meant to be copied.

## Echo worker

Both examples:

1. Define a typed payload.
2. Define a typed output.
3. Subclass the language worker base.
4. Supply shallow input/output schemas.
5. Process a `TaskMessage`.
6. Print a `TaskResult`.

Run them:

```bash
dotnet run --project examples/dotnet/EchoWorker/EchoWorker.csproj
swift run --package-path examples/swift/echo-worker EchoWorker
```

## Moving from example to production

Replace direct `handle` calls with a transport run loop:

| Example mode | Production mode |
|--------------|-----------------|
| Build a `TaskMessage` in `main` | Receive `TaskMessage` from NATS |
| Call `HandleAsync(...)` / `handle(...)` | Call `RunAsync(...)` / `run(transport:)` |
| Print the result | Publish to `heddle.results.{parent_task_id}` |

The worker subclass does not change.

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
