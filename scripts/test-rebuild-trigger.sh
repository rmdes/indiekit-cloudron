#!/usr/bin/env bash
# Self-check for start.sh's rebuild-trigger signature.
#
# Contract (must stay in sync with the theme's eleventy.config.js watchIgnores):
#   * every *.json artifact under _data is in the signature — the theme ignores
#     them, so this trigger is the ONLY thing that propagates a real edit;
#   * a byte-identical rewrite (the boot rehydration from MongoDB) must NOT fire;
#   * *.css is NOT in the signature — theme.css/critical.css stay watched by
#     Eleventy so branding saves propagate as assets without a full rebuild;
#   * *.tmp staging files never enter the signature, so a half-written artifact
#     can't trigger a rebuild or be read mid-write.
#
# Run: scripts/test-rebuild-trigger.sh
set -uo pipefail

D=$(mktemp -d)
cleanup() {
    rm "$D"/*.json "$D"/*.css "$D"/*.tmp "$D"/compositions/*.json 2>/dev/null
    rmdir "$D/compositions" "$D" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$D/compositions"
# The full production artifact set (rmendes, 2026-08-20).
for f in site-config homepage cv block-catalog categories loaded-plugins; do
    echo "{\"$f\":1}" > "$D/$f.json"
done
for f in homepage collection-default posttype-default pages \
         preview-draft preview-homepage preview-listing preview-pages; do
    echo "{\"$f\":1}" > "$D/compositions/$f.json"
done
echo "body{color:red}" > "$D/theme.css"
echo "body{margin:0}"  > "$D/critical.css"

# Mirrors the SIG_NOW expression in start.sh.
sig() { md5sum "$D"/*.json "$D"/compositions/*.json 2>/dev/null | tr '\n' ','; }

fail=0
check() { # check <desc> <same|diff> <before> <after>
    if [ "$2" = same ] && [ "$3" != "$4" ]; then echo "FAIL: $1 (signature moved)"; fail=1
    elif [ "$2" = diff ] && [ "$3" = "$4" ]; then echo "FAIL: $1 (signature did not move)"; fail=1
    else echo "ok: $1"; fi
}

# 1. The boot rehydration: same bytes, new mtime. Must NOT trigger. (The bug.)
BEFORE=$(sig); sleep 1
for f in site-config homepage cv block-catalog categories loaded-plugins; do
    echo "{\"$f\":1}" > "$D/$f.json"
done
touch "$D/compositions/"*.json
check "idempotent boot rewrite of every artifact does not trigger" same "$BEFORE" "$(sig)"

# 2. Every artifact must be covered — including the three the old hand-written
#    list missed (block-catalog, categories, loaded-plugins).
for f in site-config homepage cv block-catalog categories loaded-plugins; do
    BEFORE=$(sig); echo "{\"$f\":2}" > "$D/$f.json"
    check "content change in $f.json triggers" diff "$BEFORE" "$(sig)"
done
BEFORE=$(sig); echo '{"changed":1}' > "$D/compositions/pages.json"
check "content change in compositions/pages.json triggers" diff "$BEFORE" "$(sig)"

# 3. CSS is Eleventy's job, not the trigger's — must not restart the watcher.
BEFORE=$(sig); echo "body{color:blue}" > "$D/theme.css"; echo "body{margin:1px}" > "$D/critical.css"
check "css change does NOT trigger (Eleventy watches it)" same "$BEFORE" "$(sig)"

# 4. Staging files must be invisible to the signature.
BEFORE=$(sig); echo '{"partial":' > "$D/site-config.json.a1b2c3.tmp"
check "tmp staging file does NOT trigger" same "$BEFORE" "$(sig)"

# 5. Add / remove still propagate.
BEFORE=$(sig); echo '{"new":1}' > "$D/compositions/collection-blog.json"
check "added artifact triggers" diff "$BEFORE" "$(sig)"
BEFORE=$(sig); rm "$D/compositions/collection-blog.json"
check "removed artifact triggers" diff "$BEFORE" "$(sig)"

if [ $fail -eq 0 ]; then echo "PASS"; else echo "FAILED"; exit 1; fi
