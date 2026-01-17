#!/bin/bash

set -eu

echo "==> Ensure directories"
mkdir -p /app/data/config /app/data/uploads

# Create default config file on first run
if [[ ! -f /app/data/config/indiekit.config.js ]]; then
    echo "==> Creating default config on first run"
    cp /app/pkg/indiekit.config.js.template /app/data/config/indiekit.config.js
    echo ""
    echo "=============================================="
    echo "IMPORTANT: Edit your configuration file at:"
    echo "/app/data/config/indiekit.config.js"
    echo "=============================================="
    echo ""
fi

# Create user env file for secrets on first run
if [[ ! -f /app/data/config/env.sh ]]; then
    echo "==> Creating env.sh for user secrets"
    cat > /app/data/config/env.sh <<'ENVEOF'
# Add your secrets here - this file is sourced before starting Indiekit
# These environment variables are used by Indiekit plugins

# GitHub store (required)
export GITHUB_TOKEN=""

# Bluesky syndicator (optional)
# export BLUESKY_PASSWORD=""

# Mastodon syndicator (optional)
# export MASTODON_ACCESS_TOKEN=""

# Other stores/syndicators (uncomment as needed)
# export GITLAB_TOKEN=""
# export GITEA_TOKEN=""
# export BITBUCKET_PASSWORD=""
# export FTP_USER=""
# export FTP_PASSWORD=""
# export S3_ACCESS_KEY=""
# export S3_SECRET_KEY=""
# export INTERNET_ARCHIVE_ACCESS_KEY=""
# export INTERNET_ARCHIVE_SECRET_KEY=""
# export WEBMENTION_IO_TOKEN=""
ENVEOF
fi

# Source user secrets
source /app/data/config/env.sh

# Indiekit core configuration (mongodbUrl in config reads from this)
export MONGODB_URL="${CLOUDRON_MONGODB_URL}"
export PORT=3000

# App URL from Cloudron (useful in config)
export CLOUDRON_APP_URL="${CLOUDRON_APP_ORIGIN}"

# Mail configuration (if sendmail addon is used)
if [[ -n "${CLOUDRON_MAIL_SMTP_SERVER:-}" ]]; then
    export MAIL_SMTP_HOST="${CLOUDRON_MAIL_SMTP_SERVER}"
    export MAIL_SMTP_PORT="${CLOUDRON_MAIL_SMTP_PORT}"
    export MAIL_SMTP_USER="${CLOUDRON_MAIL_SMTP_USERNAME}"
    export MAIL_SMTP_PASS="${CLOUDRON_MAIL_SMTP_PASSWORD}"
    export MAIL_FROM="${CLOUDRON_MAIL_FROM}"
fi

echo "==> Setting permissions"
chown -R cloudron:cloudron /app/data

cd /app/code

echo "==> Starting Indiekit on port ${PORT}"
exec gosu cloudron:cloudron node node_modules/@indiekit/indiekit/bin/cli.js serve --config /app/data/config/indiekit.config.js
