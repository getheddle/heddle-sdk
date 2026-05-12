# Architecture

Heddle SDK mirrors the Heddle wire contract in language-native packages.

![SDK architecture](images/sdk-architecture.svg#only-light)
![SDK architecture](images/sdk-architecture-dark.svg#only-dark)

## Repository layout

```text
schemas/v1/
  checkpoint_state.schema.json
  orchestrator_goal.schema.json
  task_message.schema.json
  task_result.schema.json

dotnet/src/Heddle.Sdk/
  Models.cs
  Subjects.cs
  Transport.cs
  ShallowSchemaValidator.cs
  HeddleWorker.cs
  InMemoryHeddleTransport.cs

dotnet/src/Heddle.Sdk.Nats/
  NatsHeddleTransport.cs

swift/
  Package.swift
  Sources/HeddleActor/
    Models.swift
    Subjects.swift
    Transport.swift
    ShallowSchemaValidator.swift
    HeddleWorker.swift
    InMemoryTransport.swift

swift-nats/
  Package.swift
  Sources/HeddleActorNATS/
    NatsTransport.swift

examples/
  dotnet/EchoWorker/
  swift/echo-worker/
```

## Package layers

| Layer | Responsibility |
|-------|----------------|
| Schemas | Copied source of truth from Heddle's exported Pydantic models. |
| Models | Language-native types for `TaskMessage`, `TaskResult`, `OrchestratorGoal`, `CheckpointState`. |
| Subjects | Exact Heddle subject and queue-group conventions. |
| Validation | Shallow JSON Schema boundary checks matching Heddle's runtime behavior. |
| Worker base | Decode, validate, process, encode, publish, reset. |
| Core transports | Small publish/subscribe interface plus in-memory test transport. |
| NATS adapters | Separate packages that connect the same worker loop to NATS Core. |

## Worker lifecycle

![Worker lifecycle](images/worker-lifecycle.svg#only-light)
![Worker lifecycle](images/worker-lifecycle-dark.svg#only-dark)

The base workers own the repeated protocol work so application workers can
focus on `process`.

Malformed transport messages do not crash the process. They call a hook and the
subscription loop continues.

Processing failures become `TaskResult(status = failed)`. The result keeps the
task ID, parent task ID, worker type, and trace context so callers can correlate
the failure.

## Transport compatibility

The in-memory transports are same-process harnesses for tests, examples, and
Workshop-style local development. They mirror Heddle's `InMemoryBus` queue-group
behavior, but they do not create an IPC endpoint. A Swift or .NET process that
needs to participate in a live Heddle or Workshop runtime should use a shared
broker transport, usually NATS.

The NATS adapters live in separate packages so core SDK consumers can build and
test without pulling broker-client dependencies.

## Compatibility contract

Compatibility is defined by the upstream Heddle schemas and docs:

- `schemas/v1/*.schema.json`
- `getheddle/heddle/docs/foreign-actors.md`
- `getheddle/heddle/docs/DESIGN_INVARIANTS.md`

When the upstream Pydantic models change, this repository should change in the
same commit or release train:

1. Export schemas in `heddle`.
2. Copy updated schemas into `heddle-sdk/schemas/v1`.
3. Update .NET and Swift typed wrappers.
4. Update examples and docs.
5. Run SDK CI.
