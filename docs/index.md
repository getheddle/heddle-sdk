# Heddle SDK

**Build foreign-language Heddle processor workers without binding to Python.**

Heddle's runtime is Python, but its actor protocol is intentionally
language-agnostic: NATS subjects plus typed JSON envelopes. This repository
packages that contract for .NET and Swift so native workers can participate in
the same Heddle bus as Python workers.

![SDK architecture](images/sdk-architecture.svg#only-light)
![SDK architecture](images/sdk-architecture-dark.svg#only-dark)

## What ships today

| Area | What you get |
|------|--------------|
| Wire schemas | Copied `schemas/v1/*.schema.json` from `getheddle/heddle` |
| .NET | `Heddle.Sdk` contract models, subject helpers, shallow validation, worker base |
| Swift | `HeddleActor` `Codable` models, subject helpers, shallow validation, worker base |
| Examples | Runnable .NET and Swift echo workers that need no NATS server |
| Docs | Protocol concepts, architecture, language guides, and contribution standards |

The first layer is deliberately transport-agnostic. NATS-specific adapters can
land after the contract surface settles.

## Quick start

Build the packages:

```bash
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
swift build --package-path swift
```

Run the examples:

```bash
dotnet run --project examples/dotnet/EchoWorker/EchoWorker.csproj
swift run --package-path examples/swift/echo-worker EchoWorker
```

## Documentation map

| Guide | Start here when... |
|-------|--------------------|
| [Concepts](CONCEPTS.md) | You want the protocol mental model. |
| [Getting Started](GETTING_STARTED.md) | You want to build and run the examples. |
| [Swift SDK](SWIFT.md) | You are implementing a Swift processor worker. |
| [.NET SDK](DOTNET.md) | You are implementing a C# / .NET processor worker. |
| [Examples](EXAMPLES.md) | You want copyable worker skeletons. |
| [Architecture](ARCHITECTURE.md) | You need the repo map and lifecycle. |
| [Contributing](CONTRIBUTING.md) | You are opening a PR. |
| [Coding Guide](CODING_GUIDE.md) | You are changing SDK code or docs. |

## Relationship to Heddle

The sibling `getheddle/heddle` repository owns the runtime framework,
canonical Pydantic models, exported JSON Schemas, router, orchestrators,
Workshop, and Python workers.
Its rendered docs live at <https://getheddle.github.io/heddle/>, and the
canonical SDK-facing protocol page is
[Foreign-Language Actors](https://getheddle.github.io/heddle/foreign-actors/).

This repository owns language-specific SDK surfaces that mirror that contract.
When upstream message models change, update `heddle` first, export schemas
there, copy `schemas/v1` here, then update the .NET and Swift wrappers.
