#!/bin/bash
#
# Eleventy build loop — one SHORT-LIVED full build per batch of changes.
#
# Replaces `eleventy --watch --incremental`, which ran as a single long-lived
# process for the life of the container. That arrangement was the source of most
# of this file's history, for three independent reasons:
#
# 1. CORRECTNESS. @11ty/eleventy 3.1.2 AND 3.1.6 throw `templateRender has not
#    yet initialized` when TemplateWriter._addToTemplateMapIncrementalBuild
#    reaches a Template that has not been async-initialised — which is exactly
#    what a file created since the last glob is. The build writes 0 files, the
#    process STAYS ALIVE, and the post that triggered it is never published.
#    Reproduced deterministically; no open upstream issue. Full builds cannot hit
#    it: isFileRelevantToThisTemplate() returns true on its second line when
#    there is no incremental file, never reaching the getter that throws.
#
# 2. MEMORY. Measured from .eleventy-mem.log (950 completed builds): the FIRST
#    full build in a fresh process peaks at 2076MB median; the tenth incremental
#    build in the same process peaks at 2779MB median / 3491MB p90 / 3766MB max.
#    --incremental was adopted in 270f6ec explicitly to save memory and it costs
#    memory, monotonically with process age. Twelve separate commits raised or
#    lowered --max-old-space-size chasing that curve. A process that exits gives
#    every byte back.
#
# 3. SUPPORT. Upstream documents --incremental as "to improve build times when
#    doing local development" and lists server-side incremental as an
#    unimplemented To Do (#2775). Nunjucks {% include %} has no incremental
#    dependency graph at all (#3804, OPEN). 11ty's own site uses --incremental in
#    exactly one npm script (`start`, local dev) and its `start-production`
#    script drops it. GoogleChrome/web.dev does not use `eleventy --watch` even
#    in development — it runs chokidar spawning clean one-shot builds, which is
#    what this file does.
#
# The cost is wall-clock: full builds run 154s median where a healthy
# incremental ran 51s. Rebuilds are asynchronous and the previous output keeps
# serving throughout, so that time is invisible to readers — unlike a dropped
# post, which is permanent.
#
# Inherits its environment (NODE_OPTIONS, SITE_URL, secrets) from start.sh,
# which backgrounds this script after exporting them.

set +e  # a failing build must never kill this loop

ELEVENTY_DIR=/app/pkg/eleventy-site
CONTENT_DIR=/app/data/content
OUTPUT_DIR=/app/data/site

# How often to look for changes. Cheap: one find(1) that stops at the first hit.
POLL_SECONDS=10

# After spotting a change, wait this long before building so a burst of posts
# (or a Micropub write plus its media) becomes ONE build instead of several.
DEBOUNCE_SECONDS=15

# A build that fails will still look "changed" on the next poll, so back off
# instead of spinning. Resets on the first success.
BACKOFF_SECONDS=30
MAX_BACKOFF_SECONDS=600

# Scan boundary. Everything modified after this has not been built yet.
# Lives in /app/data so it survives container recreation.
MARKER=/app/data/.last-build-scan

# Purge eleventy-fetch cache entries whose body file is empty.
# eleventy-fetch decides cache validity WITHOUT validating content: v4 checks the
# metadata sidecar only, v5 adds existsSync — which a zero-byte file passes. It
# then parses the body unguarded (v4 `require()`, v5 `JSON.parse`), so an empty
# body throws "Unexpected end of JSON input" on every build and never re-fetches:
# a permanent crash loop. Empty bodies come from its non-atomic writeFile, which
# truncates to 0 before writing — die in that window and the body is left empty
# while the metadata keeps its older timestamp.
# Remove the metadata sidecar too: dropping only the body leaves the entry "valid"
# and turns the parse error into a missing-module error.
purge_empty_fetch_cache() {
    local body count=0
    for body in /app/data/cache/eleventy-fetch-*.json; do
        [ -f "$body" ] || continue      # no matches: glob stays literal
        [ -s "$body" ] && continue      # non-empty: keep
        rm -f "$body" "${body%.json}"   # body + metadata sidecar
        count=$((count + 1))
    done
    [ $count -gt 0 ] && echo "[build-loop] Purged $count corrupt (zero-byte) eleventy-fetch cache entries"
    return 0
}

# Content signature — MTIME based, and deliberately NOT content-hashed.
#
# Hashing 2,785 markdown files every 10 seconds would be absurd; find(1) with
# -quit stops at the FIRST match and usually touches only a handful of inodes.
#
# Directories are included on purpose: deleting a post does not make any
# surviving file newer, but it does bump the mtime of the directory that held
# it. Without `-o -type d` an unpublish would never rebuild.
#
# _data is pruned because its artifacts get a different test (below): the
# site-config and CV plugins rewrite them from MongoDB at every container start
# with byte-identical content, which bumps mtime without changing anything. That
# is what made every deploy do two full builds until a2f11e8 switched to
# hashing; keep the two detectors separate or that regression comes back.
content_changed() {
    [ -f "$MARKER" ] || return 0   # never built — everything is new
    [ -n "$(find "$CONTENT_DIR" \
        -path "$CONTENT_DIR/_data" -prune -o \
        \( -newer "$MARKER" \) -print -quit 2>/dev/null)" ]
}

