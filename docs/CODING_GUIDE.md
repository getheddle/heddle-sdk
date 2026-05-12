# Coding Guide

The SDK spans C#, Swift, docs, examples, and generated diagrams. Keep changes
small, explicit, and aligned across languages.

## General rules

- Preserve upstream wire names exactly.
- Run `python tools/sync_schemas.py --check` before changing contract models.
- Prefer standard-library types and dependency-light implementations.
- Keep broker-specific code outside the core SDK packages.
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
dotnet build dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj
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
swift build --package-path swift-nats
swift build --package-path examples/swift/echo-worker
```

### macOS C++ header setup

`swift-nats` depends on SwiftNIO SSL, which compiles C++ sources. On some macOS
Command Line Tools installs, `clang++` may fail before Swift code compiles:

```text
fatal error: 'memory' file not found
```

First confirm the host toolchain:

```bash
xcode-select -p
xcrun --show-sdk-path
printf '#include <memory>\n' > /tmp/check-memory.cc
clang++ -std=c++17 -fsyntax-only /tmp/check-memory.cc
```

If the last command fails but the header exists under
`$(xcrun --show-sdk-path)/usr/include/c++/v1`, either install/select full
Xcode, or export the SDK libc++ include path before building:

```bash
export CPLUS_INCLUDE_PATH="$(xcrun --show-sdk-path)/usr/include/c++/v1${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
swift build --package-path swift-nats
```

For a persistent shell setup, add that `CPLUS_INCLUDE_PATH` export to your
shell profile. Do not bake this path into package manifests; it is local
developer-toolchain repair.

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

## Schema sync

The upstream Heddle repository exports canonical schemas from Pydantic models.
This SDK vendors those files and records their hashes in `schemas/manifest.json`.

Verify the local manifest:

```bash
python tools/sync_schemas.py --check
```

Sync from a sibling checkout:

```bash
python tools/sync_schemas.py --update --upstream ../heddle
```

Compare without modifying files:

```bash
python tools/sync_schemas.py --check-upstream --upstream ../heddle
```

After any schema sync, update typed wrappers, examples, and migration notes in
[Contract Evolution](CONTRACT_EVOLUTION.md).
