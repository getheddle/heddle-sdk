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

A NATS adapter can implement that protocol without changing worker code:

```swift
try await EchoWorker().run(transport: natsTransport)
```

The checked-in example calls `handle(_:)` directly so it can run without NATS:

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
