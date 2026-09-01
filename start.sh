#!/bin/bash

set -eu

echo "==> Ensure directories"
mkdir -p /app/data/config /app/data/content /app/data/uploads /app/data/releases /app/data/cache /app/data/images

# Clean up data corruption from previous buggy deployments
echo "==> Cleaning up any corrupted data from backups"
# Remove circular symlink that causes ELOOP errors (content/content/content/...)
rm -f /app/data/content/content 2>/dev/null || true
# Remove old buggy eleventy directory (node_modules should never be in /app/data)
rm -rf /app/data/eleventy 2>/dev/null || true

# Merge migrated legacy content (copy new files without overwriting existing)
if [[ -d /app/pkg/migrated-content ]]; then
    echo "==> Merging migrated legacy content"
    for dir in /app/pkg/migrated-content/*/; do
        dirname=$(basename "$dir")
        mkdir -p "/app/data/content/$dirname"
        # Use cp -n (no clobber) to not overwrite existing files
        cp -rn "$dir"* "/app/data/content/$dirname/" 2>/dev/null || true
    done
    echo "==> Migration merge complete"
fi

# Seed Eleventy layout directory-data files so a fresh content volume renders
# through the theme out of the box. Eleventy assigns no layout to Micropub-created
# .md files on its own; these directory-data files map content dirs → theme
# layouts. Without them, pages/notes render as raw HTML with no <head> (no
# charset → mojibake). Idempotent: only created when missing, so a site that
# customizes these keeps its own version (e.g. rmendes is left untouched).
echo "==> Seeding Eleventy layout data files (if missing)"
if [[ ! -f /app/data/content/content.json ]]; then
    echo '{"layout": "layouts/post.njk"}' > /app/data/content/content.json
    echo "    seeded content/content.json (default layout for all content)"
fi
mkdir -p /app/data/content/pages
if [[ ! -f /app/data/content/pages/pages.json ]]; then
    echo '{"layout": "layouts/page.njk"}' > /app/data/content/pages/pages.json
    echo "    seeded content/pages/pages.json (slash-page layout)"
fi

# Update config from bundled version (supports personal overrides via .rmendes pattern)
# Always update to ensure config changes are applied on deploy
if [[ -f /app/pkg/indiekit.config.js ]]; then
    echo "==> Updating Indiekit config from bundled version"
    cp /app/pkg/indiekit.config.js /app/data/config/indiekit.config.js
elif [[ ! -f /app/data/config/indiekit.config.js ]]; then
    echo "==> Creating default config from template (first run)"
    cp /app/pkg/indiekit.config.js.template /app/data/config/indiekit.config.js
fi

# Per-site loaded-plugins manifest → Eleventy _data file.
# The composer (scripts/compose-site.mjs) emits sites/<site>/.compiled/plugin-loadout.json
# which the Dockerfile bakes into /app/pkg/loaded-plugins.json. Exposing it under
# /app/data/content/_data/ lets theme templates read `loadedPlugins.<key>` to
# conditionally render plugin-specific UI (e.g. `{% if loadedPlugins.cv %}…{% endif %}`).
if [[ -f /app/pkg/loaded-plugins.json ]]; then
    mkdir -p /app/data/content/_data
    cp /app/pkg/loaded-plugins.json /app/data/content/_data/loaded-plugins.json
    echo "==> Exposed loaded-plugins.json to theme (_data/)"
fi

# Create user env file for secrets on first run
if [[ ! -f /app/data/config/env.sh ]]; then
    echo "==> Creating env.sh for syndicator tokens"
    cat > /app/data/config/env.sh <<'ENVEOF'
# Add your tokens here and restart the app

# PASSWORD_SECRET - REQUIRED after first run
# 1. Visit your Indiekit URL /admin, you'll see a "New password" page
# 2. Create a password
# 3. Copy the PASSWORD_SECRET hash and paste it below IN SINGLE QUOTES
# 4. Restart the app (cloudron restart)
# IMPORTANT: Use single quotes because the hash contains $ characters!
export PASSWORD_SECRET='paste-your-hash-here'

# GitHub token (optional, for /github endpoint)
export GITHUB_TOKEN=""

# Bluesky app password (get from Settings > App Passwords)
export BLUESKY_PASSWORD=""

# Mastodon access token (get from Settings > Development > Applications)
export MASTODON_ACCESS_TOKEN=""

# LinkedIn syndication (for posting to LinkedIn)
# Option 1: Use OAuth flow at /linkedin (recommended)
# Option 2: Set access token manually
export LINKEDIN_ACCESS_TOKEN=""
export LINKEDIN_AUTHOR_NAME=""
export LINKEDIN_PROFILE_URL=""
# LinkedIn OAuth app credentials (get from LinkedIn Developer Portal)
export LINKEDIN_CLIENT_ID=""
export LINKEDIN_CLIENT_SECRET=""

# Webmention.io token (get from https://webmention.io/settings)
export WEBMENTION_IO_TOKEN=""

# Funkwhale configuration (for /funkwhale endpoint)
# Get token from your Funkwhale Settings > Applications
export FUNKWHALE_INSTANCE="https://buzzworkers.com"
export FUNKWHALE_TOKEN=""
export FUNKWHALE_USERNAME="buzz"

# YouTube configuration (for /youtube endpoint)
# Get API key from Google Cloud Console > APIs & Services > Credentials
export YOUTUBE_API_KEY=""
# Comma-separated channel handles (e.g., "@channel1,@channel2")
export YOUTUBE_CHANNELS=""

# Last.fm configuration (for /listening endpoint)
# Get API key from https://www.last.fm/api/account/create
export LASTFM_API_KEY=""
export LASTFM_USERNAME=""

# Site customization (optional)
export SITE_NAME="My IndieWeb Blog"
export SITE_DESCRIPTION="An IndieWeb blog powered by Indiekit"
export AUTHOR_NAME="Your Name"
export AUTHOR_TITLE=""
export AUTHOR_BIO="Welcome to my IndieWeb blog."
export AUTHOR_AVATAR=""
export AUTHOR_LOCATION=""
export AUTHOR_LOCALITY=""
export AUTHOR_COUNTRY=""
export AUTHOR_ORG=""
export AUTHOR_PRONOUN=""
export AUTHOR_EMAIL=""
export AUTHOR_KEY_URL=""
export AUTHOR_CATEGORIES=""

# Social profile handles (used for feed widgets AND h-card rel="me" links)
export GITHUB_USERNAME=""
export BLUESKY_HANDLE=""
export MASTODON_INSTANCE=""
export MASTODON_USER=""
export LINKEDIN_USERNAME=""
export ACTIVITYPUB_HANDLE=""  # Fediverse handle (e.g., "rick") — adds rel="me" link to h-card

# Or set all social links manually (overrides auto-generation from handles above)
# Format: "Name|URL|icon,Name|URL|icon"
# Example: "GitHub|https://github.com/user|github,Mastodon|https://mastodon.social/@user|mastodon"
export SITE_SOCIAL=""

# Markdown for Agents — serve clean Markdown to AI agents
# Set to "false" to disable Markdown generation entirely
export MARKDOWN_AGENTS_ENABLED="true"
# Content-signal policy — controls what AI agents are allowed to do with your content
# Values: "yes" or "no" for each signal
export MARKDOWN_AGENTS_AI_TRAIN="yes"   # Allow AI model training
export MARKDOWN_AGENTS_SEARCH="yes"     # Allow search indexing
export MARKDOWN_AGENTS_AI_INPUT="yes"   # Allow agentic use (RAG, summarization)
ENVEOF
fi

# Source user secrets
source /app/data/config/env.sh

# Migrate: add ACTIVITYPUB_HANDLE to env.sh if missing (added in v2.0.21)
if ! grep -q 'ACTIVITYPUB_HANDLE' /app/data/config/env.sh 2>/dev/null; then
    echo '' >> /app/data/config/env.sh
    echo '# ActivityPub handle for fediverse rel="me" verification in h-card' >> /app/data/config/env.sh
    echo 'export ACTIVITYPUB_HANDLE=""' >> /app/data/config/env.sh
fi

# Migrate: add MARKDOWN_AGENTS vars to env.sh if missing
if ! grep -q 'MARKDOWN_AGENTS_ENABLED' /app/data/config/env.sh 2>/dev/null; then
    cat >> /app/data/config/env.sh <<'MDEOF'

# Markdown for Agents — serve clean Markdown to AI agents
# Set to "false" to disable Markdown generation entirely
export MARKDOWN_AGENTS_ENABLED="true"
# Content-signal policy — controls what AI agents are allowed to do with your content
# Values: "yes" or "no" for each signal
export MARKDOWN_AGENTS_AI_TRAIN="yes"
export MARKDOWN_AGENTS_SEARCH="yes"
export MARKDOWN_AGENTS_AI_INPUT="yes"
MDEOF
fi

# Bridge ActivityPub handle to Eleventy theme for rel="me" link in h-card
# Priority: explicit ACTIVITYPUB_HANDLE > AP_ACTOR_HANDLE > extracted from indiekit config
if [[ -z "${ACTIVITYPUB_HANDLE:-}" && -z "${AP_ACTOR_HANDLE:-}" ]]; then
    # Extract handle from the activitypub plugin section of indiekit config
    AP_HANDLE_FROM_CONFIG=$(sed -n '/indiekit-endpoint-activitypub/,/^[[:space:]]*}/{ s/.*handle:[[:space:]]*"\([^"]*\)".*/\1/p; }' /app/data/config/indiekit.config.js 2>/dev/null | head -1)
    export ACTIVITYPUB_HANDLE="${AP_HANDLE_FROM_CONFIG}"
