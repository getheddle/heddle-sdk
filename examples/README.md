# Examples

The examples are intentionally small and infrastructure-free. They show how to
write a foreign processor worker with the SDK, feed it a `TaskMessage`, and get
back a `TaskResult` with the Heddle wire shape.

Real deployments add a transport adapter, usually NATS, and call the worker's
run loop. The processing code stays the same.

## .NET echo worker

```bash
dotnet run --project examples/dotnet/EchoWorker/EchoWorker.csproj
```

The .NET example subclasses `HeddleWorker<TPayload, TOutput>`, processes an
`EchoPayload`, and prints the encoded `TaskResult`.

## Swift echo worker

```bash
swift run --package-path examples/swift/echo-worker EchoWorker
```

The Swift example subclasses `HeddleWorker<Payload, Output>`, processes the same
logical payload, and prints the encoded result JSON.

## What to copy into a real worker

- The typed payload and output structs.
- The worker subclass and `process` method.
- The `inputSchema` and `outputSchema` shape if you want SDK-side shallow
  validation before publishing results.

What not to copy:

- Direct calls to `handle(...)` in production. Use `run(transport:)` /
  `RunAsync(...)` with a real transport adapter.
