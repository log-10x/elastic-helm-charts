#!/bin/sh
#
# 10x sidecar health check for the Logstash chart. Shared by the startup, the
# readiness and the liveness probe; the caller passes the mode as $1.
#
# WHY THIS EXISTS
#
# The tenx container carried no probe of any kind, so the kubelet marked it
# Ready the instant the process image was created and never looked again.
# Measured on this chart at 1.1.39: an install whose licence was the literal
# string "not-a-jwt" reported the tenx container ready=true, restarts=0, with
# no engine output at all, for as long as it was watched. Chart CI cannot fail
# on an engine that never starts.
#
# WHAT THE CONTAINER LOOKS LIKE
#
# With tenx.waitForLogstash on, the container command is a shell that polls
# /dev/tcp for Logstash's return port and then execs the engine over itself.
# So pid 1 is bash first and the engine binary after, and there is no second
# process to find: no pgrep, no ps, and nothing else in the image to run them.
# Everything here reads /proc/1 and /proc/net directly.
#
# That shape also decides what a probe is FOR. An engine that dies is pid 1
# dying, which ends the container and the kubelet restarts it with no help from
# us. The two states nothing catches are:
#
#   1. the wait. pid 1 is still the poll shell, the engine has not been
#      launched, and today the container is Ready. This is not a fault during a
#      normal start, which is why it fails the startup and readiness probes and
#      never the liveness probe: the container is fine, its peer is not up yet.
#
#   2. the freeze. The engine is pid 1, it is in the process table, and it is
#      doing nothing: SIGSTOPped, traced, or deadlocked. The container stays
#      Running with zero restarts forever.
#
# WHAT IS TESTED, AND WHY EACH TEST CAN FAIL
#
#   A. pid 1 is the engine, not the wait shell. Compared by resolving
#      /proc/1/exe, which is what the kernel recorded at execve. The first
#      version of this probe matched pid 1's command line against '*tenx*' and
#      was worthless: the poll shell's own command line contains "$TENX_BIN",
#      so the pattern matched before the engine had been launched at all.
#
#   B. The engine is listening on tenx.inputPort, and the listening socket is
#      one of pid 1's own file descriptors. This is the test that observes the
#      ENGINE rather than the process: readStream(stream:logstash) binds that
#      port at the end of pipeline construction, after the licence has been
#      verified, so an engine that cannot licence itself, cannot load its
#      config, or is still building never passes it. The inode has to belong to
#      pid 1 because Logstash shares this network namespace, and a check that
#      only asked "is something listening" would pass on the wrong process.
#
#   C. Scheduler state. T and t are stopped or traced, Z and X a corpse nobody
#      reaped. All of them keep pid 1 in the table.
#
#   D. Forward progress. Cumulative CPU over all engine threads has to advance
#      at least once every stallSeconds. Nothing keys off EVENT flow, because an
#      idle Logstash is a healthy Logstash; the engine burns CPU on its own
#      timers whatever the traffic.
#
set -u

MODE="${1:-liveness}"

INPUT_PORT="${TENX_PROBE_INPUT_PORT:-5046}"
STALL_SECONDS="${TENX_PROBE_STALL_SECONDS:-60}"
STATE_FILE="${TENX_PROBE_STATE_FILE:-/tmp/tenx-probe-${MODE}.state}"
ENGINE_BIN="${TENX_BIN:-/opt/tenx-cloud/bin/tenx-cloud}"

case "$MODE" in
    startup|readiness|liveness) : ;;
    *) echo "tenx-probe: FAIL: unknown mode '$MODE' (expected startup, readiness or liveness)" >&2; exit 1 ;;
esac

