# Deploying a new site

Operator-facing companion to [`CLAUDE.md`](../CLAUDE.md). Read that file first if you want exhaustive architectural reference. This guide is the walking-through-it manual for getting a new site onto a Cloudron server and keeping the deploy loop tight.

Audience: operator-as-developer. You know git, Docker, npm, and shell. You do not know this stack's specific quirks. Those are here.

> **Workspace note.** The three repos this guide names — `indiekit-cloudron`, `indiekit-eleventy-theme`, and `indiekit-endpoint-site-config` — are all public on GitHub under [github.com/rmdes](https://github.com/rmdes). The only private bits are the `sites/` overlay directories and `*.rmendes`-style files at the repo root; both are gitignored. Push the three public repos as part of the normal deploy loop. See [`feedback_repo_visibility.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_repo_visibility.md) for the full table.

---

## 1. Overview

### What this stack is

Three runtime processes inside one Cloudron container:

| Process | Port | Role |
|---------|------|------|
| **nginx** | 3000 (Cloudron entry) | Static file server + reverse proxy. Serves the Eleventy build from `/app/data/site/` (a symlink to a timestamped release). Proxies admin routes to Indiekit on `:8080`. |
| **Indiekit** | 8080 (internal) | Node.js app. Handles Micropub, IndieAuth, the admin UI, all `@rmdes/*` plugin endpoints (site-config, comments, conversations, ActivityPub, syndication, etc.). |
| **Eleventy** | (no port) | Static site generator running in `--watch --incremental` mode. Rebuilds HTML when content or theme files change. Writes to a new timestamped release directory, then atomic-swaps the `/app/data/site` symlink and reloads nginx. |

Plus background tasks: syndication poller (every 2 min), webmention sender (every 5 min), memory monitor (every 10 min). All managed by [`start.sh`](../start.sh).

### Three repos, one plugin, one submodule

| Repo | What it ships | Where it lives |
|------|---------------|----------------|
| **indiekit-cloudron** | The Cloudron package: Dockerfile, Makefile, CloudronManifest, start.sh, nginx config | This repo |
| **indiekit-eleventy-theme** | The single canonical Eleventy theme (Nunjucks templates, Tailwind CSS, `_data/*.js`) | Git submodule at `eleventy-site/` |
| **@rmdes/indiekit-endpoint-site-config** | The 12-control theming admin plugin (palette, semantic roles, mode, version history) | Installed via `npm install` in the Dockerfile, source at [`github.com/rmdes/indiekit-endpoint-site-config`](https://github.com/rmdes/indiekit-endpoint-site-config) |

One theme. One plugin. Many sites. Per-site variance lives in two places only:
1. `sites/<name>/config/` overlay files (gitignored, local only)
2. MongoDB `siteConfig.primary` document (written by the theming admin)

### Data flow for a theming change

```
Admin clicks Save in /site-config/branding
   |
   v
site-config plugin writes:
   /app/data/content/_data/theme.css          (CSS custom properties)
   /app/data/content/_data/critical.css       (above-the-fold rules)
   /app/data/content/_data/site-config.json   (structured identity/layout)
   |
   v
Plugin also writes the new document into MongoDB siteConfig.primary
(plus pushes a snapshot into the version history array)
   |
   v
Eleventy watcher sees a file change in content/_data/
   |
   v
Theme templates (theme.css.njk -> /css/theme.css; critical via inline filter)
re-render with the new values via inlineFile()
   |
   v
Eleventy writes a new timestamped release directory under /app/data/releases/
   |
   v
start.sh / eleventy.after hook atomic-swaps /app/data/site symlink
nginx -s reload
   |
   v
Public site serves the new CSS on next request
```

The plugin never writes to `/app/code/` or `/app/pkg/` — those are read-only at runtime. All runtime writes go to `/app/data/*`. This is the single most-tripped-over rule in this stack. See [`feedback_cloudron_writable_paths.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_cloudron_writable_paths.md).

### Prerequisites

You need:

- A Cloudron server you can `cloudron login` into. Self-hosted or cloudron.io managed; either works.
- A domain (or subdomain) you can point at that Cloudron server.
- A working clone of this repo with submodule initialized:
  ```
  git clone https://github.com/rmdes/indiekit-cloudron.git
  cd indiekit-cloudron
  make init        # runs git submodule update --init --recursive
  ```
- `gh` CLI logged in if you want to push to the three GitHub repos as part of the deploy loop.
- npm publish access for the `@rmdes` scope **only if** you intend to change plugin source. Plain deploys don't need it.

---

## 2. Multi-Cloudron context switching

The `cloudron` CLI is context-bound to one server. If you have more than one (a self-hosted box plus a managed Cloudron, or staging vs prod), the wrong context will silently deploy to the wrong server. A wrong deploy is hard to undo — there is no `cloudron undeploy`.

```bash
# Who am I logged into?
cloudron list                     # lists known servers; the active one has a marker

# List the active context's apps
cloudron status                   # shows current server URL + version

# Switch context
cloudron login my-server.example.com

# Or, log out and re-login
cloudron logout
cloudron login other-server.example.com
```

**Habits that prevent disasters:**

1. Run `cloudron status` before any `cloudron build` or `cloudron update`. The output's first line shows which server you're talking to. Read it.
2. Pin the target app in your shell history: `make deploy SITE=mysite APP=mysite.example.com`. The `APP=` is the FQDN, and the CLI will reject the deploy if it can't reach that app on the current server — so a context mismatch fails loudly rather than silently.
3. If you're switching between two servers frequently, alias each context: `alias clr-prod='cloudron login prod.example.com'`.

---

## 3. Pre-design audits checklist

Six audits from the v2 plan (`documentation-central/plans/2026-05-24-foundation-site-config-plan-v2.md` §"Pre-design audits"). Run them before designing any new plugin, route, or CSS pipeline. v1 of the theming system skipped these and produced a long stack of in-place corrections. This is the cheap way to avoid repeating that.

### A. Sibling plugin patterns

Before writing a new admin controller or view, read how the existing `@rmdes/*` plugins do it.

```bash
# CV plugin — canonical reference for controller + view pattern
ls ~/code/indiekit-dev/indiekit-endpoint-cv/lib/controllers
ls ~/code/indiekit-dev/indiekit-endpoint-cv/views
cat ~/code/indiekit-dev/indiekit-endpoint-cv/CLAUDE.md
```

Look for: `?saved=1` redirect convention (not `?success=<encoded>`), inline `<style>` block only for design tokens, the `page-header`, `hp-section`, `field` / `field__label` / `field__input` markup pattern, `button button--primary` classes.

### B. Indiekit framework API

```bash
# Database access path
grep -rn "Indiekit.database\|application.database" ~/code/indiekit-dev/indiekit-origin/packages/indiekit/lib | head -10

# Session shape (no req.flash, no req.session.user, just access_token + scope)
grep -rn "session\." ~/code/indiekit-dev/indiekit-origin/packages/indiekit/lib | head -20
```

Confirm: `Indiekit.database` is the correct path, not `Indiekit.application.database`. Confirm: `Indiekit.config?.publication?.me` is the canonical user-identity path. Confirm: errors propagate via `try { ... } catch (error) { next(error); }`, not `throw new Error(...)`.

### C. CSS pipeline — trace writes to served output

The big one. Before designing any runtime-CSS mechanism, trace it end to end. The v1 design assumed `/app/code/eleventy-site/css/theme.css` was writable. It isn't. See [`feedback_cloudron_writable_paths.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_cloudron_writable_paths.md).

```bash
# Where does the plugin write?
grep -n "outputPath\|writeFile" ~/code/indiekit-dev/indiekit-endpoint-site-config/lib/render/*.js

# Where does Eleventy passthrough-copy from?
grep -n "addPassthroughCopy\|addWatchTarget" ~/code/indiekit-dev/indiekit-eleventy-theme/eleventy.config.js
```

Verify each step:
1. Plugin write path is under `/app/data/*` (writable at runtime).
2. An Eleventy template (`theme.css.njk` with `permalink: /css/theme.css`) reads that runtime path via the `inlineFile` filter, with a committed `theme.example.css` fallback.
3. The watch target picks up changes so HTML rebuilds and cache-bust hashes refresh.

### D. Template Tailwind class inventory

Before changing `tailwind.config.js` or a CSS-vars contract, audit which utility classes templates actually use. v1 added 6 flat brand tokens that templates never referenced (the brand controls were dead UI).

```bash
cd ~/code/indiekit-dev/indiekit-eleventy-theme

# Which surface/accent shades do templates use?
grep -rEo '(bg|text|border|ring|outline|divide|placeholder|caret)-(surface|accent|primary|link)-[0-9]+' \
  _includes/ content/ 2>/dev/null | sort -u

# Which semantic Tier-2 tokens do templates use?
grep -rE '(text|bg|border)-(heading|fg|bg|action|link|focus|surface|border)\b' \
  _includes/ 2>/dev/null | head -20

# Is there any <alpha-value> literal in compiled CSS?
grep -l '<alpha-value>' _site/css/*.css 2>/dev/null || echo "clean"
```

For every token-shade pair templates reference, the Tailwind config must generate a corresponding class. Flat tokens (one CSS var) don't generate `-NNN` shades — they need a full palette object.

### E. Cloudron deploy mechanics

Six things to know before pushing a deploy:

1. Confirm the target server: `cloudron status`.
2. Image-tag cache: Cloudron caches images by tag. Rebuild at the same tag may serve stale content. The Makefile produces a fresh tag per build by reading the `.cloudron-build` counter — bump it for every deploy.
3. **Do not bump `CloudronManifest.upstreamVersion` as a cache-bust.** That field must match a real upstream `@indiekit/indiekit` release. See [§6](#6-image-tagging-and-the-build-counter) and [`feedback_cloudron_version_fields.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_cloudron_version_fields.md).
4. Verify upstream version on npm before changing the manifest: `npm view @indiekit/indiekit version`.
5. nginx config is part of the image. Adding a plugin to the config plugins array is not enough — if the plugin mounts new routes you may need a corresponding `location` block in `nginx.conf` and a config materialize via `make prepare`.
6. Backend Indiekit is live ~30s after `cloudron update`. The public site updates only after Eleventy's "Swapped to release" log line (~3–5 min for a warm build). Test backend URLs early, public URLs after the swap.

### F. Makefile and `sites/` semantics

```bash
cat ~/code/indiekit-dev/indiekit-cloudron/Makefile | grep -A3 '^\.PHONY:'
```

Walk every documented target. The Makefile's main happy path is: `init` → `use SITE=<name>` → `prepare` → `build` → `deploy`. Do NOT assume any target you don't see documented in `make help` is supported. Per-site `theme/` rsync logic that may appear in older docs is dead code — see Audit F in the v2 plan.

---

## 4. Scaffolding a new site

This is the per-site happy path. Assume you already cloned the repo and ran `make init`. We will create a site called `mysite` that deploys to `mysite.example.com`.

### 4.1 Create the overlay directory

```bash
cd ~/code/indiekit-dev/indiekit-cloudron
mkdir -p sites/mysite/config
```

The `sites/` directory is gitignored. Everything you put here stays on your machine.

### 4.2 Seed the five config files

Copy from `sites/rmendes/config/` (treat it as the canonical example) or from the committed `*.template` files:

```bash
# Option A: copy from the canonical rmendes example (then sanitize secrets)
cp sites/rmendes/config/nginx.conf            sites/mysite/config/nginx.conf
cp sites/rmendes/config/indiekit.config.js    sites/mysite/config/indiekit.config.js
cp sites/rmendes/config/redirects.map         sites/mysite/config/redirects.map
cp sites/rmendes/config/old-blog-redirects.map sites/mysite/config/old-blog-redirects.map
cp sites/rmendes/config/env.sh                sites/mysite/config/env.sh

# Option B: start from the public templates (no secrets to scrub)
cp nginx.conf.template             sites/mysite/config/nginx.conf
cp indiekit.config.js.template     sites/mysite/config/indiekit.config.js
cp redirects.map.template          sites/mysite/config/redirects.map
cp old-blog-redirects.map.template sites/mysite/config/old-blog-redirects.map
touch sites/mysite/config/env.sh
```

### 4.3 Customize each file

| File | What to change per site |
|------|------------------------|
| `env.sh` | All identity vars: `SITE_URL`, `SITE_NAME`, `SITE_DESCRIPTION`, `AUTHOR_NAME`, `AUTHOR_EMAIL`, `AUTHOR_AVATAR`, `AUTHOR_BIO`, etc. Plus per-integration tokens: `MASTODON_ACCESS_TOKEN`, `BLUESKY_PASSWORD`, `GITHUB_TOKEN`, `WEBMENTION_IO_TOKEN`, etc. Plus `PASSWORD_SECRET` — leave the placeholder for first run; the admin UI guides you through creating one. |
| `indiekit.config.js` | `publication.me` (your canonical URL), the `plugins:` array (delete any you don't want), and per-plugin config blocks at the bottom (e.g. the Mastodon, Bluesky, LinkedIn syndicator blocks reference env vars and usually need URL/handle adjustments). |
| `nginx.conf` | Most blocks are reusable across sites. Things you may want to change: the legacy redirect rules (delete blocks for post-types you don't have), the CSP header if you load CDNs other than the defaults, any extra `location` blocks for plugins you add later. |
| `redirects.map` | If you're migrating from another platform, populate this with the legacy URL → new URL map. Each line: `/old/path /new/path/;`. Empty file is fine. |
| `old-blog-redirects.map` | Same idea, used in a separate `map { ... }` directive in nginx for a second redirect surface. Empty file is fine. |

The five files exist because `make prepare SITE=mysite` materializes them at the repo root (as `./nginx.conf`, `./indiekit.config.js`, etc.) which are then COPY'd into the Docker image by the Dockerfile. The materialized files at repo root are listed in `.gitignore` and should not be committed.

### 4.4 (Optional) seed pre-existing content

If you're moving an existing blog into this stack, put any pre-existing posts under `sites/mysite/migrated-content/`. `start.sh` will `cp -rn` them into `/app/data/content/` on first container boot. Use the same directory layout the Eleventy theme expects:

```
sites/mysite/migrated-content/
├── articles/
│   ├── 2024-01-15-first-post.md
│   └── 2024-03-22-another.md
├── notes/
├── pages/
│   └── about.md
└── ...
```

If you're starting fresh, skip this. The repo-root `migrated-content/` directory MUST contain only `.gitkeep` — never put per-site content there. See [`feedback_migrated_content_contamination.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_migrated_content_contamination.md) for the failure mode this guards against.

### 4.5 Set as the default site

```bash
make use SITE=mysite
make which                # confirms: Active SITE: mysite
make which-image          # prints the exact image tag the next build will produce
```

`make use` writes `mysite` to `.current-site` (gitignored) so subsequent `make build` / `make deploy` invocations don't need `SITE=` repeated.

---

## 5. Plugin update lifecycle

You only do this when you've changed plugin source code (typically in `~/code/indiekit-dev/indiekit-endpoint-site-config/` or another `@rmdes/*` plugin repo). Plain "I want to deploy a new site with the existing plugins" does not need any of this.

### 5.1 Edit, version, commit, push

```bash
cd ~/code/indiekit-dev/indiekit-endpoint-site-config

# 1. Make your changes
$EDITOR lib/render/write-theme-css.js

# 2. Bump the version
$EDITOR package.json    # e.g., "1.0.0-alpha.7" -> "1.0.0-alpha.8"

# 3. Commit + push
git add -A
git commit -m "fix: ..."
git push origin main
```

Version bumps are mandatory. npm rejects publishing the same version twice. Pre-release suffixes (`alpha.N`, `beta.N`) are fine for in-flight work; promote to plain semver when you ship a stable release.

### 5.2 npm publish — the manual gate

This step requires a one-time password from your authenticator app. Automation cannot do it.

```bash
cd ~/code/indiekit-dev/indiekit-endpoint-site-config
npm publish    # prompts for OTP
```

Confirm the new version is live:

```bash
npm view @rmdes/indiekit-endpoint-site-config version
```

Do not proceed to `cloudron build` until this prints the new version. The Docker image will install whatever's on npm at build time, and a stale version means your changes silently don't ship.

### 5.3 Pin the new version in the Dockerfile

```bash
cd ~/code/indiekit-dev/indiekit-cloudron
$EDITOR Dockerfile
```

Find the `npm install` block and update the `@rmdes/indiekit-endpoint-site-config@<version>` pin. Same for any other plugin you updated. Commit:

```bash
git add Dockerfile
git commit -m "chore: bump @rmdes/indiekit-endpoint-site-config to alpha.8"
git push origin main
```

### 5.4 Theme changes

When you change the Eleventy theme:

```bash
cd ~/code/indiekit-dev/indiekit-eleventy-theme
# edit, commit, push
git add -A
git commit -m "feat: ..."
git push origin main

# Now update the submodule pointer in indiekit-cloudron
cd ~/code/indiekit-dev/indiekit-cloudron
git submodule update --remote eleventy-site
git add eleventy-site
git commit -m "chore: bump eleventy-site submodule to <SHA>"
git push origin main
```

The submodule pointer must be pushed to the public repo — otherwise the next clone (or any CI process building from origin) cannot resolve the theme commit.

### 5.5 indiekit-cloudron changes

When you change anything else — Dockerfile, Makefile, nginx.conf template, etc.:

```bash
cd ~/code/indiekit-dev/indiekit-cloudron
git add -A   # be deliberate; the materialized config files at root should not be committed
git commit -m "..."
git push origin main
```

The gitignore handles the materialized config + `sites/` overlay correctly. After `make prepare`, the working tree shows `nginx.conf` etc. as " M" (modified). Leave those local; do not stage them.

---

## 6. Image tagging and the build counter

The Makefile constructs every image tag from three inputs:

```
IMAGE_TAG := $(SITE)-$(UPSTREAM_VERSION)-build$(BUILD_NUMBER)
FULL_IMAGE := rmdes/indiekit-cloudron:$(IMAGE_TAG)
```

| Input | Source | Example |
|-------|--------|---------|
| `SITE` | `.current-site` or `SITE=` arg | `rmendes` |
| `UPSTREAM_VERSION` | `CloudronManifest.json` -> `upstreamVersion` | `1.0.0-beta.27` |
| `BUILD_NUMBER` | `.cloudron-build` (single integer file at repo root) | `35` |

Final tag: `rmdes/indiekit-cloudron:rmendes-1.0.0-beta.27-build35`.

### Why three inputs

- **`SITE`** prefix prevents `make build SITE=othersite` from overwriting the previous site's tag in the registry. Two sites can build the same upstream/build counter without colliding.
- **`UPSTREAM_VERSION`** tracks the actual upstream Indiekit release. Operators reading the tag can tell which Indiekit beta this image was built against without going through commit history.
- **`BUILD_NUMBER`** is the cache-bust counter. Bump it for every deploy; this is the only field you should be changing per deploy.

### Bumping the build counter

```bash
# Read current value
cat .cloudron-build
# 35

# Bump it
echo $(( $(cat .cloudron-build) + 1 )) > .cloudron-build

# Or directly
echo 36 > .cloudron-build
```

The file is committed to git so the counter is monotonic across machines and operators. (It's the one piece of state in this repo that all collaborators share.) Bump it as part of every deploy commit:

```bash
echo $(( $(cat .cloudron-build) + 1 )) > .cloudron-build
git add .cloudron-build
git commit -m "chore: bump build counter"
```

### NEVER bump `upstreamVersion` as a cache-bust

Past sessions repurposed `CloudronManifest.upstreamVersion` to force fresh image pulls. They bumped it `beta.27 → beta.28 → beta.29` despite beta.28 and beta.29 never being published upstream. This drifts your manifest into fiction. Commit `1f21f66` reverted it. The full rationale is in [`feedback_cloudron_version_fields.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_cloudron_version_fields.md).

Only bump `upstreamVersion` when `npm view @indiekit/indiekit version` reports a new release and you've actually pulled it in (i.e., bumped `INDIEKIT_VERSION` in the Dockerfile and rebuilt).

### Verifying the tag before you build

```bash
make which-image SITE=mysite
# rmdes/indiekit-cloudron:mysite-1.0.0-beta.27-build36
```

Sanity check: read it, confirm it's what you expect, then build.

---

## 7. Build and deploy flow

The full per-deploy sequence:

```bash
# 1. Make sure you're on the right server
cloudron status

# 2. Materialize the per-site config at the repo root
make prepare SITE=mysite

# 3. Bump the build counter (NOT upstreamVersion)
echo $(( $(cat .cloudron-build) + 1 )) > .cloudron-build

# 4. Build
make build SITE=mysite
# Equivalent to: cloudron build --no-cache --tag <SITE>-<UPSTREAM>-build<N>

# 5. Deploy
make deploy SITE=mysite APP=mysite.example.com
# Equivalent to: cloudron update --app mysite.example.com \
#                                --image rmdes/indiekit-cloudron:<TAG> --no-backup

# 6. Watch the logs
cloudron logs -f --app mysite.example.com
```

### What `make prepare` does

`make prepare SITE=mysite` copies the five files from `sites/mysite/config/` over the repo root (`./nginx.conf`, `./indiekit.config.js`, `./redirects.map`, `./old-blog-redirects.map`, `./env.sh`). These root files are listed in `.gitignore` — they're build artifacts, not committed sources.

It also handles `migrated-content/`:
- If `sites/mysite/migrated-content/` exists, it `rsync -aL`'s those files over the repo root `migrated-content/`.
- If not, it leaves the repo root `migrated-content/` alone (which should only contain `.gitkeep`).

It does NOT touch the `eleventy-site/` submodule — there's only one theme; per-site theme forks are not supported.

### What `make build` does

```
cloudron build --no-cache --tag <SITE>-<UPSTREAM>-build<N>
```

`--no-cache` is always used. Docker layer caching breaks subtly with npm installs and submodule contents. The cost is ~3–5 min of cold build vs ~1 min with cache; not worth the bugs.

The image goes to your Docker Hub by default (`rmdes/indiekit-cloudron:<tag>`). Cloudron pulls it on `cloudron update`.

### What `make deploy` does

```
cloudron update --app <APP> --image <FULL_IMAGE> --no-backup
```

`--no-backup` skips Cloudron's pre-update backup. This saves several minutes per deploy and is safe when you're iterating. Run a manual `cloudron backup --app <APP>` at the end of a deploy session if you want a restore point.

### Watching the deploy

`cloudron logs -f --app mysite.example.com` streams everything: nginx access logs, Indiekit stdout, Eleventy stdout, the background pollers, the memory monitor.

Three landmark log lines to watch for:

| Line | Meaning |
|------|---------|
| `==> Indiekit is ready` | Indiekit's HTTP API is answering on `:8080`. Backend admin URLs (`/admin`, `/site-config/*`) now work. ~30s after container start. |
| `==> Atomic swap: site -> releases/...` | Eleventy's initial full build is done. The `/app/data/site` symlink has been swapped to the new release. Public URLs now serve the new build. |
| `==> nginx reloaded, new release is live` | Right after the swap. nginx is re-reading the symlink. |

Warm build: ~3 min from `cloudron update` to "Swapped to release". Cold build (empty caches): ~20 min. If the swap message doesn't appear after 25 min on a warm rebuild, something is wrong; check the logs for OOM, missing modules, or theme errors.

### Backend vs public timing

Indiekit comes up fast. Eleventy is slow. This stack runs the watcher even when an initial full build wasn't performed — and the watcher's first action is its own full build. So:

- `/admin`, `/site-config/branding`, `/cv/dashboard` etc. work ~30s after `cloudron update`.
- The public homepage (`/`), individual posts, category pages all serve the OLD release until the swap.
- Visitors see no 404s and no broken pages during this gap — the old release is still there, served seamlessly. This is the zero-downtime architecture working as designed.

If you're iterating on theming via the admin UI, you can keep changing settings while the public side catches up. The admin is responsive immediately.

---

## 8. First-deploy checklist

The first time you deploy a brand-new site, several things happen automatically. Verify each.

### 8.1 What happens automatically

1. **Container starts.** `start.sh` runs as the entry point.
2. **Directory creation.** `mkdir -p /app/data/{config,content,uploads,releases,cache,images}`.
3. **Migrated content seed.** If `/app/pkg/migrated-content/<type>/` exists, `cp -rn` copies non-overwriting into `/app/data/content/<type>/`. First boot: full copy. Subsequent boots: only new files.
4. **Indiekit config copy.** `/app/pkg/indiekit.config.js` (built into the image from `sites/mysite/config/indiekit.config.js`) gets copied to `/app/data/config/indiekit.config.js` on every boot. This means your config changes ship on every deploy.
5. **env.sh creation.** On first boot only, if `/app/data/config/env.sh` doesn't exist, a default one is created with placeholders.
6. **Indiekit starts** on port 8080.
7. **Plugin init().** Each `@rmdes/*` plugin's `init()` runs. The site-config plugin calls `maybeSeedFromEnv(Indiekit)` — if `siteConfig.primary` doesn't exist in MongoDB, it builds one from your env vars (`SITE_NAME`, `SITE_DESCRIPTION`, `AUTHOR_NAME`, etc.) and writes the initial theme.css + critical.css + site-config.json to `/app/data/content/_data/`.
8. **Eleventy watcher starts.** It does its own initial full build to `/app/data/releases/<timestamp>/`, then atomic-swaps the symlink. From here on out, content changes trigger incremental rebuilds.
9. **Background pollers start.** Syndication every 2 min, webmention sender every 5 min, memory monitor every 10 min.

### 8.2 Verify manually after first deploy

Once you see "Swapped to release" in the logs:

```bash
# Public site serves a build
curl -I https://mysite.example.com/
# HTTP/2 200

# Admin UI is reachable (will redirect to login)
curl -I https://mysite.example.com/admin
# HTTP/2 302 -> /session

# The site-config plugin's branding view renders
# (visit in browser after logging in via IndieAuth)
open https://mysite.example.com/site-config/branding

# theme.css is being served (cache-busted)
curl -sI https://mysite.example.com/css/theme.css | head -3
# HTTP/2 200
# content-type: text/css

# No plugin init errors in logs
cloudron logs --app mysite.example.com | grep -iE "error|fail" | head -20
```

### 8.3 If the seed went wrong

If your env.sh had typos when the first deploy ran (wrong `SITE_NAME`, missing `AUTHOR_NAME`), the seeded MongoDB document reflects those typos. Two ways to fix:

**Option A — re-seed.** Faster.

```bash
# Drop the singleton document
cloudron exec --app mysite.example.com -- bash -c \
  'mongosh "$CLOUDRON_MONGODB_URL" --quiet --eval "db.siteConfig.deleteOne({_id: \"primary\"})"'

# Fix env.sh and restart
cloudron push --app mysite.example.com sites/mysite/config/env.sh /app/data/config/env.sh
cloudron restart --app mysite.example.com
# Plugin init re-runs, seed re-fires
```

**Option B — edit through the admin UI.** Slower but no shell needed. Log in, go to `/site-config/identity`, change the fields, save.

### 8.4 First-deploy specific things to set

- **PASSWORD_SECRET** must be set before you can log in. The first time you hit `/admin`, Indiekit will show a "New password" page that generates a bcrypt hash. Copy it (with single quotes, the hash contains `$`) into `sites/mysite/config/env.sh` as `export PASSWORD_SECRET='<hash>'`, then `make push-env SITE=mysite APP=mysite.example.com && cloudron restart --app mysite.example.com`.
- **Webmention.io token.** Register at [webmention.io](https://webmention.io), put the token in env.sh, restart.
- **Mastodon access token.** Settings → Development → Applications. Same drill.
- **Bluesky app password.** Settings → App Passwords. Same drill.

---

## 9. Theming via the site-config plugin

The plugin (`@rmdes/indiekit-endpoint-site-config`) is what makes "one theme, many sites" work. Without it the Eleventy theme would only serve its committed example tokens — no admin-side customization.

### 9.1 The 12-control admin

Four sections (`/site-config/identity`, `/branding`, `/layout`, `/features`). Branding is where the 12 controls live.

| Group | Controls | What they set |
|-------|----------|---------------|
| **Palette (3)** | Surface preset, custom palette (when preset=custom), accent base | Tier-1 reference tokens. `--c-surface-50..950` and `--c-accent-50..950` are derived from these. |
| **Text (3)** | Heading color, body text, muted text | Tier-2 semantic overrides for `--c-heading`, `--c-fg`, `--c-fg-muted`. Default: inherit from surface palette. |
| **Interaction (3)** | Link color, action background, focus ring | Tier-2 overrides for `--c-link`, `--c-action`, `--c-focus`. Default: inherit from accent palette. |
| **Structure (3)** | Surface color, border color, mode | Tier-2 `--c-surface`, `--c-border`, and the mode preference (`light` / `dark` / `auto`). |

Tier-3 alert states (`--c-success`, `--c-warning`, `--c-danger`) are fixed for accessibility reasons. Operators don't pick alert colors.

### 9.2 The 3-tier token system

Templates reference Tier-2 utilities. When you override a Tier-2 token, every element bound to that semantic role updates on the next Eleventy rebuild. You don't have to repaint a palette to recolor headings.

```
Tier 1 (palette, 11 shades each)
  --c-surface-50..950, --c-accent-50..950
       |
       v
Tier 2 (semantic roles, what templates use)
  --c-bg, --c-fg, --c-fg-muted, --c-heading,
  --c-link, --c-action, --c-action-fg,
  --c-surface, --c-border, --c-focus
       |
       v
Tier 3 (alert states, fixed in v1)
  --c-success, --c-warning, --c-danger (+ -fg variants)
```

The full design spec for this contract lives at [`documentation-central/plans/2026-05-24-theming-v2-design.md`](../../documentation-central/plans/2026-05-24-theming-v2-design.md). Don't re-explain it here; that document is the source of truth.

### 9.3 APCA Lc contrast validation

Every save is checked. The plugin uses APCA (Lc) instead of WCAG ratio — Lc is the modern standard that actually reflects perceived contrast.

| Lc value | Plugin behavior |
|----------|-----------------|
| `< 30` | Hard block. Save rejected with a contrast error. Settings revert. |
| `30–45` | Soft warn. Save proceeds; UI shows a warning banner. |
| `>= 45` | Pass. No warning. |

The validation runs body text (Tier-2 `--c-fg`) against page background (Tier-2 `--c-bg`) in both light and dark mode, plus action foreground against action background. If you can't get a contrast pass, the most common cause is picking a surface preset and a heading override that fight each other — try resetting the heading and saving with the preset's inherited default.

### 9.4 Version history and reset

| Action | Where |
|--------|-------|
| Last 10 saves snapshot to `siteConfig.history[]` | Automatic, no operator action |
| One-click revert to a previous version | `/site-config/branding` → version history dropdown |
| Reset a single subsection (Palette / Text / Interaction / Structure) | "Reset section" button in each subsection |
| Reset all branding to defaults | "Reset all" button at the bottom of the branding form |

Resets are saves. They also snapshot to history. You can't lose data this way.

### 9.5 Live preview iframe

The branding form embeds an iframe pointing at `/site-config/api/preview` (path may differ; check the plugin). The preview reads pending form state via query params and overlays it on the saved MongoDB document before generating the CSS. So you can experiment before clicking save.

Mode toggle is independent: preview light and dark mode without changing your saved mode preference. The preview iframe uses its own `?mode=light` / `?mode=dark` param.

### 9.6 Mode handling

Three values for the mode setting:

| Mode | Behavior |
|------|----------|
| `light` | The `:root {}` block holds light values. No `prefers-color-scheme` rule. No `.dark` selector. Always light. |
| `dark` | The `:root {}` block holds dark values. Always dark. |
| `auto` | `:root {}` holds light values. A `@media (prefers-color-scheme: dark) { :root:not(.light) { ... } }` block holds dark values. A `.dark { ... }` selector also exists for explicit toggle. |

The `:root:not(.light)` scoping on the dark-mode media query is deliberate: it lets an explicit JS toggle adding `.light` to `<html>` win over OS preference. Without that scoping, the OS wins forever.

---

## 10. Per-site contamination cautions

Three classes of bug that contamination across sites has caused. Treat each as a hard rule.

### 10.1 `migrated-content/` at repo root

**Rule:** the repo-root `migrated-content/` directory must contain only `.gitkeep`. Per-site seed content lives in `sites/<name>/migrated-content/`.

**Why it matters:** the Dockerfile has a literal `COPY migrated-content /app/pkg/migrated-content`. Whatever's in `migrated-content/` at the moment of `cloudron build` gets baked into the image. On every container start, `start.sh` runs `cp -rn /app/pkg/migrated-content/* /app/data/content/`. If you put another site's content there, the receiving site's `/app/data/content/` gets that content seeded into it.

Docker COPY ignores `.gitignore` — only `.dockerignore` keeps files out of the build context. The repo's `.gitignore` line `/migrated-content/*` is for git review only; it doesn't protect the build.

**How to enforce:**

```bash
# Before any build, verify
ls migrated-content/
# Should print exactly: .gitkeep

# If something else is there, it means a make prepare for another site put it there
# (because that site has its own sites/<other>/migrated-content/).
# Solution: run `make prepare SITE=<your-site>` again — but verify your site's
# migrated-content/ is the one you want first.
```

See [`feedback_migrated_content_contamination.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_migrated_content_contamination.md) for the full incident write-up.

### 10.2 Shared Dockerfile plugin list

**Rule:** do not add site-specific plugins to the shared Dockerfile `npm install` block.

The Dockerfile lists every plugin every site might want. Adding (for example) `@rmdes/indiekit-endpoint-donation` because chardonsbleus needs it would also install it into rmendes's image. The plugin would load, register routes, run init code, and probably store junk in rmendes's MongoDB.

There is no current mechanism for per-site plugin loadout. Until per-site plugin manifests ship (the un-built "Plan B"), the Dockerfile plugin list is shared across all sites. A plugin gets added there only if every site needs it.

The Dockerfile has an explicit `NOTE` comment marking the chardonsbleus-only donation plugin as deliberately excluded. Read it before adding anything new to the install list:

```bash
grep -A3 "chardonsbleus-specific" Dockerfile
```

### 10.3 `eleventy-site/` submodule contamination

**Rule:** do not rsync external content over the `eleventy-site/` submodule. There is one canonical theme. Per-site variance is MongoDB siteConfig only.

Older Makefile branches and earlier docs reference a per-site `theme/` directory under `sites/<name>/`. That code path is dead. It was experimental and never worked cleanly. Removing it was tracked as Task v2.6 in the plan; check that the Makefile no longer rsyncs anything over the submodule:

```bash
grep -nA5 "sites/.*theme" Makefile
# Should match nothing — or only commented-out lines / dead notes.
```

If your operator hands you a workflow that involves "drop a theme replacement at `sites/<name>/theme/`" — stop and re-read the v2 plan first. That workflow contaminates the canonical theme across rebuilds and is the reason this rule exists.

---

## 11. Rebuilding after changes

The deploy loop you'll run dozens of times per day during iteration:

```bash
# 1. Make the change (in the right repo)
# 2. Bump the version where required (plugin: package.json; theme: submodule pointer)
# 3. npm publish if plugin changed (manual OTP)
# 4. Bump the build counter
echo $(( $(cat .cloudron-build) + 1 )) > .cloudron-build

# 5. Materialize
make prepare SITE=mysite

# 6. Build + deploy
make deploy SITE=mysite APP=mysite.example.com

# 7. Watch logs
cloudron logs -f --app mysite.example.com
```

### When to use `--no-cache`

Always, for production deploys. `make build` uses `--no-cache` by default. The few-minutes cost of a cold build is much smaller than the cost of debugging a stale-layer ghost bug.

For local dev iteration on the Dockerfile itself, `make build-cached` exists. It uses Docker's layer cache. Useful when you're testing a sequence of build-step changes and the network round-trips for `npm install` dominate.

### When `--no-backup` is safe

`make deploy` passes `--no-backup` by default. Safe during iteration:

- You're trying changes in rapid succession.
- The MongoDB data is replaceable (you can re-seed from env.sh).
- You're testing on a non-production site.

Run a manual `cloudron backup --app <APP>` at the end of a session to checkpoint the day's work.

NOT safe:

- After irreversible MongoDB writes (real user comments, syndication state).
- Right after a major upstream Indiekit version bump (you may want to roll back).

### The build-counter loop

```bash
while iterating; do
  # 1. Code change
  # 2. echo $(( $(cat .cloudron-build) + 1 )) > .cloudron-build
  # 3. make deploy SITE=mysite APP=mysite.example.com
  # 4. cloudron logs -f --app mysite.example.com
  # 5. Verify in browser
done
```

Once you're done iterating, commit the final counter value and the Dockerfile pin to `indiekit-cloudron`'s main branch. That captures the public record of what's deployed.

---

## 12. Troubleshooting

### "Deployed but I still see old colors / old content"

Most likely a service worker cache. The theme registers a service worker that caches HTML and CSS aggressively.

1. Check the swap actually happened: `cloudron exec --app mysite.example.com -- readlink /app/data/site` — should point to a recent release timestamp.
2. Hard refresh (Cmd+Shift+R / Ctrl+Shift+R). This bypasses the service worker.
3. If still stale, unregister the service worker in DevTools → Application → Service Workers → Unregister, then reload.
4. Vivaldi specifically also caches `theme.css` aggressively at the browser layer; clear site data from settings if hard refresh isn't enough.

### "Eleventy build keeps crashing"

Three common causes, in order of likelihood:

1. **Contamination from another site.** Check `/app/data/content/` for files that reference templates your theme doesn't have (e.g., `layout: "layouts/homepage.njk"` in a `pages/home.md` for a site that doesn't have that layout). Match against the manifest in `sites/<other>/migrated-content/`. Remove the offending files via `cloudron exec`.
2. **Submodule pointer mismatch.** The submodule SHA in your indiekit-cloudron commit may not exist on the theme repo's origin. Run `git submodule update --init` in the indiekit-cloudron checkout and verify it succeeds. If the SHA isn't resolvable, the theme commit wasn't pushed.
3. **OOM during initial build.** Look for `JavaScript heap out of memory` or a `Killed` signal in logs. The watcher's initial full build peaks at ~2.8 GB. If you've added a memory-hungry plugin, the cgroup may not have room. The container's cgroup limit is 3.5 GB. See [CLAUDE.md §Memory Tuning](../CLAUDE.md) for details.

### "npm publish OTP failed"

This is on your end — the npm CLI couldn't authenticate. Common causes: the OTP entered was for the wrong account, the OTP was already used, the time on your authenticator drifted, or your npm token expired. `npm whoami` to verify the active account. Re-run `npm publish` with a fresh OTP.

### "Build context too large"

`cloudron build` (or `docker build`) is uploading a giant context. Causes:

1. Accidentally committed binaries somewhere in the repo (`find . -size +10M -not -path './eleventy-site/node_modules/*' -not -path './node_modules/*'`).
2. Stale `node_modules` at the repo root that aren't in `.dockerignore` for some reason.
3. A `sites/<name>/` overlay that bloated — large images in `sites/<name>/migrated-content/`, for example.

Check `.dockerignore` in the repo root. It should exclude `node_modules/`, `.git/`, large media dirs, etc.

### "`/css/theme.css` 404s on the public site"

The Dockerfile's prebuild step probably failed, or the `theme.css.njk` template chain is broken.

```bash
# Verify the prebuild ran during the image build
cloudron exec --app mysite.example.com -- ls -la /app/pkg/eleventy-site/css/
# Should include theme.example.css

# Verify the runtime path has theme.css
cloudron exec --app mysite.example.com -- ls -la /app/data/content/_data/
# Should include theme.css (written by the site-config plugin on init)

# Verify the released build has the file
cloudron exec --app mysite.example.com -- ls -la /app/data/site/css/
```

If the runtime `theme.css` is missing, the plugin's seed-from-env never wrote it — usually because MongoDB siteConfig.primary already exists but with a v1-shaped document. Drop it and let the plugin re-seed (see [§8.3](#83-if-the-seed-went-wrong)).

### "Indiekit keeps restarting (logs show 'Indiekit exited with code')"

The watchdog loop in `start.sh` auto-restarts Indiekit when it crashes. If it's flapping (restart cycle every 30–60s), the process is OOM-killed or has a startup error.

```bash
# Look for the most recent crash + check for a heap snapshot
cloudron exec --app mysite.example.com -- ls -lh /app/data/config/*.heapsnapshot 2>/dev/null

# Check the last 200 lines of logs for "INDIEKIT CRASH"
cloudron logs --app mysite.example.com | grep -A20 "INDIEKIT CRASH" | tail -50
```

Heap snapshots get copied from `/tmp/indiekit-diag/` to `/app/data/config/` on crash. Pull them down with `cloudron pull --app mysite.example.com /app/data/config/<file>.heapsnapshot` and analyze in Chrome DevTools.

---

## 13. Acceptance criteria for a clean deploy

How do you know your deploy is actually good? Run through these:

- [ ] `cloudron status` confirms the right server.
- [ ] `cloudron logs --app mysite.example.com` shows `==> Indiekit is ready` (no startup errors).
- [ ] `cloudron logs --app mysite.example.com` shows `==> Atomic swap: site -> releases/<TS>` (Eleventy finished a full build).
- [ ] `cloudron logs --app mysite.example.com | grep -iE "error|crash|killed" | tail -20` returns no recent matches.
- [ ] `curl -I https://mysite.example.com/` returns 200.
- [ ] `curl -I https://mysite.example.com/admin` returns 302 (redirects to login).
- [ ] `curl -I https://mysite.example.com/css/theme.css` returns 200.
- [ ] Hard-refresh the homepage in a real browser; it renders with your theme.
- [ ] Log in to `/admin`; navigate to `/site-config/branding`; the form loads with your current settings (not empty defaults).
- [ ] Memory monitor logs show steady-state cgroup usage under 2,800 MB (within the 3,584 MB limit).
- [ ] If you bumped a plugin: visit one of its admin pages and confirm the version is what you published (the page footer or HTML comments may show it; otherwise `cloudron exec --app mysite.example.com -- bash -c 'cd /app/code && npm ls @rmdes/indiekit-endpoint-site-config'`).

If all of those pass, the deploy is good.

---

## Appendix: Related reading

| Topic | Where to look |
|-------|---------------|
| Full architectural reference (read-only at runtime, symlink patterns, memory tuning, patches) | [`CLAUDE.md`](../CLAUDE.md) (this repo) |
| Workspace-wide repo map, plugin source-of-truth rules | [`/home/rick/code/indiekit-dev/CLAUDE.md`](../../CLAUDE.md) |
| Plan A v2 spec (six audits, architecture, task history) | [`documentation-central/plans/2026-05-24-foundation-site-config-plan-v2.md`](../../documentation-central/plans/2026-05-24-foundation-site-config-plan-v2.md) |
| Theming v2 design (3-tier tokens, 12 controls, contrast validation) | [`documentation-central/plans/2026-05-24-theming-v2-design.md`](../../documentation-central/plans/2026-05-24-theming-v2-design.md) |
| Site-config plugin README | [`indiekit-endpoint-site-config/README.md`](../../indiekit-endpoint-site-config/README.md) |
| Canonical `@rmdes/*` plugin patterns (CV plugin) | [`indiekit-endpoint-cv/CLAUDE.md`](../../indiekit-endpoint-cv/CLAUDE.md) |
| Cloudron version-field discipline (upstreamVersion vs build counter) | [`feedback_cloudron_version_fields.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_cloudron_version_fields.md) |
| Writable paths inside the Cloudron container | [`feedback_cloudron_writable_paths.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_cloudron_writable_paths.md) |
| The migrated-content contamination incident | [`feedback_migrated_content_contamination.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_migrated_content_contamination.md) |
| Repo visibility (what's public, what's local) | [`feedback_repo_visibility.md`](../../.claude/projects/-home-rick-code-indiekit-dev/memory/feedback_repo_visibility.md) |
