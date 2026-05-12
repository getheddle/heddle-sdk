# Contract Evolution

Heddle SDKs mirror the wire contract owned by `getheddle/heddle`. This page
defines how schema changes move from the Python runtime into published language
packages, and how client migrations should be handled.

## Source of truth

The canonical message models live in `heddle.core.messages` in the upstream
Heddle repository. Upstream exports those Pydantic models into
`schemas/v1/*.schema.json`; this repository vendors those files under the same
path.

The SDK repository also tracks `schemas/manifest.json`, which records:

- the upstream Heddle commit used for the last schema sync
- the schema version directory
- the SHA-256 hash of each vendored schema file

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
| Add optional envelope field with a default | Keep `v1` | Minor or prerelease patch | Clients can upgrade SDKs when convenient |
| Add optional metadata convention | Keep `v1` | Minor or prerelease patch | Document the convention; no forced code change |
| Add required field | New `v2` | Major or explicitly breaking prerelease | Clients must update constructors/decoders |
| Rename or remove field | New `v2` | Major or explicitly breaking prerelease | Clients must migrate serialized data and code |
| Change field type or meaning | New `v2` | Major or explicitly breaking prerelease | Clients must migrate code and stored fixtures |
| Add enum value | Treat as breaking until SDKs support unknown values | Major or coordinated prerelease | Clients must update decoders or use unknown fallback |
| Add top-level envelope extension | Prefer schema update; if not in schema, document as extension | Minor if preserved safely | Clients should preserve unknown fields where possible |

## SDK model rules

- Wire keys stay snake_case and must match the exported schemas.
- SDKs may expose idiomatic property names, but serialization must use the wire
  names.
- Unknown fields should be preserved when the language makes that practical.
  .NET currently preserves extension data; Swift currently models the known
  `_trace_context` extension but does not preserve arbitrary unknown fields.
- Enums are strict today. Before public stable releases, add an unknown-value
  strategy or document enum additions as breaking.
- Shallow worker payload validation stays aligned with Heddle runtime behavior:
  required-field presence plus top-level JSON type checks.

## Trace context

`_trace_context` is a documented top-level envelope extension used for W3C
trace propagation. SDKs should preserve it when present and publish it back on
`TaskResult`.

Today this field is documented by Heddle's foreign-actor protocol and modeled
by the SDKs, but it is not present in the exported `schemas/v1` files. Treat it
as a compatibility-sensitive extension until upstream decides whether to add it
to the canonical schemas.

## Migration flow

1. Change upstream Heddle Pydantic models and protocol docs first.
2. Export schemas in `getheddle/heddle` and let upstream CI verify no drift.
3. In `heddle-sdk`, run:

   ```bash
   python tools/sync_schemas.py --update --upstream ../heddle
   ```

4. Update language models, validators, worker bases, and examples.
5. Add or update golden JSON fixtures and language tests.
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
