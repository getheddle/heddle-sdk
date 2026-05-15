# AGENTS.md — Heddle SDK

`heddle-sdk` is the sibling repository for Heddle language SDKs. It
packages the Heddle wire contract for non-Python processor workers,
starting with .NET and Swift.

The canonical runtime remains [`getheddle/heddle`](https://github.com/getheddle/heddle).
This repository must feel like a natural extension of that project: same
message envelopes, same subject conventions, same stateless-worker rules,
same documentation quality bar.

This file is the source of truth for agent guidance in *this* repo.
Cross-repo guidance, invariants, philosophy, and the wire-protocol
contract live in
**[`heddle-agent-toolkit/`](../heddle-agent-toolkit/)** —
read those before structural work.

## Toolkit install

The toolkit is sibling to this repo. To populate `.claude/skills/` and
`.claude/agents/` from a fresh clone:

```bash
git clone https://github.com/getheddle/heddle-agent-toolkit.git ../heddle-agent-toolkit
../heddle-agent-toolkit/install.sh .
```

Until the toolkit is published, contributors will need a local sibling
checkout. The skills and subagents named in this doc come from there.

## Read first

### From the toolkit (shared across `getheddle/*`)

- `heddle-agent-toolkit/anchors/ECOSYSTEM.md` — where this repo sits.
- `heddle-agent-toolkit/anchors/PHILOSOPHY.md` — design opinions.
- `heddle-agent-toolkit/anchors/INVARIANTS.md` — non-negotiable rules,
  with cross-repo invariants C1–C7 specifically governing this repo.
- `heddle-agent-toolkit/anchors/CONTRACT_MAP.md` — wire protocol,
  subjects, schema flow, change workflow.

### From this repo

- `docs/ARCHITECTURE.md` — SDK module map and relationship to Heddle.
- `docs/CONCEPTS.md` — protocol concepts in plain language.
- `docs/PORTING.md` — checklist for adding JVM or another language SDK.
- `docs/PUBLISHING.md` — NuGet and SwiftPM release readiness checklist.
- `docs/ROADMAP.md` — planned schema, publishing, and JVM work.
- `docs/CONTRACT_EVOLUTION.md` — schema sync and migration policy.
- `docs/CODING_GUIDE.md` — language-specific style and docs standards.
- `docs/CONTRIBUTING.md` — contribution boundaries and review expectations.
- `../heddle/docs/foreign-actors.md` — canonical foreign-actor wire protocol.

## Verification commands

```bash
python tools/sync_schemas.py --check
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
dotnet test dotnet/tests/Heddle.Sdk.Tests/Heddle.Sdk.Tests.csproj
dotnet build dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj
dotnet build examples/dotnet/EchoWorker/EchoWorker.csproj
swift package dump-package
swift build
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

CI exports `docs/diagrams/*.drawio` to `docs/images/*.svg` using draw.io
and then regenerates dark variants.

The toolkit's `/heddle-preflight` skill runs the standard pre-commit
subset and reports pass/fail. The toolkit's `/heddle-contract-sync`
skill wraps the upstream sync workflow.

## Repository map

```text
schemas/v1/              Copied canonical JSON Schemas from heddle
schemas/manifest.json    Upstream schema commit and schema file hashes
tools/sync_schemas.py    Schema sync and manifest check tool
Package.swift            Root SwiftPM publication surface
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

## Repo-specific rule

Cross-repo invariants C1–C7 (toolkit) govern the seam to `heddle`. In
addition, **malformed messages are skipped, not process-fatal**: the
worker base catches malformed input, calls the malformed-message hook,
and keeps the subscription loop alive. This mirrors heddle's framework
invariant #8 and applies to every language SDK.

## Review checklist (this repo)

Before committing:

- Does this keep .NET and Swift behavior aligned (cross-repo invariant C6)?
- Does it preserve Heddle's subject naming and queue-group conventions
  (C2)?
- Does it keep the SDK core free of transport-specific dependencies (C5)?
- Does any docs change link back to the Heddle source of truth where
  needed?
- Do the examples compile from a fresh checkout?
- If schemas changed: did `/heddle-contract-sync` complete cleanly?
- For non-trivial work: did you spawn `heddle-architect` first?
- For seam diffs: did you spawn `heddle-contract-reviewer` to verify the
  cross-language coherence?
- **Does this commit add, change, deprecate, remove, or fix
  user-facing behaviour?** If yes, add an entry under `[Unreleased]` in
  [`CHANGELOG.md`](CHANGELOG.md) (Added / Changed / Deprecated /
  Removed / Fixed / Security). Documentation-only changes, internal
  refactors with no behavioural delta, and CI/build adjustments are
  exempt.
