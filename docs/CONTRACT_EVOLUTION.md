# Contract Evolution

Heddle SDKs mirror the wire contract owned by `getheddle/heddle`. This page
defines how schema changes move from the Python runtime into published language
packages, and how client migrations should be handled.

## Source of truth

The canonical message models live in `heddle.core.messages` in the upstream
Heddle repository. Upstream exports those Pydantic models into
`schemas/v1/*.schema.json` (the `WireEnvelope` frame, the three core bodies and
the standalone `CheckpointState`) together with language-neutral conformance
fixtures in `schemas/v1/fixtures/`. This repository vendors both under the same
path.

The SDK repository also tracks `schemas/manifest.json`, which records:

- the upstream Heddle commit used for the last schema sync
- the schema version directory
- the SHA-256 hash of each vendored schema and fixture file

Run the local check before changing SDK models:

```bash
python tools/sync_schemas.py --check
```

To sync from a sibling checkout:

```bash
python tools/sync_schemas.py --update --upstream ../heddle
```

To compare the current SDK schemas against a sibling upstream checkout without
modifying files:

```bash
python tools/sync_schemas.py --check-upstream --upstream ../heddle
```

## Change classes

| Upstream change | Schema directory | SDK release | Client migration |
|-----------------|------------------|-------------|------------------|
| Add optional body field with a default | Keep `v1` | Minor or prerelease patch | Clients can upgrade SDKs when convenient; older receivers ignore the field |
| Add optional metadata convention | Keep `v1` | Minor or prerelease patch | Document the convention; no forced code change |
| Add required body field, or change a body's meaning | New `payload_type` (within v1) | Major or explicitly breaking prerelease | Clients must update constructors/decoders |
| Add or change a frame field | New `v2` | Major or explicitly breaking prerelease | Every SDK must update its frame codec |
| Rename or remove field | New `v2` | Major or explicitly breaking prerelease | Clients must migrate serialized data and code |
| Change field type or meaning | New `v2` | Major or explicitly breaking prerelease | Clients must migrate code and stored fixtures |
| Add enum value | Treat as breaking until SDKs support unknown values | Major or coordinated prerelease | Clients must update decoders or use unknown fallback |
| Add top-level Middleware-Lane key (`_`-prefixed) | Non-breaking | No SDK update needed; it is propagated as opaque JSON | None |

## SDK model rules

- Wire keys stay snake_case and must match the exported schemas.
- SDKs may expose idiomatic property names, but serialization must use the wire
  names.
- The frame is strict: an unknown top-level key that does not start with `_`
  is rejected. `_`-prefixed keys (the Middleware Lane) are kept as opaque JSON
  and copied from an inbound task frame to its result frame, in every SDK.
- Bodies are tolerant readers: unknown body keys are accepted and dropped, as
  the Python runtime does.
- Message text follows two I-JSON rules (unique member names at every depth;
  finite fraction/exponent numbers). A violation is a `frame` error in every
  SDK, checked before the JSON is decoded.
- Every SDK passes every vendored conformance fixture
  (`schemas/v1/fixtures/manifest.json`): valid fixtures round-trip by value,
  invalid ones are rejected at the layer named in `rejected_at`.
- Enums are strict today. Before public stable releases, add an unknown-value
  strategy or document enum additions as breaking.
- Shallow worker payload validation stays aligned with Heddle runtime behavior:
  required-field presence plus top-level JSON type checks.

## Trace context

`_trace_context` is a Middleware-Lane key used for W3C trace propagation. The
frame schema admits it through `patternProperties: {"^_": {}}`, and the SDKs
carry it like any other lane key: verbatim, from the inbound task frame to the
result frame. Its inner shape is defined by Heddle's foreign-actor protocol,
not by the exported schemas.

## Migration flow

1. Change upstream Heddle Pydantic models and protocol docs first.
2. Export schemas in `getheddle/heddle` and let upstream CI verify no drift.
3. In `heddle-sdk`, run:

   ```bash
   python tools/sync_schemas.py --update --upstream ../heddle
   ```

4. Update language models, validators, worker bases, and examples.
5. Run each SDK's fixture tests against the newly vendored fixtures, and add
   language tests for anything the fixtures do not cover.
6. Update docs with migration notes and supported-version caveats.
7. Release SDK packages with the upstream schema commit in the release notes.

## Compatibility promises

Before stable package releases, compatibility is best-effort and documented in
release notes. After stable package releases:

- Patch releases should not require client code changes.
- Minor releases may add optional fields or helper APIs.
- Major releases are the place for breaking wire-contract changes.
- A new `schemas/vN` directory should coexist with earlier schema directories
  for at least one major release cycle when practical.

release notes. After stable package releases:

- Patch releases should not require client code changes.
- Minor releases may add optional fields or helper APIs.
- Major releases are the place for breaking wire-contract changes.
- A new `schemas/vN` directory should coexist with earlier schema directories
  for at least one major release cycle when practical.
