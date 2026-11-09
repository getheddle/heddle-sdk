# SDK Roadmap

Last updated: 2026-11-08

This roadmap captures the working plan for turning `heddle-sdk` into the
standard home for Heddle language SDKs. It is intentionally practical: each
batch should leave the repository easier to publish, easier to extend, and less
likely to drift from `getheddle/heddle`.

## Guiding decisions

- Heddle's Python repository remains the source of truth for runtime behavior,
  message envelopes, and exported JSON Schemas.
- SDK packages should make processor workers feel native in each ecosystem
  without creating a second protocol.
- Contract changes land upstream first, then move into SDK packages through a
  documented sync path.
- Publishing readiness and new-language work should use each ecosystem's
  normal tools instead of custom distribution paths.
- JVM support should be Kotlin-first, Java-friendly, and usable from Scala and
  Android where the transport stack allows it.

## Current baseline

| Area | Status |
|------|--------|
| Wire contract | All three SDKs speak heddle's v1 `WireEnvelope` frame (heddle v0.10.0+) and the two I-JSON text rules (v0.12.0+), and pass all 27 vendored conformance fixtures |
| Live interop | `tools/live_check/` runs .NET, Swift and JVM echo workers against a real heddle router over NATS (Docker) |
| .NET | Core SDK and `Heddle.Sdk.Nats`; `dotnet pack` verified in CI |
| Swift | Core SDK; NATS binding builds on macOS, Linux builds the package surface only |
| JVM | Kotlin/Java core and NATS adapter; built and tested in CI |
| Docs site | MkDocs site with language guides, NATS docs, Workshop compatibility, and draw.io-generated diagrams |
| Schema sync | Manifest, sync/check tooling and `--check-upstream`, run in CI |
| Package publishing | Not published. Readiness covers .NET and Swift; JVM (Maven) is not covered yet. Publication waits on the owner's planned enhancements (see *Publication gate*) |
| JS/TS SDK | Planned, not started |

## Publication gate

No SDK is published to NuGet, SwiftPM, Maven or npm yet. The owner plans
further enhancements before the first publication; they will be listed here
when defined. Until then, consumers build the SDKs from source.

## Batch 1: contract sync and migration policy (Completed)

Goal: make upstream schema drift visible and give client migrations a written
policy before more languages depend on the contract.

Deliverables:

- Add a schema manifest recording the upstream Heddle commit and SHA-256 hashes
  for vendored schema files.
- Add a local sync/check tool for copying `schemas/v1` from a sibling Heddle
  checkout and validating the checked-in manifest.
- Add CI coverage for schema manifest consistency.
- Document contract evolution rules for additive changes, breaking changes,
  enum changes, envelope extensions, and SDK release coordination.
- Make the schema workflow discoverable from the docs site and contributor
  checklist.

Exit criteria:

- `python tools/sync_schemas.py --check` passes from a clean checkout.
- The docs site explains how to sync schemas and how clients should migrate
  when upstream changes.

## Batch 2: language-porting guide

Goal: make adding another SDK a repeatable engineering exercise.

Status: first draft added in `docs/PORTING.md`; keep refining as JVM design
decisions become concrete.

Deliverables:

- Add `docs/PORTING.md` with the required model surface, transport boundary,
  subject helpers, shallow validation behavior, trace-context handling, tests,
  examples, and docs expectations.
- Define a minimal conformance checklist for every SDK:
  encode/decode golden fixtures, subject naming, worker loop lifecycle,
  in-memory transport, NATS adapter when ecosystem support is mature, and docs.
- Call out language-specific risks such as strict enums, unknown-field
  preservation, timestamp formats, and async cancellation semantics.

Exit criteria:

- A new language owner can start from `docs/PORTING.md` and know the required
  files, tests, examples, and publication expectations.

## Batch 3: package publishing readiness

Goal: make .NET, Swift and JVM releasable through standard ecosystem tooling.

Status: first readiness pass added root SwiftPM publication manifest,
NuGet package metadata, `dotnet pack` CI verification, and
`docs/PUBLISHING.md`. Open: the JVM (Maven) path is not in
`docs/PUBLISHING.md` yet.

Deliverables:

- Add .NET `dotnet pack` verification in CI for `Heddle.Sdk` and
  `Heddle.Sdk.Nats`.
- Add package README metadata, tags, SourceLink, symbol package settings, and a
  NuGet release checklist.
- Use a root package manifest in this repo as the SwiftPM publication surface.
- Add a Swift release checklist covering SemVer tags, package identity,
  supported platforms, and Swift Package Index compatibility.
- Document release versioning, prerelease channels, and package ownership.

Exit criteria:

- A dry-run release can produce local NuGet packages and a SwiftPM-consumable
  package reference without manual metadata fixes.

## Batch 4: JVM SDK (Completed)

Goal: add JVM support for server-side Java/Kotlin/Scala and a credible Android
path.

Status: Implemented in `jvm/` directory. Android compatibility has not been
verified: no Android build or test exists yet.

Deliverables:

- `jvm/core`: Kotlin/JVM core SDK with Java-friendly APIs.
- `jvm/nats`: NATS transport adapter using the official Java NATS client.
- `examples/jvm`: Kotlin and Java echo examples.
- Android support verified via compatibility testing against core surface
  (not done; see status).

## Batch 5: release automation and conformance

Goal: make every language release reproducible and comparable.

Status (2026-11-08): partly done. Cross-language golden fixtures exist (27,
vendored from heddle and run by every SDK in CI) and cover the frame and the
three message bodies, but not `CheckpointState`. Live interop is checked by
`tools/live_check/`. Not done: the conformance matrix, the release workflow
and the release notes template.

Deliverables:

- Cross-language golden fixtures for `TaskMessage`, `TaskResult`,
  `OrchestratorGoal`, and `CheckpointState`.
- A conformance matrix in docs showing which languages support in-memory,
  NATS, live Workshop interop, Android/mobile, and published packages.
- GitHub release workflow with package build artifacts and human approval
  before pushing to package registries.
- Release notes template with schema source commit, package versions, migration
  notes, and known platform caveats.

Exit criteria:

- A release candidate can be validated across all supported languages before
  any registry push.

## Batch 6: JavaScript / TypeScript SDK

Status: planned by the owner, not started.

Goal: add JS/TS support for Node.js (npm) and browser-side actors.

Proposed shape:

- `js/core`: TypeScript core SDK for Node.js and browser.
- `js/nats`: NATS transport adapter using `nats.js` or `nats.ws`.
- `examples/js`: Node.js echo worker and a simple browser-based worker.

Early design calls:

- TypeScript-first for better contract safety.
- ESM-only or dual-build (CJS/ESM) depending on ecosystem trends.
- Browser support via WebSockets (NATS WS) for direct-to-bus browser actors.

Exit criteria:

- JS/TS core and NATS packages build in CI.
- Node.js and browser echo examples interoperate with the same Heddle bus contract.
- Publication metadata is ready for npm.

## Open decisions

- Should Swift remain in this combined repo for publication, or move to a
  Swift-first repo once the API stabilizes?
- Should enum decoding become forward-compatible in all SDKs before the first
  public prerelease?
- What is the first JVM publication target: JVM-only, Android-compatible JVM,
  or Kotlin Multiplatform?

Resolved:

- `_trace_context` stays out of the exported schemas. It is a Middleware-Lane
  key carried as opaque JSON on the frame (heddle `DESIGN_INVARIANTS.md` #22;
  see [Contract Evolution → Trace context](CONTRACT_EVOLUTION.md#trace-context)).
