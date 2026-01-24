#!/bin/bash

set -eu

echo "==> Ensure directories"
mkdir -p /app/data/config /app/data/content /app/data/uploads /app/data/site /app/data/cache /app/data/images

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

# Build Eleventy site from /app/pkg/eleventy-site (where node_modules lives)
# Symlinks in Dockerfile point content/_site/.cache to /app/data
echo "==> Clearing stale site files"
rm -rf /app/data/site/*

# Create temporary placeholder so health checks don't fail during build
echo '<html><head><meta http-equiv="refresh" content="5"></head><body><p>Building site...</p></body></html>' > /app/data/site/index.html
chown cloudron:cloudron /app/data/site/index.html

echo "==> Building Eleventy site"
cd /app/pkg/eleventy-site
gosu cloudron:cloudron ./node_modules/.bin/eleventy --output=/app/data/site || {
    echo "==> Eleventy build failed, creating placeholder"
    mkdir -p /app/data/site
    echo "<html><body><h1>Blog coming soon</h1><p>Create your first post at <a href='/admin'>/admin</a></p></body></html>" > /app/data/site/index.html
}

echo "==> Setting permissions on generated site"
chown -R cloudron:cloudron /app/data

# Start Eleventy in watch mode to rebuild on content changes
echo "==> Starting Eleventy watcher for auto-rebuild"
gosu cloudron:cloudron ./node_modules/.bin/eleventy --watch --output=/app/data/site &

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
            SYNDICATION_TOKEN=$(cd /app/code && node -e "
                const jwt = require('jsonwebtoken');
                const token = jwt.sign(
                    { me: '$SYNDICATION_ORIGIN', scope: 'update' },
                    '$SYNDICATION_SECRET',
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

# Wait for Indiekit process (keeps container running)
echo "==> All services started, waiting for Indiekit..."
wait $INDIEKIT_PID
