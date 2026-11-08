#!/usr/bin/env bash
# Live interop check: a real NATS server (Docker), heddle's router, and the
# .NET, Swift and JVM echo workers from this repo. A Python driver sends framed
# tasks through the router and checks every result with heddle's own wire
# decoder and parse(). See tools/live_check/README.md.
#
# Usage: tools/live_check/run.sh          (from anywhere)
# Env:   HEDDLE_REPO   heddle checkout       (default: ../heddle next to this repo)
#        NATS_IMAGE    NATS image            (default: nats:2.10.22)
#        NATS_PORT     client port on host   (default: 4222)
#        NATS_MON_PORT monitoring port       (default: 8222)
#        KEEP_LOGS=1   print every log at the end, even on success
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HEDDLE_REPO="$(cd "${HEDDLE_REPO:-$ROOT/../heddle}" && pwd)"
NATS_IMAGE="${NATS_IMAGE:-nats:2.10.22}"
NATS_PORT="${NATS_PORT:-4222}"
NATS_MON_PORT="${NATS_MON_PORT:-8222}"
export NATS_URL="nats://localhost:$NATS_PORT"
CONTAINER="heddle-sdk-live-check-$$"
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/heddle-live-check.XXXXXX")"
PIDS=()

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'live_check: %s\n' "$*" >&2; exit 2; }

cleanup() {
    local status=$?
    for pid in "${PIDS[@]:-}"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    # Gradle's JavaExec child outlives its parent; stop it by main class.
    pkill -f "heddle.examples.KotlinEchoWorkerKt" 2>/dev/null || true
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    if [ "$status" -ne 0 ] || [ "${KEEP_LOGS:-0}" = 1 ]; then
        for f in "$LOGS"/*.log; do
            [ -e "$f" ] || continue
            printf '\n----- %s -----\n' "$(basename "$f")"
            tail -n 40 "$f"
        done
    fi
    printf '\nlogs: %s\n' "$LOGS"
    exit "$status"
}
trap cleanup EXIT INT TERM

# --- Prerequisites ----------------------------------------------------------
for tool in docker dotnet swift uv curl python3; do
    command -v "$tool" >/dev/null || die "missing prerequisite: $tool"
done
[ -f "$HEDDLE_REPO/configs/router_rules.yaml" ] || die "no heddle checkout at $HEDDLE_REPO (set HEDDLE_REPO)"
docker info >/dev/null 2>&1 || die "docker daemon is not reachable (start Docker / OrbStack)"
if [ -z "${JAVA_HOME:-}" ]; then
    command -v java >/dev/null || die "missing prerequisite: java (JDK 17 or 21; set JAVA_HOME)"
fi
java_major="$("${JAVA_HOME:+$JAVA_HOME/bin/}java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)"
case "$java_major" in
    17|21) ;;
    *) die "JDK $java_major found; Gradle 8.11 with Kotlin 2.0 needs JDK 17 or 21 (set JAVA_HOME)" ;;
esac
# The .NET projects target net8.0; allow a newer installed runtime.
export DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-Major}"

# --- Build ------------------------------------------------------------------
say "Building the .NET and Swift echo workers and the JVM example"
dotnet build "$HERE/dotnet-echo/LiveEcho.csproj" -c Release >"$LOGS/build-dotnet.log" 2>&1
swift build --package-path "$HERE/swift-echo" >"$LOGS/build-swift.log" 2>&1
"$ROOT/jvm/gradlew" -p "$ROOT/jvm" :examples:classes -q >"$LOGS/build-jvm.log" 2>&1
# --frozen: use heddle's lock as is; uv run installs only what is missing and
# never removes the extras of an existing heddle environment.
(cd "$HEDDLE_REPO" && uv run --frozen python -c "import heddle.bootstrap" >"$LOGS/build-heddle.log" 2>&1)

# --- NATS -------------------------------------------------------------------
say "Starting $NATS_IMAGE on :$NATS_PORT"
docker run -d --name "$CONTAINER" -p "$NATS_PORT:4222" -p "$NATS_MON_PORT:8222" \
    "$NATS_IMAGE" -m 8222 >/dev/null
for _ in $(seq 1 30); do
    curl -sf "http://localhost:$NATS_MON_PORT/varz" >/dev/null && break
    sleep 1
done
curl -sf "http://localhost:$NATS_MON_PORT/varz" >/dev/null || die "NATS did not start"

# --- Router and workers -----------------------------------------------------
say "Starting the heddle router and the three workers"
(cd "$HEDDLE_REPO" && exec uv run --frozen heddle router --config configs/router_rules.yaml \
    --nats-url "$NATS_URL" --skip-preflight) >"$LOGS/router.log" 2>&1 &
PIDS+=($!)
dotnet "$HERE/dotnet-echo/bin/Release/net8.0/LiveEcho.dll" >"$LOGS/dotnet.log" 2>&1 &
PIDS+=($!)
"$HERE/swift-echo/.build/debug/LiveEcho" >"$LOGS/swift.log" 2>&1 &
PIDS+=($!)
"$ROOT/jvm/gradlew" -p "$ROOT/jvm" :examples:runKotlinEcho -q >"$LOGS/kotlin.log" 2>&1 &
PIDS+=($!)

# Wait until the router and all three workers have subscribed.
want="heddle.tasks.incoming heddle.tasks.echo-dotnet.local heddle.tasks.echo-swift.local heddle.tasks.echo-kotlin.standard"
for _ in $(seq 1 90); do
    have="$(curl -s "http://localhost:$NATS_MON_PORT/subsz?subs=1" | python3 -c \
        'import json,sys; print(" ".join(s["subject"] for s in json.load(sys.stdin).get("subscriptions_list", [])))')"
    missing=""
    for s in $want; do
        case " $have " in *" $s "*) ;; *) missing="$missing $s" ;; esac
    done
    [ -z "$missing" ] && break
    sleep 2
done
[ -z "$missing" ] || die "not subscribed after 180s:$missing"
# Each subject must have exactly one subscriber: a stray worker from another
# run would share the queue group and answer some of the tasks.
dupes="$(curl -s "http://localhost:$NATS_MON_PORT/subsz?subs=1" | python3 -c     'import collections,json,sys; c=collections.Counter(s["subject"] for s in json.load(sys.stdin).get("subscriptions_list", []) if s["subject"].startswith("heddle.tasks.")); print(" ".join(k for k, n in c.items() if n > 1))')"
[ -z "$dupes" ] || die "more than one subscriber on: $dupes (stop other heddle workers first)"

# --- Drive ------------------------------------------------------------------
say "Running the driver"
(cd "$HEDDLE_REPO" && uv run --frozen python "$HERE/driver.py")
