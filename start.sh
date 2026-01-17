#!/bin/bash

set -eu

echo "==> Ensure directories"
mkdir -p /app/data/config /app/data/content /app/data/uploads

# Create default config file on first run
if [[ ! -f /app/data/config/indiekit.config.js ]]; then
    echo "==> Creating default config on first run"
    cp /app/pkg/indiekit.config.js.template /app/data/config/indiekit.config.js
fi

# Create user env file for secrets on first run
if [[ ! -f /app/data/config/env.sh ]]; then
    echo "==> Creating env.sh for syndicator tokens"
    cat > /app/data/config/env.sh <<'ENVEOF'
# Add your tokens here and restart the app

# GitHub token (optional, for /github endpoint - get from Settings > Developer settings > Personal access tokens)
export GITHUB_TOKEN=""

# Bluesky app password (get from Settings > App Passwords)
export BLUESKY_PASSWORD=""

# Mastodon access token (get from Settings > Development > Applications)
export MASTODON_ACCESS_TOKEN=""
ENVEOF
fi

# Source user secrets
source /app/data/config/env.sh

# Indiekit core configuration
export MONGODB_URL="${CLOUDRON_MONGODB_URL}"
export PORT=3000

# Generate and persist SECRET if not exists (used for JWT signing)
if [[ ! -f /app/data/config/.secret ]]; then
    openssl rand -hex 32 > /app/data/config/.secret
fi
export SECRET="$(cat /app/data/config/.secret)"

# App URL from Cloudron
export CLOUDRON_APP_URL="${CLOUDRON_APP_ORIGIN}"

echo "==> Setting permissions"
chown -R cloudron:cloudron /app/data

cd /app/code

echo "==> Starting Indiekit on port ${PORT}"
exec gosu cloudron:cloudron node node_modules/@indiekit/indiekit/bin/cli.js serve --config /app/data/config/indiekit.config.js
