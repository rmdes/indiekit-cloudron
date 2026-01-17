#!/bin/bash

set -eu

echo "==> Ensure directories"
mkdir -p /app/data/config /app/data/content /app/data/uploads /app/data/site /app/data/eleventy

# Create default config file on first run
if [[ ! -f /app/data/config/indiekit.config.js ]]; then
    echo "==> Creating default config on first run"
    cp /app/pkg/indiekit.config.js.template /app/data/config/indiekit.config.js
fi

# Initialize Eleventy site on first run
if [[ ! -f /app/data/eleventy/eleventy.config.js ]]; then
    echo "==> Initializing Eleventy site"
    cp -r /app/pkg/eleventy-site/* /app/data/eleventy/
    # Create symlink for content directory
    ln -sf /app/data/content /app/data/eleventy/content
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

# Build Eleventy site initially
echo "==> Building Eleventy site"
cd /app/data/eleventy
gosu cloudron:cloudron /app/code/node_modules/.bin/eleventy --output=/app/data/site || {
    echo "==> Eleventy build failed, creating placeholder"
    mkdir -p /app/data/site
    echo "<html><body><h1>Blog coming soon</h1><p>Create your first post at <a href='/admin'>/admin</a></p></body></html>" > /app/data/site/index.html
}

# Start Eleventy in watch mode to rebuild on content changes
echo "==> Starting Eleventy watcher for auto-rebuild"
gosu cloudron:cloudron /app/code/node_modules/.bin/eleventy --watch --output=/app/data/site &

# Setup nginx
cp /app/pkg/nginx.conf /run/nginx.conf
mkdir -p /run/nginx-client-body /run/nginx-proxy /run/nginx-fastcgi /run/nginx-uwsgi /run/nginx-scgi

echo "==> Starting nginx on port 3000"
nginx -c /run/nginx.conf &

cd /app/code

echo "==> Starting Indiekit on port ${PORT}"
exec gosu cloudron:cloudron node node_modules/@indiekit/indiekit/bin/cli.js serve --config /app/data/config/indiekit.config.js