else
    export ACTIVITYPUB_HANDLE="${ACTIVITYPUB_HANDLE:-${AP_ACTOR_HANDLE:-}}"
fi

# Indiekit core configuration
export MONGODB_URL="${CLOUDRON_MONGODB_URL}"
export PORT=8080  # Indiekit runs on internal port, nginx proxies

# Generate and persist SECRET if not exists (used for JWT signing)
if [[ ! -f /app/data/config/.secret ]]; then
    openssl rand -hex 32 > /app/data/config/.secret
fi
export SECRET="$(cat /app/data/config/.secret)"

# App URL from Cloudron
export CLOUDRON_APP_URL="${CLOUDRON_APP_ORIGIN}"
export SITE_URL="${CLOUDRON_APP_ORIGIN}"
export SITE_ME="${CLOUDRON_APP_ORIGIN}"

echo "==> Setting permissions"
chown -R cloudron:cloudron /app/data

# Setup nginx first (needed for health checks)
cp /app/pkg/nginx.conf /run/nginx.conf
mkdir -p /run/nginx-client-body /run/nginx-proxy /run/nginx-fastcgi /run/nginx-uwsgi /run/nginx-scgi /run/nginx-ap-cache

echo "==> Starting nginx on port 3000"
nginx -c /run/nginx.conf &

