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
#    Reproduced deterministically. FIXED ON UPSTREAM main (4.0.0-alpha.10 adds
#    `await tmpl.asyncTemplateInitialization()` before the check) but NOT
#    backported to 3.x, and 3.1.6 is npm `latest`. Full builds cannot hit it:
#    isFileRelevantToThisTemplate() returns true on its second line when there is
#    no incremental file, never reaching the getter that throws.
#
# 2. MEMORY. From .eleventy-mem.log (950 completed builds), peak RSS grows
#    monotonically with how many builds a process has done: 2076MB median on a
#    process's 1st build, 2779MB median / 3491MB p90 / 3766MB max by its 10th.
#    --incremental was adopted in 270f6ec explicitly to save memory and it costs
#    memory. Twelve separate commits moved the heap cap chasing that curve.
#
#    BE HONEST ABOUT THE SIZE OF THIS WIN. That 2076MB median is across ALL
#    first-builds in the log, most of them short or aborted. Measured on the real
#    3,443-page site at the 2026-09-16 cutover: one-shot full build peaked at
#    3034MB RSS / 1781MB heap, versus 3080MB RSS / 2274MB heap for the watcher's
#    own build half an hour earlier. RSS is the SAME; the win is ~500MB of heap
#    peak, which is what the heap cap actually governs. Real, but modest. The
#    correctness and support arguments below carry this decision, not this one.
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
# The cost is wall-clock, and it is the honest headline: a full build of rmendes
# takes 388s where a healthy incremental took 51s. Rebuilds are asynchronous and
# the previous output keeps serving throughout, so that time is invisible to
# readers — unlike a dropped post, which is permanent.
#
# Inherits its environment (NODE_OPTIONS, SITE_URL, secrets) from start.sh,
# which backgrounds this script after exporting them.

set +e  # a failing build must never kill this loop

ELEVENTY_DIR=/app/pkg/eleventy-site
CONTENT_DIR=/app/data/content

# /app/data/site is a SYMLINK to the live release. Builds target a fresh
# directory under releases/ and the symlink is renamed over on success, so the
# previous release serves — complete and self-consistent — for the whole build.
SITE_LINK=/app/data/site
RELEASES_DIR=/app/data/releases

# Keep this many releases, newest first. Each is ~910MB now that generated media
# lives outside the output (og/ and img/ are served by nginx alias from
# /app/data). Rollback is a relink to an older one plus a restart.
KEEP_RELEASES=3

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

# Atomic symlink swap.
#
# `mv -T` is a rename(2): the symlink never does not exist. `ln -sfn` is NOT a
# substitute — it unlinks then links, and a request landing in that window gets
# a 404 from the document root disappearing.
#
# No `nginx -s reload` is needed: the config has no open_file_cache, so nginx
# resolves the symlink through the kernel on every open(2) and picks up the new
# target immediately. Requests already in flight keep streaming from the inode
# they opened, which is exactly the atomicity wanted. If open_file_cache is ever
# added to nginx.conf, a reload becomes REQUIRED here.
swap_release() {
    local new_release="$1"
    ln -s "$new_release" "${SITE_LINK}_tmp" || return 1
    chown -h cloudron:cloudron "${SITE_LINK}_tmp" 2>/dev/null || true
    mv -T "${SITE_LINK}_tmp" "$SITE_LINK" || { rm -f "${SITE_LINK}_tmp"; return 1; }
    return 0
}

# Drop releases beyond KEEP_RELEASES, newest kept.
#
# The live release is resolved and skipped explicitly rather than trusting it to
# be among the newest: if the clock ever went backwards, or a release directory
# were touched, `ls -t` ordering would otherwise delete the directory the
# running site is being served from.
prune_releases() {
    local live dir
    live=$(readlink -f "$SITE_LINK" 2>/dev/null)
    for dir in $(ls -1dt "${RELEASES_DIR}"/*/ 2>/dev/null | tail -n +$((KEEP_RELEASES + 1))); do
        dir=${dir%/}
        [ "$(readlink -f "$dir")" = "$live" ] && continue
        rm -rf "$dir" && echo "[build-loop] Removed old release $(basename "$dir")"
    done
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

    # Where this build writes. With the swap enabled that is a brand-new
    # directory; the live site is not touched until the build has succeeded.
    local target
    if [ "$SWAP_ENABLED" = true ]; then
        target="${RELEASES_DIR}/$(date +%s)"
        mkdir -p "$target" || return 1
        chown cloudron:cloudron "$target" 2>/dev/null || true
    else
        target="$SITE_LINK"
    fi

    cd "$ELEVENTY_DIR" || return 1
    gosu cloudron:cloudron "${ELEVENTY_DIR}/node_modules/.bin/eleventy" --output="$target"
    local exit_code=$?

    # A build that wrote nothing must never be swapped in, whatever it exited
    # with. `Wrote 0 files` is the failure that kept the watcher alive for 24
    # hours on 2026-09-15; in place it left the site stale, but swapped it would
    # replace the site with an empty directory.
    if [ $exit_code -eq 0 ] && [ "$SWAP_ENABLED" = true ] && [ ! -s "${target}/index.html" ]; then
        echo "[build-loop] Build exited 0 but produced no index.html — refusing to swap"
        exit_code=90
    fi

    if [ $exit_code -eq 0 ] && [ "$SWAP_ENABLED" = true ]; then
        if swap_release "$target"; then
            echo "[build-loop] Swapped to release $(basename "$target")"
            prune_releases
        else
            echo "[build-loop] Build succeeded but the release swap FAILED — site still on the previous release"
            exit_code=91
        fi
    fi

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
        # Throw away the half-built release. The live symlink was never touched,
        # so the previous release keeps serving, complete and self-consistent.
        if [ "$SWAP_ENABLED" = true ] && [ -n "${target:-}" ] && [ "$target" != "$SITE_LINK" ]; then
            rm -rf "$target"
        fi
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
# Atomic swap requires /app/data/site to BE a symlink. start.sh migrates an old
# real directory into releases/ and links it, so this should always hold — but if
# it somehow does not, build in place rather than refuse to build at all. A site
# that rebuilds without atomicity beats a site that stops rebuilding.
if [ -L "$SITE_LINK" ]; then
    SWAP_ENABLED=true
else
    SWAP_ENABLED=false
    echo "==> [build-loop] WARNING: ${SITE_LINK} is not a symlink — building IN PLACE, no atomic swap"
fi

echo "==> [build-loop] Starting (one-shot full builds; poll ${POLL_SECONDS}s, debounce ${DEBOUNCE_SECONDS}s, swap=${SWAP_ENABLED})"
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
