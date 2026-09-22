#!/bin/bash

set -eu

echo "==> Ensure directories"
mkdir -p /app/data/config /app/data/content /app/data/uploads /app/data/releases /app/data/cache /app/data/images /app/data/og /app/data/img

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

# Initial build DISABLED — build-loop.sh owns the first build now.
#
# This block is the remains of the atomic release-swap design (4f37a16), disabled
# on 2026-04-04 (913fc7b). Its stated reason — "Eleventy 3.9GB peak + Indiekit
# exceeds the 4GB cgroup" — is stale in BOTH halves: the cgroup is 5120MB, and
# that peak included the OG excerpt retention fixed on 2026-09-12 (V8 SlicedString
# pinning whole pages; 764MB -> 1MB measured). A one-shot full build now peaks at
# ~2.1GB. Keeping it disabled is still correct, but for a different reason:
# build-loop.sh already does a full build at container start, so re-enabling this
# would just build the site twice per boot.
#
# Restoring the SWAP itself (build to a fresh dir, atomic symlink rename) is a
# real option and is tracked separately. Two things must be solved first, both
# verified 2026-09-16: `cp -al` seeding is UNSAFE because Eleventy writes with
# fs.writeFile, which truncates in place and therefore mutates the live release
# through the hardlink; and a virgin release dir makes eleventy-img regenerate
# every image, so img/ and og/ want to move to persistent storage served by an
# nginx alias before a swap is worth it.
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
    # Note: readiness signal is NOT created here — build-loop.sh runs a full
    # build on start and the eleventy.after hook creates the signal file when
    # that build completes. This ensures plugins don't start until the system
    # is truly stable (build finished).
fi

# Node options for the Eleventy build process (build-loop.sh spawns it).
#
# --expose-gc lets eleventy.config.js call global.gc() after each build, forcing
# V8 to hand freed pages back to the OS via madvise(MADV_DONTNEED). Less critical
# now that every build is a process that exits — exiting returns everything —
# but the post-build heap log it enables is still the main memory diagnostic.
# --heapsnapshot-signal=SIGUSR2: on-demand heap snapshot analysis.
#
# HEAP AT 3328 — READ THIS BEFORE CHANGING IT.
#
# This number has been edited twelve times across eight months, and twice in one
# day on 2026-09-12 it was LOWERED to 2560 by comparing the wrong two figures,
# taking the site down both times. The trap: `.eleventy-mem.log` records
# `post-pagefind` AFTER the forced GC at the END of a build (~1280MB under the
# old watcher), which looks like plenty of headroom. The number that binds is
# the PEAK during template rendering.
#
# What changed: the long-lived `--watch --incremental` watcher held every
# rendered page in memory for incremental diffing — 707MB of large_object_space
# in the Mar 2026 heap snapshot — and its peak climbed with each successive
# build (2076MB median on a process's 1st build, 3491MB p90 by its 10th).
# One-shot full builds retain none of that. Measured on a 3,443-page build:
# heap 552/801MB, versus 1292/1466MB for the same site under the watcher.
#
# So 3328 is now generous rather than marginal. It is left high on purpose: a
# cap costs nothing until it binds, and the cost of getting it wrong downward is
# a silent outage. Do not "reclaim" it.
#
# Budget of the 5120MB cgroup: build 3328 + Indiekit ~600 + og-cli batch ~460
# + nginx/redis ~30 = ~4400, leaving ~700MB margin.
export NODE_OPTIONS="--max-old-space-size=3328 --expose-gc --heapsnapshot-signal=SIGUSR2 --diagnostic-dir=/tmp"

# ─── Generated media lives OUTSIDE the Eleventy output ───
# Responsive images and OG cards are expensive to produce and identical between
# builds. Writing them into the output makes the output expensive to recreate,
# which is what blocks an atomic release swap: a release must be built from
# EMPTY (seeding from the previous release with hardlinks is not an option —
# Eleventy writes with fs.writeFile, which truncates in place and would mutate
# the live release through the link), and from empty eleventy-img regenerates
# every file.
#
# Both are safe to share across releases: img/ filenames are content-addressed
# (hash-width-format), so a changed source yields a different name; og/ cards
# already live in the persistent .cache/og and were merely copied in. nginx
# serves both with an `alias`. The og copy target is a separate PUBLIC dir
# rather than .cache/og itself, so the build cache — manifest included — stays
# off the public surface.
export OG_PUBLIC_DIR=/app/data/og
export IMG_PUBLIC_DIR=/app/data/img
chown cloudron:cloudron /app/data/og /app/data/img 2>/dev/null || true

# One-time migration: seed the new dirs from the current output so the first
# build after this change does not have to re-run Sharp over every image. Only
# when empty, so it costs one `ls` on every subsequent boot. cp -n never
# clobbers, so a partially-seeded dir completes rather than being rewritten.
if [ -d /app/data/site/img ] && [ -z "$(ls -A /app/data/img 2>/dev/null)" ]; then
    echo "==> Seeding ${IMG_PUBLIC_DIR} from the current release (one-time)"
    cp -rn /app/data/site/img/. /app/data/img/ 2>/dev/null || true
    chown -R cloudron:cloudron /app/data/img 2>/dev/null || true
    echo "==> Seeded $(find /app/data/img -type f | wc -l) image file(s)"
