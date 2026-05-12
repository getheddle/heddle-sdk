# Swift SDK

The Swift package is named `HeddleActor`. It provides `Codable` wire models,
subject helpers, shallow schema validation, and a generic worker base.

## Add the package

For a local checkout:

```swift
dependencies: [
    .package(path: "../../swift")
]
```

For a Git dependency:

```swift
dependencies: [
    .package(url: "https://github.com/getheddle/heddle-sdk.git", branch: "main")
]
```

Use the `HeddleActor` product:

```swift
.product(name: "HeddleActor", package: "heddle-sdk")
```

## Define payload and output types

```swift
import HeddleActor

struct EchoPayload: Codable, Sendable {
    var text: String
}

struct EchoOutput: Codable, Sendable {
    var text: String
    var length: Int
}
```

Payload types decode from `TaskMessage.payload`. Output types must encode to a
JSON object; arrays and primitive outputs fail the worker contract because
`TaskResult.output` is object-shaped.

## Implement a worker

```swift
final class EchoWorker: HeddleWorker<EchoPayload, EchoOutput>, @unchecked Sendable {
    init() {
        super.init(workerType: "echo", tier: "local")
    }

    override func process(
        payload: EchoPayload,
        metadata: [String: JSONValue]
    ) async throws -> WorkerOutput<EchoOutput> {
        WorkerOutput(
            output: EchoOutput(
                text: payload.text.uppercased(),
                length: payload.text.count
            ),
            modelUsed: "swift-example"
        )
    }
}
```

## Run with a transport

The core SDK defines the transport boundary:

```swift
public protocol HeddleTransport: Sendable {
    func publish(subject: String, payload: Data) async throws

    func subscribe(
        subject: String,
        queueGroup: String?
    ) async throws -> AsyncThrowingStream<HeddleMessage, Error>
}
```

The core package includes an in-memory implementation for local examples and
tests:

```swift
let transport = InMemoryTransport()
try await EchoWorker().run(transport: transport)
```

A broker adapter can implement the same protocol without changing worker code:

```swift
try await EchoWorker().run(transport: natsTransport)
```

Use the shipped NATS adapter package for Heddle runtime interop:

```swift
import HeddleActorNATS

let transport = NatsTransport(url: URL(string: "nats://localhost:4222")!)
try await transport.connect()
try await EchoWorker().run(transport: transport)
```

The checked-in example uses `InMemoryTransport` so it can run without NATS
while still exercising the transport loop:

```bash
swift run --package-path examples/swift/echo-worker EchoWorker
```

## Swift concurrency notes

- Payload and output types should be `Sendable`.
- `HeddleWorker` is an open class and marked `@unchecked Sendable` because
  subclasses define their own state. Keep subclasses stateless between tasks.
- Override `reset()` to clear temporary resources after each task.
- Override `malformedMessage(_:)` to log malformed input without crashing the
  subscription loop.
- `InMemoryTransport` is process-local. Use a shared broker transport for a
  native worker that needs to talk to a running Heddle or Workshop process.
- `HeddleActorNATS` depends on the official `nats-io/nats.swift` package and
  stays separate from the core Swift package.
