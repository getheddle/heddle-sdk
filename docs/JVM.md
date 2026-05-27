# JVM SDK

The JVM SDK provides Kotlin-first, Java-friendly support for Heddle processor
workers. It includes the `heddle-sdk-core` and `heddle-sdk-nats` packages.

## Add the package

The SDK is built with Gradle. For a local checkout, add the project to your
`settings.gradle.kts`:

```kotlin
includeBuild("../../heddle-sdk/jvm")
```

And add the dependency to your `build.gradle.kts`:

```kotlin
dependencies {
    implementation("heddle:core:0.1.0") // core models and worker base
    implementation("heddle:nats:0.1.0") // NATS transport adapter
}
```

## Define payload and output models

### Kotlin

```kotlin
data class EchoPayload(val message: String)
data class EchoOutput(val response: String)
```

### Java

```java
public class EchoPayload {
    public String message;
}

public class EchoOutput {
    public String response;
    public EchoOutput(String response) { this.response = response; }
}
```

## Implement a worker

### Kotlin

```kotlin
class KotlinEchoWorker(transport: HeddleTransport) : HeddleWorker<EchoPayload, EchoOutput>(
    workerType = "echo",
    payloadClass = EchoPayload::class.java,
    outputClass = EchoOutput::class.java,
    transport = transport
) {
    override suspend fun process(payload: EchoPayload, metadata: Map<String, Any?>): WorkerOutput<EchoOutput> {
        return WorkerOutput(EchoOutput("Echo: ${payload.message}"))
    }
}
```

### Java

```java
public class JavaEchoWorker extends HeddleWorker<EchoPayload, EchoOutput> {
    public JavaEchoWorker(HeddleTransport transport) {
        super("echo", ModelTier.STANDARD, EchoPayload.class, EchoOutput.class, transport);
    }

    @Override
    public Object process(EchoPayload payload, Map<String, ?> metadata, Continuation<? super WorkerOutput<EchoOutput>> $completion) {
        return new WorkerOutput<>(new EchoOutput("Echo: " + payload.message));
    }
}
```

## Run with a transport

The core SDK defines the `HeddleTransport` interface. You can use the
in-memory transport for tests or the NATS transport for live interop.

### Kotlin (Coroutines)

```kotlin
fun main() = runBlocking {
    val transport = NatsHeddleTransport.connect("nats://localhost:4222")
    val worker = KotlinEchoWorker(transport)
    worker.run()
}
```

### Java (runBlocking bridge)

```java
public static void main(String[] args) {
    NatsHeddleTransport transport = NatsHeddleTransport.Companion.connect("nats://localhost:4222");
    JavaEchoWorker worker = new JavaEchoWorker(transport);
    
    BuildersKt.runBlocking(GlobalScope.INSTANCE.getCoroutineContext(), (scope, continuation) -> {
        return worker.run(continuation);
    });
}
```

## JVM notes

- **Kotlin-first:** The SDK is authored in Kotlin to leverage null-safety and
  coroutines, but APIs are designed to be idiomatic for Java.
- **Serialization:** Uses Jackson for JSON serialization, matching Heddle's
  snake_case wire conventions.
- **Enums:** Handled via Jackson's standard enum mapping; unknown enum values
  should be handled gracefully by the application or a custom validator.
- **Transport:** The NATS adapter uses the official `nats-io/jnats` client.
- **Android:** The core SDK is compatible with Android. If Android-specific
  transport constraints arise, use a specialized transport adapter.
