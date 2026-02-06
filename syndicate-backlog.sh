#!/bin/bash
#
# syndicate-backlog.sh - Process all pending syndications
#
# Runs inside the Cloudron container to syndicate all posts that have
# mp-syndicate-to set but haven't been fully syndicated yet.
#
# Usage:
#   cloudron exec --app rmendes.net -- bash /app/pkg/syndicate-backlog.sh
#
# This script bypasses the upstream .limit(1) bug by calling the syndicate
# endpoint with source_url for each individual post. The findOne query used
# for source_url lookups doesn't have the broken syndication filter.
#
# Safe to run multiple times - syndicateToTargets() checks hasSyndicationUrl()
# and skips targets that already have a syndication URL.

set -euo pipefail

# Configuration
DELAY_BETWEEN_POSTS=5  # seconds between API calls to avoid rate limits
PORT=8080
ORIGIN="${CLOUDRON_APP_ORIGIN:-https://rmendes.net}"

echo "==> Syndicate Backlog Processor"
echo "    Origin: ${ORIGIN}"
echo ""

# Read SECRET for JWT signing
if [[ ! -f /app/data/config/.secret ]]; then
    echo "ERROR: /app/data/config/.secret not found. Is Indiekit running?"
    exit 1
fi
SECRET=$(cat /app/data/config/.secret)

# Query MongoDB for all posts with mp-syndicate-to
echo "==> Querying MongoDB for posts with pending syndication targets..."
MONGO_URL="${MONGODB_URL:-${CLOUDRON_MONGODB_URL:-}}"
if [[ -z "$MONGO_URL" ]]; then
    echo "ERROR: No MongoDB URL found in environment"
    exit 1
fi

# Get all post URLs that have mp-syndicate-to set (regardless of syndication status)
POST_URLS=$(mongosh "$MONGO_URL" --quiet --eval '
    const posts = db.posts.find(
        { "properties.mp-syndicate-to": { $exists: true } },
        { "properties.url": 1, _id: 0 }
    ).toArray();
    posts.forEach(p => {
        if (p.properties && p.properties.url) {
            print(p.properties.url);
        }
    });
')

if [[ -z "$POST_URLS" ]]; then
    echo "==> No posts found with pending syndication targets"
    exit 0
fi

# Count posts
POST_COUNT=$(echo "$POST_URLS" | wc -l)
echo "==> Found ${POST_COUNT} post(s) with mp-syndicate-to"
echo ""

# Process each post
CURRENT=0
SUCCESS=0
FAILED=0

while IFS= read -r url; do
    CURRENT=$((CURRENT + 1))
    echo "--- Post ${CURRENT}/${POST_COUNT}: ${url}"

    # Generate a fresh JWT token for each request
    TOKEN=$(cd /app/code && node -e "
        const jwt = require('jsonwebtoken');
        const token = jwt.sign(
            { me: '${ORIGIN}', scope: 'update' },
            '${SECRET}',
            { expiresIn: '5m' }
        );
        console.log(token);
    " 2>/dev/null)

    if [[ -z "$TOKEN" ]]; then
        echo "    ERROR: Failed to generate JWT token"
        FAILED=$((FAILED + 1))
        continue
    fi

    # URL-encode the source_url parameter
    ENCODED_URL=$(node -e "console.log(encodeURIComponent('${url}'))" 2>/dev/null)

    # Call the syndicate endpoint with source_url to target this specific post
    RESULT=$(curl -s -X POST \
        "http://localhost:${PORT}/syndicate?source_url=${ENCODED_URL}&token=${TOKEN}" \
        -H "Content-Type: application/json" \
        --max-time 60 2>&1)

    echo "    Result: ${RESULT}"

    # Check for success
    if echo "$RESULT" | grep -q '"success"'; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
    fi

    # Delay between posts to avoid rate limits
    if [[ $CURRENT -lt $POST_COUNT ]]; then
        echo "    Waiting ${DELAY_BETWEEN_POSTS}s before next post..."
        sleep "$DELAY_BETWEEN_POSTS"
    fi

    echo ""
done <<< "$POST_URLS"

echo "==> Backlog processing complete"
echo "    Total:   ${POST_COUNT}"
echo "    Success: ${SUCCESS}"
echo "    Failed:  ${FAILED}"
