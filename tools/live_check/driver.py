"""Live interop check: heddle router + .NET/Swift/JVM echo workers over NATS.

Run by tools/live_check/run.sh inside the sibling heddle checkout's
environment (Provide a command or script to invoke with `uv run <command>` or `uv run <script>.py`.

The following commands are available in the environment:

- accelerate
- accelerate-config
- accelerate-estimate-memory
- accelerate-launch
- accelerate-merge-weights
- cffi-gen-src
- coverage
- coverage-3.12
- coverage3
- cyclopts
- deepeval
- distro
- doclang
- docling
- docling-serialize
- docling-tools
- docling-view
- dotenv
- email_validator
- f2py
- faker
- fastapi
- fastmcp
- filetype
- get_gprof
- get_objgraph
- ghp-import
- heddle
- hf
- httpx
- httpx2
- huggingface-cli
- idna
- isympy
- jsonschema
- l2m
- latex2mathml
- latex2text
- latexencode
- latexwalker
- mail-parser
- markdown-it
- markdown_py
- marko
- mcp
- mkdocs
- mkdocs-get-deps
- mpire-dashboard
- normalizer
- numpy-config
- oxmsg
- py.test
- pybabel
- pyfiglet
- pygmentize
- pygrun
- pypdfium2
- pyrsa-decrypt
- pyrsa-encrypt
- pyrsa-keygen
- pyrsa-priv2pub
- pyrsa-sign
- pyrsa-verify
- pytest
- python
- python3
- python3.12
- rapidocr
- ruff
- tabulate
- tiny-agents
- torchfrtrace
- torchrun
- tqdm
- transformers
- typer
- undill
- uvicorn
- vba_extract.py
- watchfiles
- watchmedo
- websockets
- wheel

See `uv run --help` for more information.). Uses heddle's own wrap(), strict
wire decoder and parse() as the oracle. Exits non-zero on any failed check.
"""
import asyncio, json, os, sys
import nats
import heddle.bootstrap  # noqa: F401  registers payload types
from heddle.core.envelope import parse, wrap, middleware_lane
from heddle.core.messages import TaskMessage, TaskResult, ModelTier
from heddle.core.wire_json import loads

WORKERS = [
    ("echo-dotnet", ModelTier.LOCAL, {"text": "hello from python"}, {"text": "HELLO FROM PYTHON", "lang": "dotnet"}),
    ("echo-swift", ModelTier.LOCAL, {"text": "hello from python"}, {"text": "HELLO FROM PYTHON", "lang": "swift"}),
    ("echo-kotlin", ModelTier.STANDARD, {"message": "hello from python"}, {"response": "Kotlin Echo: hello from python"}),
]
failures: list[str] = []

def check(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        failures.append(msg)

async def main():
    nc = await nats.connect(os.environ.get("NATS_URL", "nats://localhost:4222"))
    for wt, tier, inp, want in WORKERS:
        print(f"== {wt}")
        parent = f"live-{wt}"
        inbox: asyncio.Queue = asyncio.Queue()
        async def on_result(m, q=inbox):
            q.put_nowait(m.data)
        sub = await nc.subscribe(f"heddle.results.{parent}", cb=on_result)
        lane = {"_trace_context": {"traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
                "_x_live": {"lang": wt, "n": [1, 2.5, None, "é"]}}
        task = TaskMessage(worker_type=wt, input=inp, model_tier=tier, parent_task_id=parent, metadata={"k": "v"})
        frame = wrap("core.TaskMessage", task, origin="live-check", correlation_id="corr-" + wt, **lane)
        sent = frame.model_dump(mode="json")
        # 1. Normal task through the router.
        await nc.publish("heddle.tasks.incoming", json.dumps(sent).encode())
        raw = await asyncio.wait_for(inbox.get(), 30)
        env, body = parse(loads(raw))
        check(isinstance(body, TaskResult) and env.payload_type == "core.TaskResult", "result is a framed core.TaskResult (strict decode + parse)")
        check(body.status.value == "completed", f"status completed (got {body.status.value}, error={body.error})")
        check(body.task_id == task.task_id and body.parent_task_id == parent, "task_id / parent_task_id echoed")
        check(body.worker_type == wt, f"worker_type echoed ({body.worker_type})")
        check(body.output == want, f"output {body.output}")
        check(set(body.token_usage) == {"prompt_tokens", "completion_tokens"}, "token_usage has exactly two keys")
        check(middleware_lane(env) == lane, "Middleware Lane survived router + worker unchanged")
        check(env.message_id != frame.message_id, "result has a fresh message_id")
        check(env.origin is None and env.correlation_id is None, "result frame sets no origin/correlation (as upstream)")
        # 2. Malformed messages straight to the worker subject, then a good one.
        subject = f"heddle.tasks.{wt}.{tier.value}"
        good = dict(sent, message_id=sent["message_id"][:-4] + "beef")
        bad_dup = json.dumps(sent)[:-1] + ', "payload_type": "events.Event"}'
        bad_nan = json.dumps(sent).replace('"payload": {', '"payload": {"x": NaN, ', 1)
        bad_type = json.dumps(dict(sent, payload_type="core.TaskResult"))
        for b in (bad_dup, bad_nan, bad_type):
            await nc.publish(subject, b.encode())
        await nc.publish(subject, json.dumps(good).encode())
        raw2 = await asyncio.wait_for(inbox.get(), 30)
        env2, body2 = parse(loads(raw2))
        check(body2.status.value == "completed", "worker skipped 3 malformed messages and handled the next task")
        await asyncio.sleep(1.0)
        check(inbox.empty(), "no result was published for the malformed messages")
        await sub.unsubscribe()
    await nc.drain()
    print("\nRESULT:", "PASS" if not failures else f"FAIL ({len(failures)})")
    sys.exit(1 if failures else 0)

asyncio.run(main())