fi
if [ -d /app/data/site/og ] && [ -z "$(ls -A /app/data/og 2>/dev/null)" ]; then
    echo "==> Seeding ${OG_PUBLIC_DIR} from the current release (one-time)"
    # Cards ONLY. The previous output directory also holds manifest.json,
    # because .cache/og used to be passthrough-copied wholesale — which is how
    # /og/manifest.json came to be publicly served, listing every card's slug
    # and title including drafts and deleted posts. Copying *.png keeps the
    # build manifest out of the published mirror.
    find /app/data/site/og -maxdepth 1 -name '*.png' -exec cp -n {} /app/data/og/ \; 2>/dev/null || true
    chown -R cloudron:cloudron /app/data/og 2>/dev/null || true
    echo "==> Seeded $(find /app/data/og -type f | wc -l) OG card(s)"
fi
# Syndication webhook — the theme's eleventy.after hook calls this once a build
# completes, cutting syndication latency from the poller's ~2min to ~5s.
export SYNDICATE_WEBHOOK_URL="http://localhost:8080/syndicate"
export SYNDICATE_SECRET_FILE="/app/data/config/.secret"
# ─── Eleventy build loop ───
# Replaces `eleventy --watch --incremental`, which ran as ONE long-lived process
# for the life of the container and was the direct cause of three separate
# classes of failure: silently dropped posts (an upstream crash that leaves the
# watcher alive), memory that grows with the number of incremental builds a
# process has done, and a supervisor that could only see a process that EXITED.
# build-loop.sh carries the full reasoning and the measurements.
#
# It also absorbs the old rebuild-trigger loop: site-config/composition artifact
# changes are one of its two change detectors rather than a separate watcher
# that pkill'd a build already in flight.
echo "==> Starting Eleventy build loop"
/app/pkg/build-loop.sh &

# ─── Stuck-build watchdog ───
# Second line of defence. The build loop above notices a build that EXITS
# non-zero; this notices one that never exits at all. The failure it was written
# for was the --watch --incremental watcher, which caught its own build errors
# and kept watching: `Wrote 0 files in 6.02 seconds` then `Watching…`, a live
# idle process with nothing wrong from outside. One-shot builds make that
# specific trap far less likely, but a build that hangs (a wedged network read,
# a Sharp deadlock) would still stall the loop forever with no signal.
# On 2026-09-15 rmendes sat in the watcher version of this for 24 HOURS — six
# builds started, none finished, five posts written to content/ that 404'd.
# consecutiveFailures stayed 0 (nothing crashed) and /health/build.json still
# said `ok` from the previous day. Nothing in the container noticed.
#
# Root cause is upstream (@11ty/eleventy 3.1.2 AND 3.1.6): the synchronous
# TemplateContent.isFileRelevantToThisTemplate() dereferences `this.engine` on
# a Template that has not been async-initialised and throws `templateRender has
# not yet initialized`. This does NOT fix that — it bounds the damage from ~24h
# to ~15min while the build architecture is reworked.
#
# The overdue THRESHOLD lives in the theme (lib/build-watchdog.mjs), not here:
# it is max(4 x lastOkDurationSeconds, 1800s), self-calibrating per site and
# unit-tested against the real build-duration distribution. Deliberately far
# more conservative than site-config's isStuckBuild() banner rule
# (max(2 x lastOk, 120s)) — that draws a warning, this KILLS A BUILD, and
# rmendes's full builds run to 461s. Exit code 10 = overdue.
#
# NO intentional-restart sentinel is set: a wedge IS a failure and must reach
# build-status.json and /health/build.json through the supervisor's crash
# branch, or the outage stays invisible to monitoring a second time.
(
    set +e  # the probe exits 10 on purpose; errexit would kill this loop
    WATCHDOG_INTERVAL=60
    while true; do
        sleep $WATCHDOG_INTERVAL
        gosu cloudron:cloudron node -e '
          import("/app/pkg/eleventy-site/lib/build-watchdog.mjs")
            .then(({ inspectBuildStatus }) => {
              const r = inspectBuildStatus();
              if (!r.overdue) return;
              console.log(
                `[build-watchdog] Build ${r.status?.buildId ?? "?"} has been "building" for ` +
                `${r.elapsedSeconds}s (threshold ${r.thresholdSeconds}s) — build presumed wedged`,
              );
              process.exit(10);
            })
            .catch((error) => console.warn("[build-watchdog] " + error.message));
        '
        if [ $? -eq 10 ]; then
            echo "[build-watchdog] Restarting Eleventy watcher to recover"
            pkill -f "node_modules/.bin/eleventy" 2>/dev/null || true
        fi
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
