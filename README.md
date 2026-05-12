# Heddle SDK

Language SDKs and actor-runtime helpers for Heddle.

Heddle's Python repository owns the runtime framework and canonical wire
schemas. This repository packages those contracts for other language
ecosystems, starting with .NET and Swift.

## Status

Early scaffold. The first layer includes:

- Vendored `schemas/v1/*.schema.json` from `getheddle/heddle`.
- .NET contract models, subject helpers, shallow schema validation, and a
  transport-agnostic worker loop.
- Swift `Codable` contract models, subject helpers, shallow schema validation,
  and a transport-agnostic worker base.

NATS-specific transport adapters will land after the contract packages settle.

## Repository Layout

```text
schemas/v1/              Canonical Heddle wire schemas copied from heddle
dotnet/src/Heddle.Sdk/   .NET SDK package
swift/                   SwiftPM package
```

## Wire Contract

The bus protocol is intentionally small:

- `TaskMessage` and `TaskResult` are JSON envelopes.
- Tasks enter through `heddle.tasks.incoming`.
- The router dispatches to `heddle.tasks.{worker_type}.{tier}`.
- Workers publish to `heddle.results.{parent_task_id or "default"}`.
- Foreign processor workers use queue group `processors-{worker_type}`.
- Trace context, when present, rides as top-level `_trace_context`.

The Python repository remains the source of truth. When the Pydantic models
change there, run its schema export, then copy the updated files here.

## .NET

```bash
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
```

The .NET package has no external runtime dependencies. It exposes the contract
models, helpers, and an `IHeddleTransport` abstraction that a NATS adapter can
implement.

## Swift

```bash
swift test --package-path swift
```

The Swift package has no external runtime dependencies. It exposes `Codable`
contract models, helpers, and a `HeddleTransport` protocol that a NATS adapter
can implement.

## License

MPL 2.0. See `LICENSE`.

