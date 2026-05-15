# Adding a Language SDK

This guide defines the expected shape for adding another Heddle language SDK.
Use it before starting JVM, Go, Rust, TypeScript, or any other runtime.

The goal is language-native worker authoring without a new protocol. Every SDK
must speak the same Heddle wire contract exported from `getheddle/heddle`.

## Required package shape

Each language should start with a small core package:

- wire models for `TaskMessage`, `TaskResult`, `OrchestratorGoal`, and
  `CheckpointState`
- subject helpers for Heddle task/result/control subjects
- shallow schema validation for worker input and output payloads
- worker base or runner that decodes, validates, processes, publishes, and
  resets
- transport interface with publish/subscribe semantics
- in-memory transport for examples and tests

Broker-specific packages should live beside the core package, not inside it:

- NATS adapter
- future broker adapters, if Heddle supports them upstream
- platform-specific transports such as Android-specific bindings, if needed

## Contract source

Never hand-author a different contract.

1. Start from `schemas/v1/*.schema.json`.
2. Verify the manifest:

   ```bash
   python tools/sync_schemas.py --check
   ```

3. If upstream changed, sync first:

   ```bash
   python tools/sync_schemas.py --update --upstream ../heddle
   ```

4. Follow [Contract Evolution](CONTRACT_EVOLUTION.md) for migration rules.

New SDKs must preserve `_trace_context` when present and include it on
`TaskResult`. See
[Contract Evolution → Trace context](CONTRACT_EVOLUTION.md#trace-context)
for the full rule (it's a documented envelope extension, not yet in the
exported schemas).

## Model rules

- Preserve snake_case wire keys exactly.
- Use idiomatic property names in the host language when serializers can map
  them cleanly.
- Encode timestamps as ISO 8601 strings compatible with upstream Heddle.
- Keep payload, output, metadata, and context as JSON-object-shaped values.
- Preserve unknown fields when practical. If the ecosystem makes that awkward,
  document the limitation.
- Decide enum behavior before publication. Strict enums are simple, but
  upstream enum additions become breaking changes unless the SDK has an
  unknown-value strategy.

## Worker lifecycle

A processor worker must:

1. Subscribe to `heddle.tasks.{worker_type}.{tier}`.
2. Use queue group `processors-{worker_type}` for broker-backed transports.
3. Decode incoming bytes as `TaskMessage`.
4. Skip malformed messages and continue the subscription loop.
5. Validate input with Heddle's shallow schema behavior.
6. Run native processing code.
7. Validate output with the same shallow behavior.
8. Publish `TaskResult` to `heddle.results.{parent_task_id or "default"}`.
9. Reset per-task state before reading the next message.

The worker base should make the safe lifecycle the default path.

## Validation scope

Heddle's runtime intentionally uses shallow JSON Schema checks:

- required top-level fields
- top-level property type checks
- object-shaped worker payloads and outputs

Do not make full JSON Schema validation the default unless the stricter
behavior is explicitly documented for that SDK.

## Transport interface

The core package should depend on a minimal transport boundary:

- publish subject + bytes
- subscribe subject + optional queue group
- async cancellation or disposal according to language norms

The in-memory transport should exercise the same worker loop as broker-backed
transports. Examples should use in-memory by default so they run from a fresh
checkout without infrastructure.

## NATS adapter

Add NATS only after the core package is usable.

The adapter must preserve:

- Heddle subject names
- queue groups for processor workers
- at-most-once Core NATS assumptions
- subscribe-before-publish expectations for callers waiting on results
- cancellation/disposal semantics that do not strand subscriptions

If the official NATS client has platform gaps, document them in the language
guide and keep the core package buildable on unsupported platforms.

## Required tests

Every SDK should include tests for:

- model encode/decode using representative JSON envelopes
- subject helper output
- shallow schema success and failure cases
- worker success path
- worker failure path
- malformed-message skip behavior
- trace-context preservation
- in-memory transport publish/subscribe behavior

As the repository matures, these should converge on shared golden JSON fixtures
so every language proves the same wire behavior.

## Required docs and examples

Each new language needs:

- language guide under `docs/`
- runnable echo worker example
- NATS usage section when the adapter exists
- Workshop compatibility notes
- package publication notes
- status row in the docs home page and roadmap

Examples should compile without a live broker. Live interop examples may be
documented as optional snippets.

## JVM recommendation

For JVM, prefer a Kotlin-authored core with Java-friendly APIs:

- Kotlin data classes or equivalent model types
- Java callers should not need Kotlin-only conventions for basic worker code
- coroutines are reasonable for Kotlin, but Java needs a clear
  `CompletableFuture` or blocking bridge
- Scala should work naturally through the Java/Kotlin public API
- Android should start as compatibility testing against the same core surface;
  split an Android-specific transport only if the NATS/client stack requires it

Keep the first JVM milestone small: core package, in-memory transport, Kotlin
echo example, Java echo example, then NATS.
