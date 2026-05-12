# CLAUDE.md — Heddle SDK

## What this is

Heddle SDK is the foreign-language actor SDK repository for Heddle. It provides
contract models, subject helpers, shallow schema validation, and
transport-agnostic worker bases for languages outside the Python runtime.

The first supported languages are:

```text
dotnet/src/Heddle.Sdk/   C# / .NET package
swift/                   SwiftPM package named HeddleActor
```

The upstream Heddle repository owns the runtime, router, orchestrators, Python
workers, canonical Pydantic models, and exported JSON Schemas. This repository
must stay synchronized with those contracts.

## Design boundaries

- **SDK, not Python bindings.** The interop surface is NATS subjects plus JSON
  envelopes. Nothing here imports Python or binds to Python ABI internals.
- **Transport core is abstract.** `IHeddleTransport` and `HeddleTransport`
  are the dependency-light core. NATS adapters can be separate packages later.
- **Processor workers first.** Foreign actors are intended for native
  processing, ML inference, transforms, or platform-specific capabilities.
- **Heddle remains source of truth.** When upstream Pydantic message models
  change, export schemas in `getheddle/heddle`, copy `schemas/v1`, then update
  typed wrappers here.

## Non-negotiable wire rules

- `TaskMessage`, `TaskResult`, `OrchestratorGoal`, and `CheckpointState` must
  keep snake_case wire keys compatible with upstream schemas.
- Workers subscribe to `heddle.tasks.{worker_type}.{tier}` with queue group
  `processors-{worker_type}`.
- Results publish to `heddle.results.{parent_task_id or "default"}`.
- Trace context rides as top-level `_trace_context`.
- Worker output must serialize to a JSON object.
- Shallow validation means required fields plus top-level JSON type checks.

## Build and test

```bash
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
dotnet build examples/dotnet/EchoWorker/EchoWorker.csproj
swift build --package-path swift
swift test --package-path swift
swift build --package-path examples/swift/echo-worker
uvx --from mkdocs --with mkdocs-material mkdocs build --strict
```

Local note: some macOS Swift toolchains do not expose `XCTest` to SwiftPM. The
Swift test file is conditional so `swift test` still validates the package on
those machines and runs assertions on toolchains that provide XCTest or Swift
Testing.

## Documentation standards

The docs should read like the sibling `heddle` site:

- Start with concepts and working examples, not package internals.
- Keep diagrams source-controlled as `.drawio` in `docs/diagrams`.
- Exported SVGs live in `docs/images`; dark variants use the `-dark.svg`
  suffix and the `#only-light` / `#only-dark` CSS hooks.
- Link to upstream Heddle docs for framework behavior rather than duplicating
  pages that can drift.

## What not to do

- Do not add message fields unless they exist upstream in `heddle`.
- Do not make SDK worker bases depend on a specific NATS client.
- Do not convert shallow validation into full JSON Schema validation without
  documenting the stricter behavior.
- Do not add examples that require proprietary services or live infrastructure
  to compile.
