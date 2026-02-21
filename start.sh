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

# Update config from bundled version (supports personal overrides via .rmendes pattern)
# Always update to ensure config changes are applied on deploy
if [[ -f /app/pkg/indiekit.config.js ]]; then
    echo "==> Updating Indiekit config from bundled version"
    cp /app/pkg/indiekit.config.js /app/data/config/indiekit.config.js
elif [[ ! -f /app/data/config/indiekit.config.js ]]; then
    echo "==> Creating default config from template (first run)"
    cp /app/pkg/indiekit.config.js.template /app/data/config/indiekit.config.js
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

# Or set all social links manually (overrides auto-generation from handles above)
# Format: "Name|URL|icon,Name|URL|icon"
# Example: "GitHub|https://github.com/user|github,Mastodon|https://mastodon.social/@user|mastodon"
export SITE_SOCIAL=""
ENVEOF
fi

# Source user secrets
source /app/data/config/env.sh

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
mkdir -p /run/nginx-client-body /run/nginx-proxy /run/nginx-fastcgi /run/nginx-uwsgi /run/nginx-scgi

echo "==> Starting nginx on port 3000"
nginx -c /run/nginx.conf &

# Start Indiekit in background first (so API is available for Eleventy build)
echo "==> Starting Indiekit on port ${PORT}"
cd /app/code
gosu cloudron:cloudron node node_modules/@indiekit/indiekit/bin/cli.js serve --config /app/data/config/indiekit.config.js &
INDIEKIT_PID=$!

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

# ─── Start background pollers early (they only need Indiekit, not Eleventy) ───

# Start syndication background process
# Polls the syndicate endpoint every 2 minutes to process pending syndications
echo "==> Starting syndication background process"
(
    echo "[syndication] Starting auto-syndication polling"
    while true; do
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

echo "==> Clearing Eleventy fetch cache (force fresh API data)"
rm -rf /app/data/cache/eleventy-fetch-*

# Build new release to a timestamped directory
RELEASE_TS=$(date +%s)
NEW_RELEASE="/app/data/releases/${RELEASE_TS}"
mkdir -p "${NEW_RELEASE}"
chown cloudron:cloudron "${NEW_RELEASE}"

echo "==> Building Eleventy site to ${NEW_RELEASE}"
cd /app/pkg/eleventy-site
# Node.js heap: container has 3GB, Indiekit uses ~400MB at rest
# Eleventy needs headroom for OG images, image transforms, and pagefind (all in-process)
export NODE_OPTIONS="--max-old-space-size=2048"
INITIAL_BUILD_OK=false
# Pagefind runs inside Eleventy's eleventy.after hook (non-incremental builds only)
gosu cloudron:cloudron ./node_modules/.bin/eleventy --output="${NEW_RELEASE}" && INITIAL_BUILD_OK=true || {
    echo "==> Eleventy build failed (likely OOM-killed)"
}

# Only swap if build succeeded — keep serving the old release on failure
if [ "$INITIAL_BUILD_OK" = true ]; then
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

    # Cleanup: keep only 2 most recent releases for rollback capability
    echo "==> Cleaning up old releases (keeping 2)"
    cd /app/data/releases && ls -1t | tail -n +3 | xargs -r rm -rf
else
    echo "==> Build failed, keeping previous release: ${CURRENT_RELEASE}"
    # Clean up the failed release directory
    rm -rf "${NEW_RELEASE}"
fi

# Start Eleventy in watch+incremental mode to rebuild only affected pages on content changes
# Wrapped in a supervisor loop that restarts on crash with exponential backoff
# The watcher writes to /app/data/site (current release via symlink)
echo "==> Starting Eleventy watcher for auto-rebuild"
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

        # Use absolute path — gosu's exec may not resolve relative paths from subshell cwd
        gosu cloudron:cloudron /app/pkg/eleventy-site/node_modules/.bin/eleventy \
            --watch --incremental --output=/app/data/site
        EXIT_CODE=$?
        echo "[eleventy-watcher] Watcher exited with code $EXIT_CODE at $(date '+%Y-%m-%d %H:%M:%S')"
    done
) &

# Wait for Indiekit process (keeps container running)
echo "==> All services started, waiting for Indiekit..."
wait $INDIEKIT_PID
