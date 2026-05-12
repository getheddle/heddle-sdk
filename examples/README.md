# Examples

The examples are intentionally small and infrastructure-free. They show how to
write a foreign processor worker with the SDK, feed it a `TaskMessage` through
the SDK in-memory transport, and get back a `TaskResult` with the Heddle wire
shape.

Real deployments replace the in-memory transport with a broker adapter, usually
NATS. The worker run loop and processing code stay the same.

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

- The in-memory transport for a worker that needs to talk to a running Heddle or
  Workshop process. Use a shared broker transport for cross-process interop.
