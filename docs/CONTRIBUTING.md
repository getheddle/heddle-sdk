# Contributing

Thank you for contributing to Heddle SDK.

Read the sibling Heddle governance and design docs before making structural
changes:

- <https://github.com/getheddle/heddle/blob/main/GOVERNANCE.md>
- <https://github.com/getheddle/heddle/blob/main/docs/DESIGN_INVARIANTS.md>
- <https://github.com/getheddle/heddle/blob/main/docs/foreign-actors.md>

## Contribution boundaries

Good SDK contributions:

- Improve .NET or Swift parity with the Heddle wire protocol.
- Add transport adapters without coupling them to the core package.
- Improve examples, docs, and diagrams.
- Add tests for encoding, validation, worker lifecycle, or subject helpers.

Out of scope unless coordinated with upstream Heddle:

- New wire-envelope fields.
- New actor lifecycle semantics.
- Reimplementing Python LLM backends or knowledge silos.
- Making the core SDK depend on a concrete NATS client.

## Pull request checklist

Run:

```bash
python tools/sync_schemas.py --check
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
dotnet test dotnet/tests/Heddle.Sdk.Tests/Heddle.Sdk.Tests.csproj
dotnet build dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj
dotnet pack dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj --configuration Release --output artifacts/nuget
dotnet pack dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj --configuration Release --output artifacts/nuget
dotnet build examples/dotnet/EchoWorker/EchoWorker.csproj
swift package dump-package
swift build
swift build --package-path swift
swift test --package-path swift
swift build --package-path swift-nats
swift build --package-path examples/swift/echo-worker
uvx --from mkdocs --with mkdocs-material mkdocs build --strict
```

For docs diagrams, edit `.drawio` sources under `docs/diagrams/`. CI exports
SVGs to `docs/images/` and generates dark variants.

When upstream Heddle message schemas change, sync from a local sibling checkout:

```bash
python tools/sync_schemas.py --update --upstream ../heddle
```

Then update language models, examples, and docs according to
[Contract Evolution](CONTRACT_EVOLUTION.md).

## AI-assisted development

`AGENTS.md` documents the shared project rules for AI-assisted work.
`CLAUDE.md` is only a Claude-specific pointer back to those rules.
AI-generated code is reviewed under the same standards as human-authored code:
wire compatibility, language parity, tests, and documentation.
