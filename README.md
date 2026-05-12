# Heddle SDK

Language SDKs and actor-runtime helpers for
[Heddle](https://github.com/getheddle/heddle) foreign-language processor
workers.

[![CI](https://github.com/getheddle/heddle-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/getheddle/heddle-sdk/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://getheddle.github.io/heddle-sdk/)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](LICENSE)

Heddle's Python repository owns the runtime framework and canonical wire
schemas. This repository packages those contracts for other language
ecosystems, starting with .NET and Swift.

## What ships

- Vendored `schemas/v1/*.schema.json` from `getheddle/heddle`.
- .NET contract models, subject helpers, shallow schema validation, and a
  transport-agnostic worker loop.
- Swift `Codable` contract models, subject helpers, shallow schema validation,
  and a transport-agnostic worker base.
- Runnable .NET and Swift echo-worker examples.
- A MkDocs documentation site with source-controlled draw.io diagrams.

NATS-specific transport adapters will land after the contract packages settle.

## Quick start

```bash
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
swift build --package-path swift
```

Run the examples:

```bash
dotnet run --project examples/dotnet/EchoWorker/EchoWorker.csproj
swift run --package-path examples/swift/echo-worker EchoWorker
```

## Documentation

Start with:

| Guide | Description |
|-------|-------------|
| [Concepts](docs/CONCEPTS.md) | Heddle's foreign-actor wire protocol in SDK terms |
| [Getting Started](docs/GETTING_STARTED.md) | Build packages and run examples |
| [Swift SDK](docs/SWIFT.md) | Implement a Swift processor worker |
| [.NET SDK](docs/DOTNET.md) | Implement a C# / .NET processor worker |
| [Architecture](docs/ARCHITECTURE.md) | Repository layout and worker lifecycle |
| [Contributing](docs/CONTRIBUTING.md) | Contribution boundaries and verification |

Build the docs locally:

```bash
uvx --from mkdocs --with mkdocs-material mkdocs build --strict
```

## Repository layout

```text
schemas/v1/              Canonical Heddle wire schemas copied from heddle
dotnet/src/Heddle.Sdk/   .NET SDK package
swift/                   SwiftPM package
examples/                Runnable .NET and Swift workers
docs/                    MkDocs site
docs/diagrams/           draw.io diagram sources
docs/images/             exported SVG diagrams
```

## Wire contract

The bus protocol is intentionally small:

- `TaskMessage` and `TaskResult` are JSON envelopes.
- Tasks enter through `heddle.tasks.incoming`.
- The router dispatches to `heddle.tasks.{worker_type}.{tier}`.
- Workers publish to `heddle.results.{parent_task_id or "default"}`.
- Foreign processor workers use queue group `processors-{worker_type}`.
- Trace context, when present, rides as top-level `_trace_context`.

The Python repository remains the source of truth. When the Pydantic models
change there, run its schema export, then copy the updated files here.

## License

MPL 2.0. See `LICENSE`.
