# Coding Guide

The SDK spans C#, Swift, docs, examples, and generated diagrams. Keep changes
small, explicit, and aligned across languages.

## General rules

- Preserve upstream wire names exactly.
- Prefer standard-library types and dependency-light implementations.
- Keep transport-specific code outside the core SDK packages.
- Add docs and examples when a new public concept appears.
- Keep examples runnable without NATS or external services.

## .NET style

- Target `net8.0`.
- Use nullable reference types.
- Use `System.Text.Json` and explicit `JsonPropertyName` attributes for wire
  fields.
- Keep public APIs documented when package warnings are enabled.
- Public records should be immutable or init-only.
- Worker examples should use `HeddleWorker<TPayload, TOutput>`.

Verify:

```bash
dotnet build dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj
dotnet build examples/dotnet/EchoWorker/EchoWorker.csproj
```

## Swift style

- Use Swift 6 package manifests.
- Public payload/output examples should be `Codable` and `Sendable`.
- Keep wire models `Codable`, `Equatable`, and `Sendable` where practical.
- Use snake_case only in `CodingKeys`; Swift property names stay idiomatic.
- Worker examples should use `HeddleWorker<Payload, Output>`.

Verify:

```bash
swift build --package-path swift
swift test --package-path swift
swift build --package-path examples/swift/echo-worker
```

## Documentation style

- Write docs for someone building a worker, not for someone reading every
  source file.
- Link to upstream Heddle docs for canonical runtime behavior.
- Prefer small code examples that compile.
- Put diagrams in `.drawio` source files and reference exported SVGs from docs.

## Diagram workflow

- Source: `docs/diagrams/*.drawio`
- Exported light SVG: `docs/images/<name>.svg`
- Exported dark SVG: `docs/images/<name>-dark.svg`
- CSS hooks: `#only-light` and `#only-dark`

Reference both variants:

```markdown
![Caption](images/<name>.svg#only-light)
![Caption](images/<name>-dark.svg#only-dark)
```
