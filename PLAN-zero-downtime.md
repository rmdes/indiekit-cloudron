# Plan: Zero-Downtime Eleventy Rebuilds

## Status: PENDING
## Created: 2025-02-17

---

## Problem

When the Cloudron container restarts (app update, crash recovery), `start.sh` wipes `/app/data/site/*` and runs a full Eleventy build (~9 minutes). During this window:
- The homepage shows a "Building site..." placeholder
- ALL post URLs return 404
- Search (pagefind) only partially works (preserved index, but HTML gone)
- RSS feeds are empty

Additionally, the Eleventy watcher runs without `--incremental`, meaning every content change triggers a near-full rebuild instead of a targeted partial rebuild.

## Solution

Two complementary changes:

1. **Atomic symlink swap** — Build to a timestamped release directory, then atomically swap the nginx root symlink. Old site serves throughout the build.
2. **Incremental watch mode** — Add `--incremental` to the watcher so content changes only rebuild affected pages.

## Architecture After

```
/app/data/
  releases/
    1708300000/          ← previous build (currently being served)
    1708400000/          ← new build in progress
  site → releases/1708300000   ← symlink, nginx root points here
  content/               ← user markdown (unchanged)
  cache/                 ← Eleventy cache (unchanged)
  uploads/               ← media files (unchanged)
```

**Container restart sequence:**
```
nginx starts → root=/app/data/site → symlink to LAST release → old site serves immediately
Indiekit starts → ready on :8080
Eleventy full build → writes to /app/data/releases/NEW/
Build completes → atomic symlink swap → nginx -s reload
Watcher starts with --watch --incremental
Cleanup old releases (keep 2 for rollback)
```

**Visitors experience:** Old content for ~9 min, then seamlessly new content. Zero 404s.

---

## Tasks

### Task 1: Rework start.sh build section

Replace the current "wipe and build" pattern with atomic release-based builds.

**Current (lines 192-218):**
```bash
rm -rf /app/data/site/*
echo 'Building site...' > /app/data/site/index.html
eleventy --output=/app/data/site
```

**New:**
```bash
# Create releases directory
mkdir -p /app/data/releases

# If no previous release exists (first-ever run), create placeholder
if [ ! -L /app/data/site ] && [ ! -d /app/data/site ]; then
    # Very first run — no symlink, no directory
    mkdir -p /app/data/releases/placeholder
    echo '<html>...</html>' > /app/data/releases/placeholder/index.html
    ln -s /app/data/releases/placeholder /app/data/site
elif [ -d /app/data/site ] && [ ! -L /app/data/site ]; then
    # Migration: /app/data/site is a real directory (from before this change)
    # Move its contents into a release, then replace with symlink
    MIGRATION_TS=$(date +%s)
    mv /app/data/site /app/data/releases/${MIGRATION_TS}
    ln -s /app/data/releases/${MIGRATION_TS} /app/data/site
fi

# At this point /app/data/site is a symlink → old release serves via nginx

# Build new release
RELEASE_TS=$(date +%s)
NEW_RELEASE="/app/data/releases/${RELEASE_TS}"
mkdir -p "${NEW_RELEASE}"

eleventy --output="${NEW_RELEASE}"

# Atomic swap: create temp symlink, then rename over current
ln -s "${NEW_RELEASE}" /app/data/site_tmp
mv -T /app/data/site_tmp /app/data/site

# Reload nginx to pick up new symlink target
nginx -s reload

# Cleanup: keep only 2 most recent releases
cd /app/data/releases && ls -1t | tail -n +3 | xargs -r rm -rf
```

**Key details:**
- `mv -T` is an atomic `rename(2)` syscall — the symlink is never missing
- Migration path handles the first deployment (existing `/app/data/site` directory gets converted to a release)
- First-ever run (no site at all) gets a placeholder release until build completes
- After swap, old release stays for rollback; cleanup keeps 2

**Files:** `start.sh`

### Task 2: Update Dockerfile symlinks

The Dockerfile creates `_site → /app/data/site` for Eleventy. Since `/app/data/site` becomes a symlink to a release directory, Eleventy's `_site` symlink needs to point to the build target, not the serve target.

**Current (line 86):**
```dockerfile
rm -rf /app/pkg/eleventy-site/_site && ln -s /app/data/site /app/pkg/eleventy-site/_site
```

**Change:** Keep this symlink as-is. It's fine — `_site → /app/data/site → /app/data/releases/TIMESTAMP/`. The double symlink resolves correctly. Eleventy writes through both links.

BUT — we need to ensure the build writes to `${NEW_RELEASE}` directly (via `--output=`), NOT through the `_site` symlink, because during the build the `_site` symlink still points to the OLD release.

**Action:** The `--output=${NEW_RELEASE}` flag in start.sh overrides the `_site` symlink, so Eleventy writes directly to the new release directory. The `_site` symlink is only used by the watcher (which correctly should write to the current/active release). No Dockerfile change needed.

**Files:** None (no change needed)

### Task 3: Update Dockerfile to create releases directory

Add `/app/data/releases` to the `mkdir -p` line in start.sh (already writable).

**Files:** `start.sh` (line 6)

### Task 4: Add --incremental to watcher

**Current (line 256):**
```bash
gosu cloudron:cloudron ./node_modules/.bin/eleventy --watch --output=/app/data/site
```