# Artifact signature — CONTENT hashed, for the reason above. md5sum prints
# "hash  path" per line, so an added, deleted or renamed artifact moves the
# signature too. Total payload is ~55KB. Hashes EVERY json artifact rather than
# a hand-listed subset: the old list missed loaded-plugins.json,
# block-catalog.json and categories.json, and any future plugin artifact would
# have been missed as well. `*.tmp` staging files do not match `*.json`, so a
# half-written artifact can never enter the signature.
artifact_signature() {
    md5sum "$CONTENT_DIR"/_data/*.json "$CONTENT_DIR"/_data/compositions/*.json 2>/dev/null | tr '\n' ','
}

# Report a failed build the same way start.sh's old crash wrapper did, so the
# admin UI and /health/build.json keep working. node, not a heredoc: the health
# write must MERGE (preserve lastOkAt, increment consecutiveFailures).
report_failure() {
    local exit_code="$1"
    cat > /app/data/build-status.json.tmp <<EOF
{"state":"failed","error":"build exited with code ${exit_code}","finishedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
    mv /app/data/build-status.json.tmp /app/data/build-status.json || true
    chown cloudron:cloudron /app/data/build-status.json 2>/dev/null || true

    gosu cloudron:cloudron node -e '
      import("/app/pkg/eleventy-site/lib/build-health.mjs")
        .then(({ writeBuildHealth }) => writeBuildHealth({
          state: "failed",
          lastBuildAt: new Date().toISOString(),
        }))
        .catch((error) => console.warn("[build-health] " + error.message));
    ' 2>/dev/null || echo "[build-loop] build-health write skipped"
}

run_build() {
    local reason="$1"
    purge_empty_fetch_cache

    # Stamp the scan boundary BEFORE the build, not after. A post written while
    # the build runs is newer than this stamp and therefore triggers the NEXT
    # build. Stamping afterwards would swallow it — which is the exact class of
    # silent loss this whole rewrite exists to remove.
    touch "$MARKER.pending"

    echo "[build-loop] Build started (${reason})"
    local started
    started=$(date +%s)

    cd "$ELEVENTY_DIR" || return 1
    gosu cloudron:cloudron "${ELEVENTY_DIR}/node_modules/.bin/eleventy" --output="$OUTPUT_DIR"
    local exit_code=$?
    local elapsed=$(( $(date +%s) - started ))

    if [ $exit_code -eq 0 ]; then
        # Commit the boundary only on success. A failed build leaves the old
        # marker in place so its changes are retried rather than lost.
        mv "$MARKER.pending" "$MARKER"
        chown cloudron:cloudron "$MARKER" 2>/dev/null || true
        BACKOFF_SECONDS=30
        echo "[build-loop] Build finished in ${elapsed}s"
    else
        rm -f "$MARKER.pending"
        echo "[build-loop] Build FAILED with code ${exit_code} after ${elapsed}s — retrying in ${BACKOFF_SECONDS}s"
        report_failure "$exit_code"
        sleep "$BACKOFF_SECONDS"
        BACKOFF_SECONDS=$(( BACKOFF_SECONDS * 2 ))
        [ $BACKOFF_SECONDS -gt $MAX_BACKOFF_SECONDS ] && BACKOFF_SECONDS=$MAX_BACKOFF_SECONDS
    fi
}

# Always build once at startup, whatever the marker says. A deploy changes the
# THEME and the plugin loadout, not the content, so change detection alone would
# happily serve the previous build's HTML from a container running new code.
echo "==> [build-loop] Starting (one-shot full builds; poll ${POLL_SECONDS}s, debounce ${DEBOUNCE_SECONDS}s)"
ARTIFACT_SIG=$(artifact_signature)
run_build "container start"

while true; do
    sleep "$POLL_SECONDS"

    REASON=""
    if content_changed; then
        REASON="content changed"
    else
        SIG_NOW=$(artifact_signature)
        if [ "$SIG_NOW" != "$ARTIFACT_SIG" ]; then
            REASON="site-config/composition artifact changed"
        fi
    fi
    [ -z "$REASON" ] && continue

    # Let the burst settle. Five posts published in a minute should cost one
    # build, not five.
    sleep "$DEBOUNCE_SECONDS"

    # Re-read the artifact signature AFTER the debounce so changes that landed
    # during it are counted as built, not as a fresh trigger on the next pass.
    ARTIFACT_SIG=$(artifact_signature)
    run_build "$REASON"
done
