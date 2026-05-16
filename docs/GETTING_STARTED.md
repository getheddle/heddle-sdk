# Getting Started

This guide starts from a fresh checkout and runs both language packages plus
the examples.

## Prerequisites

- .NET SDK 8 or newer
- Swift 6.2 or newer for the full Swift/NATS package surface
- Python 3.11+ only if you want to build the docs locally

No NATS server is required for the checked-in examples. They use the SDK
in-memory transports to exercise the same `run(transport:)` / `RunAsync(...)`
loop that a broker-backed deployment uses.

## Build the SDKs

```bash
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
swift build --package-path swift
dotnet build dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj
swift build --package-path swift-nats
```

`swift-nats` builds a Linux-safe package surface everywhere, and builds the
real `nats-io/nats.swift` transport binding on macOS. The checked-in manifests
remain Swift tools 6.0, but the current `nats.swift` dependency graph requires
a Swift 6.2+ toolchain when resolving the NATS adapter packages.

## Run the SDK tests

```bash
dotnet test dotnet/tests/Heddle.Sdk.Tests/Heddle.Sdk.Tests.csproj
swift test --package-path swift
```

## Run the .NET example

```bash
dotnet run --project examples/dotnet/EchoWorker/EchoWorker.csproj
```

You should see a `TaskResult` JSON object with:

- `status` set to `completed`
- `worker_type` set to `echo`
- an uppercased `output.text`
- `_trace_context` preserved from the input task

## Run the Swift example

```bash
swift run --package-path examples/swift/echo-worker EchoWorker
```

The Swift example performs the same logical work through the Swift worker base.

## Build the docs

```bash
uvx --from mkdocs --with mkdocs-material mkdocs build --strict
```

## Next step

Read the language guide for your target:

- [Swift SDK](SWIFT.md)
- [.NET SDK](DOTNET.md)

Then replace the echo payload and output with your worker's domain types.
Read [Workshop Compatibility](WORKSHOP.md) before wiring a native worker into a
running Workshop instance.
Use [NATS Transports](NATS.md) when you are ready to run the worker on a live
Heddle bus.