**New:**
```bash
gosu cloudron:cloudron ./node_modules/.bin/eleventy --watch --incremental --output=/app/data/site
```

The watcher uses `--output=/app/data/site` which resolves through the symlink to the current release. This is correct — incremental rebuilds should update the active release in-place.

**Files:** `start.sh`

### Task 5: Guard Eleventy hooks for incremental mode

The `eleventy.before` (OG images) and `eleventy.after` (Pagefind + WebSub) hooks currently run on every build event. With `--incremental`, they'd fire on every single post save — expensive and unnecessary.

**eleventy.before (OG image generation):**
```javascript
// Current:
eleventyConfig.on("eleventy.before", () => {
    execFileSync(process.execPath, [...ogCliArgs...]);
});

// New:
eleventyConfig.on("eleventy.before", ({ incremental }) => {
    if (incremental) return; // Skip OG generation on incremental builds
    execFileSync(process.execPath, [...ogCliArgs...]);
});
```

**eleventy.after (Pagefind + WebSub):**
```javascript
// Current:
eleventyConfig.on("eleventy.after", async ({ dir, runMode }) => {
    execFileSync("npx", ["pagefind", "--site", dir.output, ...]);
    // WebSub notification...
});

// New:
eleventyConfig.on("eleventy.after", async ({ dir, runMode, incremental }) => {
    if (incremental) return; // Skip indexing + notification on incremental builds
    execFileSync("npx", ["pagefind", "--site", dir.output, ...]);
    // WebSub notification...
});
```

**Trade-off:** New posts won't be searchable via Pagefind until the next full rebuild (container restart). This is acceptable because:
- Posts are immediately browseable via Eleventy's collection pages
- Search indexing was already delayed in the old system (only ran after full build)
- A periodic pagefind re-index could be added later if needed

**Files:** `indiekit-eleventy-theme/eleventy.config.js` (this is the SOURCE OF TRUTH — edit in the theme repo, not in the submodule)

### Task 6: Handle pagefind preservation

Currently start.sh preserves the pagefind index from the old `/app/data/site/` by moving it to `/tmp`. With the atomic swap approach, the old release directory already contains pagefind — it's preserved automatically because we don't delete the old release until cleanup.

**The new release needs pagefind too.** Since the `eleventy.after` hook runs pagefind after the full build, the new release will have its own fresh pagefind index. No special preservation logic needed.

**Remove the current pagefind preservation code (lines 193-201).** It's no longer needed.

**Files:** `start.sh`

### Task 7: Clear Eleventy fetch cache correctly

Currently (line 204):
```bash
rm -rf /app/data/cache/eleventy-fetch-*
```

This clears the cache to force fresh API data on rebuild. Keep this behavior — it ensures the new release has fresh external data (GitHub, Last.fm, etc.). No change needed.

**Files:** None (keep as-is)

### Task 8: Update CLAUDE.md

Update the anti-pattern list and critical patterns sections:
- Remove "Clear Stale Site Files Before Build" pattern (no longer applicable)
- Add "Atomic Release Swap" pattern documentation
- Update the architecture diagram showing releases/symlink structure
- Document rollback procedure: `ln -sfn /app/data/releases/OLD_TIMESTAMP /app/data/site && nginx -s reload`

**Files:** `CLAUDE.md`

---

## Files Modified

| File | Repo | Action |
|------|------|--------|
| `start.sh` | indiekit-cloudron | Rework build section (Tasks 1, 3, 4, 6) |
| `eleventy.config.js` | indiekit-eleventy-theme | Guard hooks (Task 5) |
| `CLAUDE.md` | indiekit-cloudron | Update docs (Task 8) |

**Not modified:**
- `Dockerfile` — no changes needed (symlinks work through double resolution)
- `nginx.conf.rmendes` / `nginx.conf.template` — no changes needed (no `open_file_cache`, symlinks followed by default)

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| `mv -T` not available | It's GNU coreutils, always present on Cloudron (Debian-based) |
| Double symlink resolution (`_site → site → releases/X`) | Tested: Linux resolves chains transparently |
| First deployment after change (migration from directory to symlink) | Explicit migration path in Task 1 |
| Watcher writes to wrong release | Watcher uses `--output=/app/data/site` which resolves through symlink to current release |
| Disk space (2 releases) | Each release is ~50-100MB, total ~200MB max. Cloudron volumes handle this. |
| Pagefind stale during incremental | Acceptable trade-off — posts browseable immediately, searchable after next full build |

---

## Verification

1. **Cold start (no previous data):** Container creates placeholder, builds, swaps. Site works after build.
2. **Warm restart (existing releases):** Old site serves immediately. New build completes. Swap is seamless. No 404s.
3. **New post via Micropub:** Watcher picks up change, incremental rebuild runs in <1s, post appears.
4. **Search after restart:** Pagefind index in new release works. Search finds all content.
5. **Rollback:** `ln -sfn /app/data/releases/OLD /app/data/site && nginx -s reload` restores previous version.

---

## What This Doesn't Fix

- **Cloudron app updates** (`cloudron update`): Container stops entirely for 2-4 min. This is a Cloudron platform limitation. However, the atomic swap means the NEXT startup serves old content immediately instead of showing "Building site..." for 9 minutes.
- **Very first deployment** (no content at all): Still shows placeholder until build completes. Unavoidable cold start.
