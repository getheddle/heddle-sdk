# Live interop check

`run.sh` checks the three SDKs against a real heddle deployment: a NATS server
in Docker, heddle's own router, and an echo worker per language. The fixture
tests already prove each codec in isolation. This check proves the actual
transports, subjects, queue groups and router hop.

```bash
tools/live_check/run.sh
```

It exits 0 when every check passes and non-zero otherwise. On failure, and
with `KEEP_LOGS=1`, it prints the tail of every log. The container and all
processes are removed on exit, even after a failure or Ctrl-C.

## What it does

1. Builds `dotnet-echo/` and `swift-echo/` (live-check workers, not examples)
   and the JVM examples.
2. Starts NATS (`nats:2.10.22` by default) in Docker with monitoring on.
3. Starts `heddle router` from a heddle checkout, then the workers. Each
   subscribes with its `processors-{worker_type}` queue group:

   | Worker | Subject |
   |---|---|
   | .NET (`dotnet-echo/`) | `heddle.tasks.echo-dotnet.local` |
   | Swift (`swift-echo/`) | `heddle.tasks.echo-swift.local` |
   | JVM (`jvm/examples` `KotlinEchoWorker`) | `heddle.tasks.echo-kotlin.standard` |

4. Waits until the router and all three workers have subscribed, and fails if
   any subject has a second subscriber, such as a worker left over from
   another run.
5. Runs `driver.py` in heddle's environment. For each worker it:
   - Frames a `TaskMessage` with heddle's `wrap()`, adding two Middleware-Lane
     keys (`_trace_context` and `_x_live`), and publishes it to
     `heddle.tasks.incoming` so the router forwards it.
   - Decodes the result with `heddle.core.wire_json.loads` and checks it with
     `parse()`:
     - The payload type is `core.TaskResult` and the status is `completed`.
     - `task_id`, `parent_task_id` and `worker_type` are echoed.
     - The output is right, and `token_usage` has exactly two keys.
     - Both lane keys are unchanged, and the frame has a fresh `message_id`.
   - Publishes three malformed messages straight to the worker: a repeated
     `payload_type`, a `NaN`, and the wrong `payload_type`. Then it publishes a
     good task, and checks that only the good one gets a result.

## Requirements

- Docker (Docker Desktop, OrbStack or similar), with ports 4222 and 8222 free.
- A heddle checkout, by default `../heddle` next to this repo, and
  [uv](https://docs.astral.sh/uv/). The script runs `uv run --frozen` in it,
  which uses heddle's lock and only adds missing packages to an existing
  environment.
- .NET SDK 8 or newer. A newer runtime is used through
  `DOTNET_ROLL_FORWARD=Major`.
- Swift 6.
- JDK 17 or 21, as `JAVA_HOME` or on `PATH`. Gradle 8.11 with Kotlin 2.0
  does not run on newer JDKs.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `HEDDLE_REPO` | `../heddle` | heddle checkout to run the router and driver from |
| `NATS_IMAGE` | `nats:2.10.22` | NATS image |
| `NATS_PORT` / `NATS_MON_PORT` | `4222` / `8222` | Host ports |
| `KEEP_LOGS` | unset | `1` prints all logs even on success |

`NATS_URL` is set from `NATS_PORT` and read by all three workers and the
driver.

This check needs a heddle checkout and Docker, so it is not part of CI. Run it
before a release, and after any change to a transport, a worker base or the
wire codecs.
