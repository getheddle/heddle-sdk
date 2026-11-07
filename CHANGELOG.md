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

### Changed (breaking)

- **Wire text follows heddle's two I-JSON rules** (getheddle/heddle#80): a
  member name repeated in any object, at any depth (compared after
  unescaping), or a fraction/exponent number that overflows a double, is a
  `frame` error, as is nesting deeper than 1000 levels. Integer literals keep
  their exact value. Each SDK enforces this before decoding: .NET with a
  `Utf8JsonReader` pass, Swift with a scanner (`JSONDecoder` cannot see
  repeated names), the JVM with Jackson's `STRICT_DUPLICATE_DETECTION` plus a
  non-finite check. Before this, .NET accepted nested repeats and threw the
  wrong exception for top-level ones, Swift kept the first value and the JVM
  the last. Synced the three new fixtures (27 in total).
- **No SDK sends non-finite numbers.** A worker result that cannot be written
  as wire JSON (for example `NaN` in the output) is published as a `failed`
  result instead; the JVM's `HeddleWire.serialize` now throws
  `IllegalArgumentException` for a non-finite number.
- **All three SDKs speak heddle's v1 `WireEnvelope` frame**
  ([#4](https://github.com/getheddle/heddle-sdk/issues/4)). This matches heddle
  v0.10.0 and later; earlier flat messages are no longer read or written.
  - New `HeddleWire` codec and `WireEnvelope` type in each SDK (`Wire.cs`,
    `Wire.swift`, `Wire.kt`): two-step parse (frame, then the body chosen by
    `payload_type`), `Wrap`/`wrap` and `Serialize`/`serialize`. Rejections
    name the layer (`frame`, `body`, `dispatch`).
  - The frame is strict (unknown non-`_` top-level keys are rejected) and
    carries the Middleware Lane: every `_`-prefixed key, as opaque JSON.
    Bodies are tolerant (unknown keys ignored).
  - Timestamps moved from the bodies to the frame (`occurred_at`,
    `recorded_at`): RFC 3339 with a mandatory offset, fractional seconds
    truncated to microseconds, leap second rejected. `created_at` and
    `completed_at` are gone.
  - `TaskMessage.payload` is now `input`. Required body fields
    (`worker_type`, `input`, `task_id` on results, `instruction`) have no
    defaults. Integer fields accept integral floats and reject strings and
    booleans. `TaskResult` token counts and timing are 64-bit.
  - The typed `_trace_context` / `TraceContext` fields and the .NET/JVM
    body extension data are gone; lane keys live on the frame.
- **Worker bases match upstream `heddle.worker.base`.** Each worker parses
  the frame; a bad frame, bad body, or a `payload_type` other than
  `core.TaskMessage` goes to the malformed-message hook and the loop
  continues. Results are framed with a fresh `message_id` and timestamps
  and a copy of the inbound lane. `process` receives the task metadata plus
  `model_tier`; `token_usage` always has exactly `prompt_tokens` and
  `completion_tokens`; `processing_time_ms` is set on failures too;
  output-validation failures keep `model_used` and token counts (.NET and
  Swift; the JVM base still takes no schemas and checks only that output is
  a JSON object).
  - Swift: `handle(_ data:)` returns the framed result (`WireEnvelope?`).
  - JVM: new `onMalformedMessage` and `reset` hooks (malformed messages were
    only logged, and there was no reset); results echo the task's
    `worker_type` instead of the worker's own.
- **Conformance fixtures.** `tools/sync_schemas.py` now vendors heddle's
  `schemas/v1/fixtures/**` and hashes them in `schemas/manifest.json`. Every
  SDK's tests run all 24 fixtures from `manifest.json`.
- `schemas/v1/` now has `wire_envelope.schema.json`.
- CI has a `jvm` job (Temurin 21). The JVM SDK had no CI before.

### Removed

- The event-sourcing models and helpers added for upstream's
  `heddle.contrib.events` Sprint 1 (listed under *Added* below):
  `EventEnvelope`, `EventMetadata`, `CommandMessage`, `CommandMetadata`,
  `EventSubjects` and `IssuerConventions` in .NET and Swift, the matching
  Kotlin models, and the vendored `event_envelope` / `command_message`
  schemas. Upstream removed those schemas, and `events.*` bodies are not part
  of the exported contract (heddle `contrib.events` is experimental).
- The JVM's committed Gradle caches and build outputs (`jvm/.gradle`,
  `jvm/**/build`); they are now ignored.

### Known limitations

- `message_id` is a random UUID (v4); upstream generates UUIDv7 for it. Both
  satisfy the schema, which requires only a string. (`task_id` and `goal_id`
  are v4 in both.)
- Swift's `JSONValue` turns an integer outside the 64-bit range inside opaque
  JSON (`input`, `output`, `metadata`, `context`, lane values) into a `Double`,
  so it does not round-trip exactly. .NET and the JVM keep it.
- Frame timestamps must be representable in UTC between years 0001 and 9999,
  since the SDKs write them in UTC. Python also accepts offsets that move an
  instant just past those bounds.
- When a worker parses `input` into its own payload type, .NET (System.Text.Json
  Web defaults) and the JVM (Jackson) coerce some values that Swift rejects.
  Pass an input schema, or validate in `process`, if that matters.

### Added

- Event-sourcing wire contract (Sprint 1 of upstream M2 plan):
  - Vendored schemas `event_envelope.schema.json` and
    `command_message.schema.json` from upstream heddle into
    `schemas/v1/`; `schemas/manifest.json` rewritten by
    `tools/sync_schemas.py --update --upstream ../heddle`.
  - Swift Codable models — `EventEnvelope`, `EventMetadata`,
    `CommandMessage`, `CommandMetadata` in
    `HeddleActor/Models.swift`.
  - Swift subject helpers — `EventSubjects.event` / `.command` /
    `.rejection` / `.eventStream` / `.commandStream` /
    `.rejectionStream` / `.eventFilter` / `.commandFilter` /
    `.rejectionFilter` in `HeddleActor/Subjects.swift`.
  - Swift issuer-convention validators —
    `HeddleActor/IssuerConventions.swift` with all six prefixes
    (`framework:`, `observer:`, `projector:`, `user:`,
    `user:system:`, `bridge:`) and multi-segment suffix support.
  - .NET POCOs for the same four envelope types in
    `Heddle.Sdk/Models.cs`.
  - .NET subject helpers — `EventSubjects` static class in
    `Heddle.Sdk/Subjects.cs`.
  - .NET issuer-convention validators —
    `Heddle.Sdk/IssuerConventions.cs`.
  - Swift and .NET tests cover round-trip, subject formation, and
    issuer validation including the two required multi-segment-suffix
    cases (`user:system:emergency_correction:eng-42` and
    `framework:cascade:retry:3`).
  - Refs: upstream `heddle-contrib-events-m2-architecture-v7.md`
    §4.1, §6 Sprint 1.

### Changed

- Formalized the **Middleware Lane** propagation policy: SDKs MUST capture and propagate all top-level JSON keys starting with an underscore (e.g., ``_trace_context``) verbatim. This ensures forward-compatibility for cross-cutting concerns like tracing without requiring SDK schema updates. Documentation updated in ``docs/PORTING.md`` and ``docs/CONTRACT_EVOLUTION.md``.
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
