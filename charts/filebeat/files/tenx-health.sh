#!/bin/sh
#
# 10x forwarder health check. Shared by the liveness and the readiness probe;
# the caller passes "liveness" or "readiness" as $1.
#
# WHY THIS EXISTS
#
# The container runs two processes joined by one pipe:
#
#   exec filebeat "$@" 2>&1 | tenx-edge run ...
#
# Every earlier version of these probes tested only the left-hand side, so a
# container whose engine had died still answered 127.0.0.1:5066 and still passed
# 'filebeat test output'. Measured three seconds after 'kill -9' on the engine:
# container running, liveness 200, readiness OK, kubectl 1/1 Ready, zero
# restarts, and the node shipping nothing through 10x. The container only fell
# over ~29 seconds later, when Filebeat's 30s metrics write hit the broken pipe.
#
# WHAT IT CATCHES
#
#   B1/B2  engine gone, idle or with output configured  -> the pgrep test
#   B3     engine frozen but still in the process table  -> the state test for a
#          stopped process, and the CPU test for one that is scheduled but has
#          quietly stopped doing anything
#
# The CPU test is what makes this more than a liveness theatre. An idle node is
# a healthy node, so nothing here keys off EVENT flow: the engine accumulates
# CPU on its own timers whatever the traffic. Measured on an idle 1.1.38
# container, cumulative CPU advanced 33 ticks over 151 seconds, and the longest
# stretch with no advance at all was 20 seconds, so the default 60 second stall
# window sits at three times the observed worst case.
#
set -u

MODE="${1:-liveness}"

STALL_SECONDS="${TENX_PROBE_STALL_SECONDS:-60}"
STATE_FILE="${TENX_PROBE_STATE_FILE:-/tmp/tenx-probe-${MODE}.state}"
STATS_URL="${TENX_PROBE_FILEBEAT_URL:-127.0.0.1:5066}"
CURL_TIMEOUT="${TENX_PROBE_CURL_TIMEOUT:-3}"

fail() {
    echo "tenx-${MODE}: FAIL: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Filebeat. Same test as before, kept so nothing regresses.
# ---------------------------------------------------------------------------
case "$MODE" in
    liveness)
        curl --fail --silent --max-time "$CURL_TIMEOUT" "$STATS_URL" >/dev/null \
            || fail "filebeat stats endpoint $STATS_URL did not answer"
        ;;
    readiness)
        # 'filebeat test output' is the right test for elasticsearch, logstash
        # and kafka, and it is the default. It cannot test output.file, which
        # answers "file output doesn't support testing" and exits 1, so those
        # deployments select the http test instead.
        case "${TENX_PROBE_FILEBEAT_TEST:-output}" in
            output)
                filebeat test output >/dev/null 2>&1 \
                    || fail "filebeat test output failed"
                ;;
            http)
                curl --fail --silent --max-time "$CURL_TIMEOUT" "$STATS_URL" >/dev/null \
                    || fail "filebeat stats endpoint $STATS_URL did not answer"
                ;;
            none)
                : ;;
            *)
                fail "TENX_PROBE_FILEBEAT_TEST is '${TENX_PROBE_FILEBEAT_TEST}', expected output, http or none"
                ;;
        esac
        ;;
    *)
        fail "unknown mode '$MODE' (expected liveness or readiness)"
        ;;
esac

# With 10x switched off the container is only Filebeat, so that is the whole
# check.
[ "${TENX_ENABLED:-false}" = "true" ] || exit 0

# ---------------------------------------------------------------------------
# 2. The engine has to be in the process table.
#
# Matched on comm with -x, never on the command line with -f: this script's own
# shell has "tenx-edge" in its arguments, so pgrep -f would match the probe
# itself and report a dead engine as alive.
# ---------------------------------------------------------------------------
ENGINE_PID="$(pgrep -x tenx-edge 2>/dev/null | head -1)"
[ -n "$ENGINE_PID" ] || fail "no tenx-edge process: the engine exited and only filebeat is left"

STAT_FILE="/proc/${ENGINE_PID}/stat"
[ -r "$STAT_FILE" ] || fail "engine pid $ENGINE_PID vanished while being checked"

# Everything after the comm field, which is parenthesised and is the only field
# that can contain spaces. State becomes $1, utime $12, stime $13.
STAT_TAIL="$(sed 's/^.*) //' "$STAT_FILE" 2>/dev/null)"
[ -n "$STAT_TAIL" ] || fail "could not read $STAT_FILE"

# ---------------------------------------------------------------------------
# 3. Scheduler state. T and t are a SIGSTOPped or traced engine, Z and X a
#    corpse nobody reaped. All of them keep the pid in the table, which is
#    exactly the case pgrep alone cannot see.
# ---------------------------------------------------------------------------
ENGINE_STATE="$(echo "$STAT_TAIL" | awk '{print $1}')"
case "$ENGINE_STATE" in
    T|t)  fail "engine pid $ENGINE_PID is stopped (state '$ENGINE_STATE'): frozen, not running" ;;
    Z|X)  fail "engine pid $ENGINE_PID is a corpse (state '$ENGINE_STATE')" ;;
esac

# ---------------------------------------------------------------------------
# 4. The two ends are still the same pipe. Filebeat's stdout inode has to be the
#    engine's stdin inode, otherwise the engine is running but reading nothing
#    this container produces.
# ---------------------------------------------------------------------------
FILEBEAT_PID="$(pgrep -x filebeat 2>/dev/null | head -1)"
if [ -n "$FILEBEAT_PID" ]; then
    FB_STDOUT="$(readlink "/proc/${FILEBEAT_PID}/fd/1" 2>/dev/null || true)"
    ENGINE_STDIN="$(readlink "/proc/${ENGINE_PID}/fd/0" 2>/dev/null || true)"
    if [ -n "$FB_STDOUT" ] && [ -n "$ENGINE_STDIN" ] && [ "$FB_STDOUT" != "$ENGINE_STDIN" ]; then
        fail "pipe broken: filebeat stdout is $FB_STDOUT, engine stdin is $ENGINE_STDIN"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Forward progress. Cumulative CPU across all engine threads has to move at
#    least once every STALL_SECONDS. A frozen or deadlocked engine burns none.
#
#    The pid is part of the stored key, so a restarted engine resets the window
#    instead of inheriting the dead one's stall.
# ---------------------------------------------------------------------------
UTIME="$(echo "$STAT_TAIL" | awk '{print $12}')"
STIME="$(echo "$STAT_TAIL" | awk '{print $13}')"
case "${UTIME}${STIME}" in
    ''|*[!0-9]*) fail "could not parse cpu times out of $STAT_FILE" ;;
esac
CPU_TICKS=$(( UTIME + STIME ))
NOW="$(date +%s)"
KEY="${ENGINE_PID}:${CPU_TICKS}"

PREV_KEY=""
PREV_TS=""
if [ -r "$STATE_FILE" ]; then
    read -r PREV_KEY PREV_TS < "$STATE_FILE" 2>/dev/null || true
fi

case "$PREV_TS" in
    ''|*[!0-9]*) PREV_KEY="" ;;
esac

if [ "$KEY" = "$PREV_KEY" ]; then
    STALLED_FOR=$(( NOW - PREV_TS ))
    if [ "$STALLED_FOR" -ge "$STALL_SECONDS" ]; then
        fail "engine pid $ENGINE_PID burned no cpu for ${STALLED_FOR}s (limit ${STALL_SECONDS}s): frozen or deadlocked"
    fi
else
    echo "$KEY $NOW" > "$STATE_FILE" 2>/dev/null || true
fi

exit 0