# Start Indiekit in background first (so API is available for Eleventy build)
# Heap: 1024MB for Indiekit + plugins. If crashing at startup, check /tmp for heap snapshots.
# --heapsnapshot-near-heap-limit=1: auto-snapshot before OOM (writes to --diagnostic-dir)
# --heapsnapshot-signal=SIGUSR2: manual snapshot via kill -USR2 <pid>
# --abort-on-uncaught-exception: core dump on unhandled errors
# Remove readiness signal BEFORE Indiekit starts — plugins check on init
rm -f /app/data/.indiekit-ready

echo "==> Starting Indiekit on port ${PORT} (heap: 1536MB, diagnostic snapshots enabled)"
# CWD must be writable — V8 --heap-snapshot-on-oom writes to CWD.
# /app/code is read-only at runtime on Cloudron.
mkdir -p /tmp/indiekit-diag
cd /tmp/indiekit-diag
gosu cloudron:cloudron env NODE_OPTIONS="--max-old-space-size=1536 --heapsnapshot-signal=SIGUSR2 --diagnostic-dir=/tmp/indiekit-diag" node --heap-snapshot-on-oom /app/code/node_modules/@indiekit/indiekit/bin/cli.js serve --config /app/data/config/indiekit.config.js &
INDIEKIT_PID=$!

