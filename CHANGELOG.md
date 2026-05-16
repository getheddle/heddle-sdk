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

### Changed

- `Models.cs` and `Models.swift` gain XML / DocC doc comments on
  every public type. The doc comments explain what each envelope is,
  when application code constructs vs receives it, the wire-protocol
  relationship, and (for `WorkerOutput<T>`) an explicit
  not-a-wire-type callout with the rationale. Mirrors the rationale
  between languages so .NET and Swift readers see the same shape.
  Resolves audit-question on `WorkerOutput<T>`
  (`INVARIANT_AUDIT_2026-05-15.md` S1) via option (a): document as
  SDK-ergonomic only, never serialised to bus. Investigation
  confirmed: `HeddleWorker` base classes in both languages transform
  `WorkerOutput` into the wire `TaskResult` envelope in
  `HandleAsync` / `handle(_:)` — `WorkerOutput` never reaches the
  bus directly. The previously-flagged .NET/Swift parity difference
  on `Metadata` / `TokenUsage` nullability (.NET nullable +
  null-default vs Swift non-optional + empty-default) is documented
  as language-idiomatic and behaviourally equivalent — the base
  class normalises both to the same wire shape, so C6 parity is
  preserved at the wire level even though the type signatures
  differ.
- `HeddleWorker.cs` and `HeddleWorker.swift` gain doc comments on
  the class, `ProcessAsync` / `process`, `ResetAsync` / `reset`, and
  the malformed-message hooks. Documents the SDK-author boundary
  explicitly: what you implement, what the base class handles for
  you, what you do NOT do. C3 (stateless workers) and C5 (transport-
  agnostic core) invariants surfaced as load-bearing rationale.
- `docs/CONCEPTS.md` gains a new "Writing a worker — the SDK
  author's API" section. Contrasts wire envelope (`TaskResult`,
  serialised to bus) with SDK return type (`WorkerOutput`, never
  serialised). Includes side-by-side .NET / Swift signatures, a
  table of what the base class handles, and the minimum echo-worker
  example in both languages.

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
