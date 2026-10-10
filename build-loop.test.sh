#!/bin/bash
# Tests for build-loop.sh's rolling debounce.
#
#   bash build-loop.test.sh
#
# Sources build-loop.sh with BUILD_LOOP_TEST=1 — which loads the definitions and
# returns before the runtime — then calls await_quiet() against a throwaway
# content tree with scaled-down constants. It exercises the REAL function on
# purpose: a copy of the loop pasted in here would pass forever after the real
# one changed.
#
# What it defends, and why each one exists:
#
#  1. A lone post still waits only DEBOUNCE_SECONDS. This is the property that
#     made rolling worth doing — a FIXED delay long enough to merge a burst would
#     tax every single post, which is the trade-off rolling removes.
#  2. A trickle extends the window. This is the behaviour being added; it fails
#     against the old `sleep "$DEBOUNCE_SECONDS"`.
#  3. Continuous activity is cut off by MAX_DEBOUNCE_SECONDS. Without the cap,
#     posting steadily would defer the build indefinitely.
#  4. A deletion counts as activity. Unpublishing makes no surviving file newer;
#     only the parent directory's mtime moves, which is why
#     content_activity_stamp() must not filter to -type f.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
BUILD_LOOP_TEST=1 . "$HERE/build-loop.sh"

# Scaled down so the suite runs in ~30s instead of ~10min.
DEBOUNCE_SECONDS=3
DEBOUNCE_TICK=1
MAX_DEBOUNCE_SECONDS=8

CONTENT_DIR=$(mktemp -d)
mkdir -p "$CONTENT_DIR/_data" "$CONTENT_DIR/notes"
touch "$CONTENT_DIR/notes/seed.md"

fail=0
pass() { echo "  PASS  $1"; }
flunk() { echo "  FAIL  $1"; fail=1; }

echo "=== 1. a lone change waits exactly the quiet window (${DEBOUNCE_SECONDS}s) ==="
w=$(await_quiet | tail -1)
[ "$w" = "$DEBOUNCE_SECONDS" ] && pass "lone post costs ${w}s" || flunk "expected ${DEBOUNCE_SECONDS}s, got ${w}s"

echo "=== 2. a trickle EXTENDS the window (the point of rolling) ==="
( for i in 1 2 3; do sleep 2; touch "$CONTENT_DIR/notes/t$i.md"; done ) &
bg=$!
w=$(await_quiet | tail -1)
wait $bg 2>/dev/null
[ "$w" -gt "$DEBOUNCE_SECONDS" ] && pass "extended to ${w}s" || flunk "no extension (${w}s) — is the wait still a fixed sleep?"

echo "=== 3. continuous activity hits the cap (${MAX_DEBOUNCE_SECONDS}s) ==="
( for i in $(seq 1 15); do sleep 1; touch "$CONTENT_DIR/notes/c$i.md"; done ) &
bg=$!
out=$(await_quiet)
kill $bg 2>/dev/null; wait $bg 2>/dev/null
w=$(echo "$out" | tail -1)
echo "$out" | grep -q "Debounce cap reached" && pass "cap fired at ${w}s" || flunk "cap never fired (${w}s) — build could be deferred forever"

echo "=== 4. a deletion registers as activity ==="
before=$(content_activity_stamp)
sleep 1
rm "$CONTENT_DIR/notes/seed.md"
after=$(content_activity_stamp)
[ "$before" != "$after" ] && pass "deletion moved the stamp" || flunk "deletion invisible — unpublishing would not extend the window"

echo "=== 5. _data is excluded from the activity stamp (hashed separately) ==="
before=$(content_activity_stamp)
sleep 1
touch "$CONTENT_DIR/_data/site-config.json"
after=$(content_activity_stamp)
[ "$before" = "$after" ] && pass "_data ignored by the mtime probe" || flunk "_data leaked into the stamp — byte-identical rewrites would extend the window forever"

find "$CONTENT_DIR" -delete 2>/dev/null
echo
if [ $fail -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $fail
