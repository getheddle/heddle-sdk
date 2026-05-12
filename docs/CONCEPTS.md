# Concepts

Heddle SDKs are not Python bindings. They are typed views over Heddle's wire
protocol.

The useful boundary is:

```text
Heddle runtime           Heddle SDK worker
----------------        ----------------------------
Router                   Decodes TaskMessage JSON
Orchestrator             Validates payload shape
NATS bus         <---->  Processes a native payload
Python workers           Encodes TaskResult JSON
Workshop                 Publishes to result subject
```

## The envelope and the payload

Every task has two layers:

| Layer | Meaning |
|-------|---------|
| Envelope | Routing, lifecycle, metadata, trace context. Stable across worker types. |
| Payload | Worker-specific JSON object. Validated by the worker's input schema. |

`TaskMessage` is the request envelope. `TaskResult` is the response envelope.
Both use snake_case wire keys, even when the language API uses PascalCase or
camelCase names.

## Subjects

| Subject | Purpose |
|---------|---------|
| `heddle.tasks.incoming` | Client or orchestrator publishes tasks for routing. |
| `heddle.tasks.{worker_type}.{tier}` | Router dispatches tasks to worker replicas. |
| `heddle.results.{parent_task_id}` | Worker publishes a result for an orchestrator goal. |
| `heddle.results.default` | Worker publishes a standalone result. |
| `heddle.tasks.dead_letter` | Router publishes unroutable or rate-limited tasks. |
| `heddle.control.reload` | Optional hot-reload broadcast. |

Foreign processor workers should subscribe to
`heddle.tasks.{worker_type}.{tier}` with queue group
`processors-{worker_type}`. Queue groups prevent every replica from receiving
the same task.

## Worker lifecycle

![Worker lifecycle](images/worker-lifecycle.svg#only-light)
![Worker lifecycle](images/worker-lifecycle-dark.svg#only-dark)

The SDK worker base follows the upstream Heddle lifecycle:

1. Receive bytes from a transport.
2. Decode a `TaskMessage`.
3. Skip malformed input and keep the loop alive.
4. Run shallow input validation.
5. Decode the worker payload into a native type.
6. Process the payload.
7. Encode output and verify it is a JSON object.
8. Run shallow output validation.
9. Publish a `TaskResult`.
10. Reset before the next task.

## Shallow schema validation

Heddle intentionally validates only the contract boundary:

- required top-level fields
- top-level JSON type checks

It does not implement full JSON Schema in the SDK core. That matches the Python
runtime and keeps foreign workers predictable. A worker may add stricter
domain validation inside `process`, but that stricter behavior should be local
to the worker.

## Trace context

Trace context rides as top-level `_trace_context`. SDKs preserve it on
`TaskResult`. A transport adapter or worker can integrate with OpenTelemetry,
but preserving the field verbatim is the minimum compatibility requirement.