# Monitor Indiekit process for crashes (background)
(
    wait $INDIEKIT_PID 2>/dev/null
    EXIT_CODE=$?
    echo "[INDIEKIT CRASH] Process exited with code ${EXIT_CODE} at $(date '+%Y-%m-%d %H:%M:%S')"
    # Check for heap snapshots (V8 writes to CWD, Node writes to --diagnostic-dir)
    SNAPSHOTS=$(ls /tmp/indiekit-diag/*.heapsnapshot 2>/dev/null)
    if [ -n "$SNAPSHOTS" ]; then
        echo "[INDIEKIT CRASH] Heap snapshot(s) written:"
        ls -lh /tmp/indiekit-diag/*.heapsnapshot 2>/dev/null
        # Copy to persistent storage for analysis
        cp /tmp/indiekit-diag/*.heapsnapshot /app/data/config/ 2>/dev/null
        echo "[INDIEKIT CRASH] Snapshot(s) copied to /app/data/config/ for retrieval"
    else
        echo "[INDIEKIT CRASH] No heap snapshots found in /tmp/indiekit-diag/"
    fi
    echo "[INDIEKIT CRASH] RSS at exit: $(cat /proc/$INDIEKIT_PID/status 2>/dev/null | grep VmRSS || echo 'process gone')"
) &

# Wait for Indiekit to be ready (max 30 seconds)
echo "==> Waiting for Indiekit to be ready..."
for i in {1..30}; do
    if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ | grep -q "200\|302"; then
        echo "==> Indiekit is ready"
        break
    fi
    sleep 1
done

# Wait extra time for API endpoints to initialize (plugins need to register routes)
echo "==> Waiting for API endpoints to initialize..."
sleep 3

# Verify Funkwhale API is available (if configured)
if [ -n "${FUNKWHALE_TOKEN:-}" ]; then
    for i in {1..10}; do
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/funkwhaleapi/api/now-playing 2>/dev/null | grep -q "200"; then
            echo "==> Funkwhale API is ready"
            break
        fi
        sleep 1
    done
fi

# Verify Last.fm API is available (if configured)
if [ -n "${LASTFM_API_KEY:-}" ]; then
    for i in {1..10}; do
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/lastfmapi/api/now-playing 2>/dev/null | grep -q "200"; then
            echo "==> Last.fm API is ready"
            break
        fi
        sleep 1
    done
fi

# Verify GitHub starred API is available (if configured)
if [ -n "${GITHUB_TOKEN:-}" ]; then
    for i in {1..10}; do
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/githubapi/api/starred/all 2>/dev/null | grep -q "200"; then
            echo "==> GitHub starred API is ready"
            break
        fi
        sleep 1
    done
fi

# ─── Start background pollers early (they only need Indiekit, not Eleventy) ───

# Start syndication background process
# Polls the syndicate endpoint every 2 minutes to process pending syndications
echo "==> Starting syndication background process"
(
    echo "[syndication] Starting auto-syndication polling"
    while true; do
        # Safety net: verify the site is serving before attempting syndication.
        # During initial Eleventy build (~9 min after restart), pages don't exist yet.
        SITE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${CLOUDRON_APP_ORIGIN}/" 2>/dev/null)
        if [ "$SITE_STATUS" != "200" ]; then
            echo "[syndication] $(date '+%Y-%m-%d %H:%M:%S') - Site not ready (HTTP $SITE_STATUS), skipping cycle"
            sleep 120
            continue
        fi

        # Read SECRET from file (env var not available in subshell)
        SYNDICATION_SECRET=$(cat /app/data/config/.secret 2>/dev/null)
        SYNDICATION_ORIGIN="${CLOUDRON_APP_ORIGIN}"

        if [ -n "$SYNDICATION_SECRET" ]; then
            # Generate a short-lived JWT token with update scope
            # Uses env vars instead of shell interpolation to prevent injection
            SYNDICATION_TOKEN=$(cd /app/code && JWT_ORIGIN="$SYNDICATION_ORIGIN" JWT_SECRET="$SYNDICATION_SECRET" node -e "
                const jwt = require('jsonwebtoken');
                const token = jwt.sign(
                    { me: process.env.JWT_ORIGIN, scope: 'update' },
                    process.env.JWT_SECRET,
                    { expiresIn: '5m' }
                );
                console.log(token);
            " 2>/dev/null)

            if [ -n "$SYNDICATION_TOKEN" ]; then
                # Call syndicate endpoint - this processes posts with mp-syndicate-to
                RESULT=$(curl -s -X POST "http://localhost:8080/syndicate?token=${SYNDICATION_TOKEN}" \
                    -H "Content-Type: application/json" 2>&1)
                echo "[syndication] $(date '+%Y-%m-%d %H:%M:%S') - $RESULT"
            fi
        fi

        # Wait 2 minutes before next check
        sleep 120
    done
) &

# Start webmention sender background process
# Polls the webmention-sender endpoint every 5 minutes to send pending webmentions
echo "==> Starting webmention sender background process"
(
    echo "[webmention] Starting auto-send polling"
    # Wait 3 minutes before first run (let Eleventy build complete first)
    sleep 180
    while true; do
        # Safety net: verify the site is serving before attempting to send webmentions.
        # The real per-post URL check is in the controller, but this avoids unnecessary
        # JWT generation and HTTP calls when the site is completely down.
        SITE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${CLOUDRON_APP_ORIGIN}/" 2>/dev/null)
        if [ "$SITE_STATUS" != "200" ]; then
            echo "[webmention] $(date '+%Y-%m-%d %H:%M:%S') - Site not ready (HTTP $SITE_STATUS), skipping cycle"
            sleep 300
            continue
        fi

        # Read SECRET from file (env var not available in subshell)
        WEBMENTION_SECRET=$(cat /app/data/config/.secret 2>/dev/null)
        WEBMENTION_ORIGIN="${CLOUDRON_APP_ORIGIN}"

        if [ -n "$WEBMENTION_SECRET" ]; then
            # Generate a short-lived JWT token with update scope
            # Uses env vars instead of shell interpolation to prevent injection
            WEBMENTION_TOKEN=$(cd /app/code && JWT_ORIGIN="$WEBMENTION_ORIGIN" JWT_SECRET="$WEBMENTION_SECRET" node -e "
                const jwt = require('jsonwebtoken');
                const token = jwt.sign(
                    { me: process.env.JWT_ORIGIN, scope: 'update' },
                    process.env.JWT_SECRET,
                    { expiresIn: '5m' }
                );
                console.log(token);
            " 2>/dev/null)

            if [ -n "$WEBMENTION_TOKEN" ]; then
                # Call webmention-sender endpoint - this sends webmentions for posts
                RESULT=$(curl -s -X POST "http://localhost:8080/webmention-sender?token=${WEBMENTION_TOKEN}" \
                    -H "Content-Type: application/json" 2>&1)
                echo "[webmention] $(date '+%Y-%m-%d %H:%M:%S') - $RESULT"
            fi
        fi

        # Wait 5 minutes before next check
        sleep 300
    done
) &

# ─── Zero-downtime Eleventy build with atomic release swap ───
# Old site continues serving while new build runs. Swap is atomic (single syscall).

# Ensure /app/data/site is a symlink to a release directory
# Migration: if /app/data/site is a real directory (pre-atomic-swap), convert it
if [ -d /app/data/site ] && [ ! -L /app/data/site ]; then
    echo "==> Migrating /app/data/site from directory to release symlink"
    MIGRATION_TS=$(date +%s)
    mv /app/data/site "/app/data/releases/${MIGRATION_TS}"
    ln -s "/app/data/releases/${MIGRATION_TS}" /app/data/site
    chown -h cloudron:cloudron /app/data/site
    echo "==> Migration complete: site -> releases/${MIGRATION_TS}"
fi

# First-ever run: no symlink and no directory exist yet
if [ ! -L /app/data/site ] && [ ! -d /app/data/site ]; then
    echo "==> First run: creating placeholder release"
    mkdir -p /app/data/releases/placeholder
    echo '<html><head><meta http-equiv="refresh" content="5"></head><body><p>Building site...</p></body></html>' > /app/data/releases/placeholder/index.html
    chown -R cloudron:cloudron /app/data/releases/placeholder
    ln -s /app/data/releases/placeholder /app/data/site
    chown -h cloudron:cloudron /app/data/site
fi

# At this point /app/data/site is a symlink → previous release → nginx serves old site
CURRENT_RELEASE=$(readlink -f /app/data/site)
echo "==> Current release: ${CURRENT_RELEASE}"
echo "==> Old site continues serving while new build runs"

# Eleventy-fetch cache is NOT wiped on deploy. Each entry has its own TTL
# (duration: "1d" for build, "30d" for watch) and expires naturally.
# Wiping forces ALL _data files to re-fetch from APIs simultaneously,
# which causes OOM during the initial build (2,352 posts + fresh API data
# exceeds the 2048MB heap within the 3072MB cgroup limit).
# If you need to force a fresh fetch, delete specific cache files manually.

# Initial build DISABLED — consistently OOMs because Eleventy (3.9GB peak RSS from
# V8 heap + Sharp buffers + OG WASM) + Indiekit (~370MB) exceeds the 4GB cgroup.
# The watcher always succeeds because it starts after the initial build process exits,
# freeing all memory. The old release serves during the watcher's ~5 min full build.
# To re-enable: uncomment the block below and comment the INITIAL_BUILD_OK=false line.
INITIAL_BUILD_OK=false
cd /app/pkg/eleventy-site
export DEBUG="Eleventy:Benchmark*"

# # Build new release to a timestamped directory
# RELEASE_TS=$(date +%s)
# NEW_RELEASE="/app/data/releases/${RELEASE_TS}"
# mkdir -p "${NEW_RELEASE}"
# chown cloudron:cloudron "${NEW_RELEASE}"
#
# echo "==> Building Eleventy site to ${NEW_RELEASE}"
# export NODE_OPTIONS="--max-old-space-size=2560"
# INITIAL_BUILD_OK=false
# # Pagefind runs inside Eleventy's eleventy.after hook (non-incremental builds only)
# gosu cloudron:cloudron node --heap-snapshot-on-oom ./node_modules/.bin/eleventy --output="${NEW_RELEASE}" && INITIAL_BUILD_OK=true || {
#     echo "==> Eleventy build failed (likely OOM-killed)"
#     SNAP=$(ls -t /tmp/*.heapsnapshot 2>/dev/null | head -1)
#     if [ -n "$SNAP" ]; then
#         SNAP_SIZE=$(du -h "$SNAP" | cut -f1)
#         echo "==> Heap snapshot captured: $SNAP ($SNAP_SIZE)"
#     fi
# }

# Only swap if build succeeded — keep serving the old release on failure
if [ "$INITIAL_BUILD_OK" = true ]; then
    # Sync OG images from persistent cache to new release.
    # eleventy.before generates OG images to .cache/og/ (→ /app/data/cache/og/),
    # but passthrough copy may miss them when --output differs from _site symlink.
    if [ -d /app/data/cache/og ]; then
        echo "==> Syncing OG images from cache to new release"
        mkdir -p "${NEW_RELEASE}/og"
        cp -f /app/data/cache/og/*.png "${NEW_RELEASE}/og/" 2>/dev/null || true
        OG_COUNT=$(ls -1 "${NEW_RELEASE}/og/"*.png 2>/dev/null | wc -l)
        echo "==> Synced ${OG_COUNT} OG images"
    fi

    echo "==> Setting permissions on new release"
    chown -R cloudron:cloudron "${NEW_RELEASE}"

    # Atomic swap: create temp symlink, then rename over current (rename(2) is atomic)
    echo "==> Atomic swap: site -> releases/${RELEASE_TS}"
    ln -s "${NEW_RELEASE}" /app/data/site_tmp
    chown -h cloudron:cloudron /app/data/site_tmp
    mv -T /app/data/site_tmp /app/data/site

    # Reload nginx to resolve the new symlink target
    nginx -s reload
    echo "==> nginx reloaded, new release is live"

    # Signal readiness — plugins can now start background tasks
    touch /app/data/.indiekit-ready
    chown cloudron:cloudron /app/data/.indiekit-ready
    echo "==> Readiness signal created, plugins starting deferred tasks"

    # Cleanup: keep only 2 most recent releases for rollback capability
    echo "==> Cleaning up old releases (keeping 2)"
    cd /app/data/releases && ls -1t | tail -n +3 | xargs -r rm -rf
else
    echo "==> Initial build skipped/failed, keeping previous release: ${CURRENT_RELEASE}"
    # Clean up the failed release directory (if one was created)
    if [ -n "${NEW_RELEASE:-}" ]; then rm -rf "${NEW_RELEASE}"; fi
    # Note: readiness signal is NOT created here — the watcher will do a full
    # build on start and the eleventy.after hook creates the signal file when
    # that build completes. This ensures plugins don't start until the system
    # is truly stable (watcher running + build finished).
fi

# Start Eleventy in watch+incremental mode to rebuild only affected pages on content changes
# Wrapped in a supervisor loop that restarts on crash with exponential backoff
# The watcher writes to /app/data/site (current release via symlink)
# Watcher does a full build on first start, then switches to incremental mode.
# Needs same heap as initial build for that first pass. Runs after initial build
# completes, so never concurrent — 2048MB is safe within 3072MB cgroup.
# --expose-gc allows eleventy.config.js to call global.gc() after each build,
# forcing V8 to release freed heap pages back to the OS via madvise(MADV_DONTNEED).
# Without this, post-build allocations stay resident because watch mode has no
# allocation pressure to trigger GC naturally.
# --heapsnapshot-signal=SIGUSR2: for on-demand heap snapshot analysis.
# Heap at 2560 — watcher's initial full build peaks above 2304MB V8 heap (3,400
# pages in memory). Needs 3.5GB+ cgroup: watcher ~2800 peak + Indiekit ~600 = ~3400.
# Steady state after build is ~2300MB total.
export NODE_OPTIONS="--max-old-space-size=2560 --expose-gc --heapsnapshot-signal=SIGUSR2 --diagnostic-dir=/tmp"
# Syndication webhook — Eleventy triggers syndication immediately after incremental builds
export SYNDICATE_WEBHOOK_URL="http://localhost:8080/syndicate"
export SYNDICATE_SECRET_FILE="/app/data/config/.secret"
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
    [ $count -gt 0 ] && echo "[eleventy-watcher] Purged $count corrupt (zero-byte) eleventy-fetch cache entries"
    return 0
}

echo "==> Starting Eleventy watcher for auto-rebuild (heap: 2560MB, expose-gc)"
(
    set +e  # Disable errexit so the retry loop survives crashes
    cd /app/pkg/eleventy-site
    RESTART_COUNT=0
    BACKOFF=5
    MAX_BACKOFF=300
    LAST_START=0

    while true; do
        NOW=$(date +%s)

        # Reset backoff if the watcher ran for at least 5 minutes (healthy run)
        if [ $LAST_START -gt 0 ] && [ $((NOW - LAST_START)) -ge 300 ]; then
            RESTART_COUNT=0
            BACKOFF=5
        fi

        LAST_START=$NOW
        RESTART_COUNT=$((RESTART_COUNT + 1))

        if [ $RESTART_COUNT -eq 1 ]; then
            echo "[eleventy-watcher] Starting watcher"
        else
            echo "[eleventy-watcher] Restarting watcher (attempt $RESTART_COUNT, backoff ${BACKOFF}s)"
            sleep $BACKOFF
            # Exponential backoff: 5, 10, 20, 40, 80, 160, 300 (capped)
            BACKOFF=$((BACKOFF * 2))
            if [ $BACKOFF -gt $MAX_BACKOFF ]; then
                BACKOFF=$MAX_BACKOFF
            fi
        fi

        # A fresh watcher start invalidates any pending sentinel — a config change
        # that touched it during the backoff window is picked up by this build anyway.
        rm -f /tmp/.eleventy-intentional-restart

        # Runs on every iteration: pre-flight on the first pass, self-heal after a
        # crash. Without it a single corrupt entry loops the watcher forever.
        purge_empty_fetch_cache

        # Use absolute path — gosu's exec may not resolve relative paths from subshell cwd
        gosu cloudron:cloudron /app/pkg/eleventy-site/node_modules/.bin/eleventy \
            --watch --incremental --output=/app/data/site
        EXIT_CODE=$?
        echo "[eleventy-watcher] Watcher exited with code $EXIT_CODE at $(date '+%Y-%m-%d %H:%M:%S')"
        # Consume the sentinel on every exit (even exit 0); combined with the
        # clear before each watcher start, a stale sentinel can never mask a
        # later real crash.
        INTENTIONAL=false
        if [ -f /tmp/.eleventy-intentional-restart ]; then
            rm -f /tmp/.eleventy-intentional-restart
            INTENTIONAL=true
            echo "[eleventy-watcher] Intentional restart (config change) — not a failure"
        fi
        if [ $EXIT_CODE -ne 0 ] && [ "$INTENTIONAL" != "true" ]; then
            # Crash: surface it to the admin UI via build-status (Phase 5).
            # jq isn't guaranteed; write with a heredoc + date.
            cat > /app/data/build-status.json.tmp <<EOF
{"state":"failed","error":"watcher exited with code ${EXIT_CODE}","finishedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
            mv /app/data/build-status.json.tmp /app/data/build-status.json || true
            # Supervisor runs as root; Eleventy's ok/building writer runs as cloudron.
            # chown so the cloudron-side writer never hits an ownership surprise.
            chown cloudron:cloudron /app/data/build-status.json 2>/dev/null || true
            echo "[eleventy-watcher] Crash captured in build-status.json"
        fi
    done
) &

# ─── Full-rebuild trigger on site-config / homepage changes ───
# The site-config admin writes site-config.json and homepage.json. The theme reads
# them via Eleventy GLOBAL DATA (_data/site.js, _data/homepageConfig.js) using fs,
# which Eleventy's --incremental watcher cannot attribute to any template — so an
# admin save (branding aside, which uses the directly-watched theme.css) does NOT
# propagate to rendered pages until a full rebuild. Watch these files' CONTENT
# and, on change, restart the Eleventy watcher; its next start does a full build
# that re-runs global data and re-renders every page with the new config.
(
    # site-config.json/homepage.json are the v3 artifacts. compositions/*.json are
    # the v4 composition artifacts (homepage, collection:default, posttype:default,
    # pages.json = PUBLISHED standalone pages, preview-pages.json = page preview).
    # ALL are consumed by Eleventy GLOBAL DATA (_data/*.mjs reading them via fs),
    # which the --incremental watcher cannot attribute to any template — so a write
    # does NOT propagate until a full rebuild. Restart the watcher on any change.
    # (Adding compositions/*.json fixes composed-PAGE publish + preview propagation;
    # previously only site-config.json/homepage.json were watched — Phase 7 gap.)
    # cv.json is written by @rmdes/indiekit-endpoint-cv and read by the theme's
    # _data/cv.js global (same fs-read pattern); since /cv is now a composed page
    # whose cv-* blocks read that global, a CV admin save also needs a full rebuild
    # to propagate (Phase 7a write-path move: was .indiekit/cv.json).
    # SIGNATURE IS A CONTENT HASH, NOT mtime. At every container start the
    # site-config and CV plugins rewrite these artifacts from MongoDB with
    # byte-identical content. That bumps mtime, so the old `stat -c %Y` signature
    # saw a "change" seconds after the first build and restarted the watcher —
    # making EVERY deploy/restart do TWO full builds (verified 2026-08-20:
    # rmendes ~160s x2; chardonsbleus 24.3s + 21.0s, 35.4s + 31.2s).
    # Hashing content ignores that idempotent boot rewrite while still catching a
    # real admin save. The `updatedAt` inside these files is the Mongo document's
    # timestamp, not a generation time, so unchanged data hashes equal.
    # md5sum prints "hash  path" per line, so add/delete/rename also move the
    # signature. Total watched payload is ~55 KB, so this is cheap at 8s.
    SIG_LAST=""
    while true; do
        # Hash EVERY json artifact in _data, not a hand-listed subset. The old
        # list missed loaded-plugins.json, block-catalog.json and categories.json,
        # and any future plugin artifact would have been missed too. The theme
        # watchIgnores this same set (eleventy.config.js), so this loop is the
        # SINGLE owner of artifact-driven rebuilds — previously Eleventy's watcher
        # and this trigger both fired on a real change and the pkill killed a
        # rebuild already in flight. `*.tmp` staging files do not match `*.json`,
        # so a half-written artifact can never enter the signature.
        SIG_NOW=$(md5sum \
            /app/data/content/_data/*.json \
            /app/data/content/_data/compositions/*.json \
            2>/dev/null | tr '\n' ',')
        if [ -n "$SIG_LAST" ] && [ "$SIG_NOW" != "$SIG_LAST" ]; then
            echo "==> [rebuild-trigger] site-config/homepage/composition artifact changed — restarting Eleventy watcher for a full rebuild"
            # Sentinel: tells the watcher supervisor this exit is intentional,
            # so the Phase 5 crash wrapper doesn't report it as a failed build.
            touch /tmp/.eleventy-intentional-restart
            pkill -f "node_modules/.bin/eleventy" 2>/dev/null || true
        fi
        SIG_LAST="$SIG_NOW"
        sleep 8
    done
) &

# Memory monitor — logs RSS for all Node.js processes every 10 minutes.
# Helps detect slow memory leaks over days. Output appears in `cloudron logs`.
# To analyze: cloudron logs --app rmendes.net | grep '\[mem-monitor\]'
(
    MONITOR_INTERVAL=600  # 10 minutes
    while true; do
        sleep $MONITOR_INTERVAL
        INDIEKIT_RSS=$(cat /proc/${INDIEKIT_PID}/status 2>/dev/null | grep ^VmRSS | awk '{print $2}')
        INDIEKIT_SWAP=$(cat /proc/${INDIEKIT_PID}/status 2>/dev/null | grep ^VmSwap | awk '{print $2}')
        # Find watcher PID dynamically (it may restart)
        WATCHER_PID=$(pgrep -f "eleventy.*--watch" 2>/dev/null | head -1)
        if [ -n "$WATCHER_PID" ]; then
            WATCHER_RSS=$(cat /proc/${WATCHER_PID}/status 2>/dev/null | grep ^VmRSS | awk '{print $2}')
            WATCHER_SWAP=$(cat /proc/${WATCHER_PID}/status 2>/dev/null | grep ^VmSwap | awk '{print $2}')
        else
            WATCHER_RSS="N/A"; WATCHER_SWAP="N/A"
        fi
        CGROUP_USED=$(cat /sys/fs/cgroup/memory.current 2>/dev/null)
        CGROUP_MB=$((CGROUP_USED / 1024 / 1024))
        echo "[mem-monitor] indiekit=${INDIEKIT_RSS}kB+${INDIEKIT_SWAP}kBswap eleventy=${WATCHER_RSS}kB+${WATCHER_SWAP}kBswap cgroup=${CGROUP_MB}MB"
    done
) &

# Indiekit watchdog — auto-restart on crash (e.g., OOM during Eleventy build)
echo "==> All services started, watching Indiekit..."
while true; do
    wait $INDIEKIT_PID
    EXIT_CODE=$?
    echo "==> Indiekit exited with code ${EXIT_CODE} — restarting in 5 seconds..."
    sleep 5

    # Restart Indiekit
    cd /app/code
    gosu cloudron:cloudron env NODE_OPTIONS="--max-old-space-size=1024" node node_modules/@indiekit/indiekit/bin/cli.js serve --config /app/data/config/indiekit.config.js &
    INDIEKIT_PID=$!

    # Wait for it to be ready before looping back to watch
    for i in {1..30}; do
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ | grep -q "200\|302"; then
            echo "==> Indiekit restarted successfully (PID ${INDIEKIT_PID})"
            break
        fi
        sleep 1
    done
done
