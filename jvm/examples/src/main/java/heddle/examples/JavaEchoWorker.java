package heddle.examples;

import heddle.sdk.*;
import heddle.sdk.nats.NatsHeddleTransport;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.GlobalScope;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.Map;

/**
 * A simple Echo worker implemented in Java.
 *
 * Demonstrates how the Kotlin-authored SDK can be consumed from Java
 * using standard Java patterns.
 */
public class JavaEchoWorker extends HeddleWorker<JavaEchoWorker.Payload, JavaEchoWorker.Output> {

    public static class Payload {
        public String message;
    }

    public static class Output {
        public String response;
        public Output(String response) { this.response = response; }
    }

    public JavaEchoWorker(HeddleTransport transport) {
        super("echo-java", ModelTier.STANDARD, Payload.class, Output.class, transport);
    }

    @Nullable
    @Override
    public Object process(@NotNull Payload payload, @NotNull Map<String, ?> metadata, @NotNull kotlin.coroutines.Continuation<? super WorkerOutput<Output>> $completion) {
        // While the worker base uses 'suspend' (which compiles to a Continuation parameter in Java),
        // Java callers can use BuildersKt.withContext or similar bridges if they want to call suspend functions.
        // For a simple worker implementation, we can just return the value directly.
        
        System.out.println("Java worker received: " + payload.message);
        return new WorkerOutput<>(new Output("Java Echo: " + payload.message), null, null, null);
    }

    public static void main(String[] args) throws InterruptedException {
        NatsHeddleTransport transport = NatsHeddleTransport.Companion.connect("nats://localhost:4222");
        JavaEchoWorker worker = new JavaEchoWorker(transport);
        
        // Use runBlocking to start the coroutine loop from Java
        BuildersKt.runBlocking(GlobalScope.INSTANCE.getCoroutineContext(), (scope, continuation) -> {
            return worker.run(continuation);
        });
    }
}
