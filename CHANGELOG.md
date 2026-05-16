# Changelog

All notable changes to Heddle SDK are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
the project adheres to [Semantic Versioning](https://semver.org/).

CHANGELOG updates are **required** for commits that add, change,
deprecate, remove, or fix user-facing behaviour in either the .NET or
Swift surfaces, or in the wire-contract handling. Documentation-only
changes, internal refactors with no behavioural delta, and CI/build
adjustments are exempt. See `AGENTS.md` "Review checklist" for the
rule and `docs/CONTRIBUTING.md` for contributor-facing guidance.

## [Unreleased]

The SDK is pre-1.0 and pre-publication. All work to date is captured
here as `Unreleased` until the first NuGet and SwiftPM tag.

### Added

- Swift `CheckpointState` struct in
  `swift/Sources/HeddleActor/Models.swift`, mirroring the existing
  `.NET` `Heddle.Sdk.CheckpointState` record. Closes the C6
  (language parity) gap surfaced by the 2026-05-15 invariant audit:
  the JSON Schema and the .NET model have shipped `CheckpointState`
  for a while; Swift was missing it. Field types follow the
  established Swift conventions in this file
  (`completed_tasks` / `pending_tasks` → `[[String: JSONValue]]`;
  `created_at` defaulted via `HeddleClock.nowIso8601()` to match
  the .NET pattern). `swift build` + `swift test` clean.
- .NET contract models, subject helpers, shallow schema validation,
  and a transport-agnostic worker loop with an in-memory transport.
- Swift `Codable` contract models, subject helpers, shallow schema
  validation, and a transport-agnostic worker base with an in-memory
  transport.
- NATS transport adapters: .NET `Heddle.Sdk.Nats` for live-runtime
  interop; Swift `swift-nats` building the real `nats-io/nats.swift`
  binding on macOS (Linux exposes a buildable package surface only,
  pending upstream).
- Runnable .NET and Swift echo-worker examples.
- MkDocs documentation site with source-controlled draw.io diagrams.
- `schemas/v1/*.schema.json` vendored from upstream Heddle, with
  `tools/sync_schemas.py` and a manifest hash for drift detection.

## Contract sync

The wire contract is owned by upstream
[`getheddle/heddle`](https://github.com/getheddle/heddle). When this
SDK adopts a new upstream schema revision, the bump is recorded both
here (under the appropriate `Added` / `Changed` section) and in
`schemas/manifest.json`.

[Unreleased]: https://github.com/getheddle/heddle-sdk/commits/main
