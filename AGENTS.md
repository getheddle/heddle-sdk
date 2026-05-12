# AGENTS.md — Heddle SDK

## What this repository is

`heddle-sdk` is the sibling repository for Heddle language SDKs. It packages
the Heddle wire contract for non-Python processor workers, starting with .NET
and Swift.

The canonical runtime remains [`getheddle/heddle`](https://github.com/getheddle/heddle).
This repository must feel like a natural extension of that project: same
message envelopes, same subject conventions, same stateless-worker rules, and
the same documentation quality bar.

## Read first

- `CLAUDE.md` — Claude-specific pointer to this file.
- `docs/ARCHITECTURE.md` — SDK module map and relationship to Heddle.
- `docs/CONCEPTS.md` — protocol concepts in plain language.
- `docs/PORTING.md` — checklist for adding JVM or another language SDK.
- `docs/ROADMAP.md` — planned schema, publishing, and JVM work.
- `docs/CONTRACT_EVOLUTION.md` — schema sync and migration policy.
- `docs/CODING_GUIDE.md` — language-specific style and docs standards.
- `docs/CONTRIBUTING.md` — contribution boundaries and review expectations.
- `../heddle/docs/foreign-actors.md` — canonical foreign-actor wire protocol.
- `../heddle/docs/DESIGN_INVARIANTS.md` — upstream design invariants.

## Non-negotiable rules

- **Do not invent a second protocol.** `schemas/v1/*.schema.json` are copied
  from `getheddle/heddle` and represent the wire contract. Use
  `tools/sync_schemas.py` to update or verify the copied files.
- **Workers are stateless.** SDK worker bases must reset between tasks and must
  not encourage per-process task memory.
- **Transport stays abstract in core packages.** NATS adapters can live beside
  the core packages later; the first layer remains dependency-light.
- **Foreign workers are processor workers.** Do not reimplement Heddle's Python
  LLM backend, knowledge-silo, Workshop, or orchestration surfaces here unless
  the upstream framework explicitly defines that expansion.
- **Malformed messages are skipped, not process-fatal.** Bad input should call
  the malformed-message hook and keep the subscription loop alive.
- **Keep examples runnable without infrastructure.** Examples may show where a
  NATS adapter plugs in, but the checked-in examples should compile and run
  without a live server.

## Verification commands

```bash
python tools/sync_schemas.py --check
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
dotnet test dotnet/tests/Heddle.Sdk.Tests/Heddle.Sdk.Tests.csproj
dotnet build dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj
dotnet build examples/dotnet/EchoWorker/EchoWorker.csproj
swift build --package-path swift
swift test --package-path swift
swift build --package-path swift-nats
swift build --package-path examples/swift/echo-worker
```

Docs:

```bash
uvx --from mkdocs --with mkdocs-material mkdocs build --strict
```

Diagrams:

```bash
python docs/diagrams/make_dark_variants.py
```

CI exports `docs/diagrams/*.drawio` to `docs/images/*.svg` using draw.io and
then regenerates dark variants.

## Repository map

```text
schemas/v1/              Copied canonical JSON Schemas from heddle
schemas/manifest.json    Upstream schema commit and schema file hashes
tools/sync_schemas.py    Schema sync and manifest check tool
dotnet/src/Heddle.Sdk/   .NET contract models and worker base
dotnet/src/Heddle.Sdk.Nats/
                         .NET NATS transport adapter
dotnet/tests/            .NET SDK tests
swift/                   SwiftPM package: HeddleActor
swift-nats/              SwiftPM NATS transport adapter
examples/dotnet/         Runnable .NET examples
examples/swift/          Runnable Swift examples
docs/                    MkDocs site
docs/diagrams/           draw.io source diagrams
docs/images/             exported SVG diagrams
```

## Review checklist

Before committing, ask:

- Does this keep .NET and Swift behavior aligned?
- Does it preserve Heddle's subject naming and queue-group conventions?
- Does it keep the SDK core free of transport-specific dependencies?
- Does any docs change link back to the Heddle source of truth where needed?
- Do the examples compile from a fresh checkout?
