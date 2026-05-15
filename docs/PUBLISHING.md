# Publishing SDK Packages

This page captures the release path for Heddle SDK packages. It is a readiness
checklist, not an instruction to publish from CI automatically.

## Versioning

Package versions should move together across ecosystems when they share the
same wire contract.

- Use prerelease versions such as `0.1.0-alpha.1` until the public API and
  contract migration policy settle.
- Patch releases should not require client code changes.
- Minor releases may add optional helpers, optional envelope fields, or new
  transport adapters.
- Breaking wire-contract changes require a new schema directory and a major
  version or explicitly breaking prerelease.
- Release notes must include the upstream Heddle schema commit from
  `schemas/manifest.json`.

## Release checklist

Before any package registry push:

```bash
python tools/sync_schemas.py --check
dotnet test dotnet/tests/Heddle.Sdk.Tests/Heddle.Sdk.Tests.csproj --configuration Release
dotnet pack dotnet/src/Heddle.Sdk/Heddle.Sdk.csproj --configuration Release --output artifacts/nuget
dotnet pack dotnet/src/Heddle.Sdk.Nats/Heddle.Sdk.Nats.csproj --configuration Release --output artifacts/nuget
swift package dump-package
swift build
swift test --package-path swift
swift build --package-path examples/swift/echo-worker
uvx --from mkdocs --with mkdocs-material mkdocs build --strict
```

On macOS Command Line Tools installations where C++ headers are not
found, see
[Coding Guide → macOS C++ header setup](CODING_GUIDE.md#macos-c-header-setup)
for the diagnosis and workaround.

## NuGet

The .NET packages are:

- `Heddle.Sdk`
- `Heddle.Sdk.Nats`

The project files include package metadata, README inclusion, SourceLink,
symbol package generation, repository metadata, license expression, and package
tags. CI runs `dotnet pack` and uploads `.nupkg` / `.snupkg` files as build
artifacts.

Manual publish shape:

```bash
dotnet nuget push artifacts/nuget/Heddle.Sdk.*.nupkg \
  --source https://api.nuget.org/v3/index.json \
  --api-key "$NUGET_API_KEY"

dotnet nuget push artifacts/nuget/Heddle.Sdk.Nats.*.nupkg \
  --source https://api.nuget.org/v3/index.json \
  --api-key "$NUGET_API_KEY"
```

Do not wire NuGet API keys into CI until package ownership, release approval,
and rollback expectations are settled.

## SwiftPM

The repository root now contains a SwiftPM manifest so consumers can depend on
the repository URL directly:

```swift
.package(url: "https://github.com/getheddle/heddle-sdk.git", from: "0.1.0")
```

Products:

- `HeddleActor`
- `HeddleActorNATS`

The nested `swift/` and `swift-nats/` manifests remain useful for focused local
development and CI checks. The root manifest is the publication surface for
standard SwiftPM discovery and Swift Package Index.

Swift release checklist:

- Tag SemVer releases from the repository root.
- Ensure `swift package dump-package` passes at the root.
- Ensure `swift build` passes on Linux for the package surface.
- Ensure `swift build --package-path swift-nats` passes on macOS for the real
  NATS binding.
- Keep the Swift platform caveat visible: the real `nats-io/nats.swift`
  binding currently builds on macOS; Linux builds the package surface.

## Ownership and secrets

Before the first public push:

- Confirm NuGet package IDs are owned by the Heddle maintainers.
- Confirm Swift Package Index can ingest the root package.
- Decide whether package publishing is manual, GitHub Release assisted, or
  fully automated after approval.
- Add registry secrets only after the release approval flow is documented.