fail() {
    echo "tenx-${MODE}: FAIL: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# A. Is pid 1 the engine yet?
#
# /proc/1/exe is the file execve actually mapped. While the wait loop runs it
# resolves to the shell; after the exec it resolves to the engine. Command
# lines are not used: the wait shell's arguments mention the engine binary.
#
# The engine may be a wrapper script, in which case /proc/1/exe is the
# interpreter, so a match on comm against the basename is accepted too.
# ---------------------------------------------------------------------------
PID1_EXE="$(readlink /proc/1/exe 2>/dev/null || true)"
PID1_COMM="$(cat /proc/1/comm 2>/dev/null || true)"
ENGINE_BASE="${ENGINE_BIN##*/}"

engine_is_pid1=false
if [ -n "$PID1_EXE" ] && [ "$PID1_EXE" = "$ENGINE_BIN" ]; then
    engine_is_pid1=true
elif [ -n "$PID1_COMM" ] && [ "$PID1_COMM" = "$ENGINE_BASE" ]; then
    engine_is_pid1=true
elif [ -n "$PID1_COMM" ] && [ "${ENGINE_BASE#"$PID1_COMM"}" != "$ENGINE_BASE" ] && [ ${#PID1_COMM} -ge 15 ]; then
    # comm is truncated to 15 characters by the kernel.
    engine_is_pid1=true
fi

if [ "$engine_is_pid1" != true ]; then
    if [ "$MODE" = liveness ]; then
        # Waiting for Logstash to bind is a normal start, not a fault. Killing
        # the container here would only restart the same wait.
        exit 0
    fi
    fail "the engine has not been launched: pid 1 is still '${PID1_COMM:-unknown}' (${PID1_EXE:-no exe}), waiting for the Logstash tcp input"
fi

# ---------------------------------------------------------------------------
# C. Scheduler state, read before anything else that takes time.
#
# Everything after the comm field, which is parenthesised and is the only field
# that can hold spaces. State becomes $1, utime $12, stime $13.
# ---------------------------------------------------------------------------
STAT_TAIL="$(sed 's/^.*) //' /proc/1/stat 2>/dev/null || true)"
[ -n "$STAT_TAIL" ] || fail "could not read /proc/1/stat"

ENGINE_STATE="$(echo "$STAT_TAIL" | awk '{print $1}')"
case "$ENGINE_STATE" in
    T|t) fail "engine is stopped (state '$ENGINE_STATE'): frozen, not running" ;;
    Z|X) fail "engine is a corpse (state '$ENGINE_STATE')" ;;
esac

# ---------------------------------------------------------------------------
# B. The engine's own listening socket on the ingest port.
# ---------------------------------------------------------------------------
case "$INPUT_PORT" in
    '' |*[!0-9]*) fail "TENX_PROBE_INPUT_PORT is '${INPUT_PORT}', which is not a port number" ;;
esac
PORT_HEX="$(printf '%04X' "$INPUT_PORT")"

# State 0A is TCP_LISTEN. Field 2 is local_address as HEX_IP:HEX_PORT, field 10
# the socket inode. tcp6 carries the v4-mapped listener on a dual-stack image.
LISTEN_INODES="$(awk -v suffix=":$PORT_HEX" '
    $4 == "0A" && substr($2, length($2) - length(suffix) + 1) == suffix { print $10 }
' /proc/net/tcp /proc/net/tcp6 2>/dev/null || true)"

[ -n "$LISTEN_INODES" ] || fail "nothing is listening on ${INPUT_PORT}: the engine is running but has not built its Logstash read stream (an unlicensed or misconfigured engine never gets this far)"

owned=false
for inode in $LISTEN_INODES; do
    for fd in /proc/1/fd/*; do
        [ -e "$fd" ] || continue
        if [ "$(readlink "$fd" 2>/dev/null)" = "socket:[$inode]" ]; then
            owned=true
            break 2
        fi
    done
done
[ "$owned" = true ] || fail "port ${INPUT_PORT} is listening but the socket does not belong to the engine: Logstash and the sidecar share a network namespace, so this is some other process holding the port"

# The startup probe's job ends here: the engine is up and accepting. Stall
# accounting starts once the container has been declared started, so the
# pipeline build does not count as a stall.
[ "$MODE" != startup ] || exit 0

# ---------------------------------------------------------------------------
# D. Forward progress.
# ---------------------------------------------------------------------------
UTIME="$(echo "$STAT_TAIL" | awk '{print $12}')"
STIME="$(echo "$STAT_TAIL" | awk '{print $13}')"
case "${UTIME}${STIME}" in
    '' |*[!0-9]*) fail "could not parse cpu times out of /proc/1/stat" ;;
esac

CPU_TICKS=$(( UTIME + STIME ))
NOW="$(date +%s)"

PREV_TICKS=""
PREV_TS=""
if [ -r "$STATE_FILE" ]; then
    read -r PREV_TICKS PREV_TS < "$STATE_FILE" 2>/dev/null || true
fi
case "${PREV_TICKS}:${PREV_TS}" in
    *[!0-9:]*|:*|*:) PREV_TICKS="" ;;
esac

if [ -n "$PREV_TICKS" ] && [ "$CPU_TICKS" = "$PREV_TICKS" ]; then
    STALLED_FOR=$(( NOW - PREV_TS ))
    if [ "$STALLED_FOR" -ge "$STALL_SECONDS" ]; then
        fail "engine burned no cpu for ${STALLED_FOR}s (limit ${STALL_SECONDS}s): frozen or deadlocked"
    fi
else
    echo "$CPU_TICKS $NOW" > "$STATE_FILE" 2>/dev/null || true
fi

exit 0
