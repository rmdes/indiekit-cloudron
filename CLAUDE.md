# CLAUDE.md

This file provides guidance to Claude Code when working with the Indiekit Cloudron app.

## Project Overview

This is a Cloudron-packaged version of Indiekit (IndieWeb server) combined with an Eleventy static site generator. The app runs three processes: Indiekit (Node.js), Eleventy (file watcher), and nginx (static file serving/proxying).

**Target Site:** https://rmendes.net

## CRITICAL: Eleventy Theme Submodule

The `eleventy-site/` directory is a **Git submodule** pointing to the separate theme repository:

- **Submodule repo:** `indiekit-eleventy-theme` (`/home/rick/code/indiekit-eleventy-theme`)
- **GitHub:** https://github.com/rmdes/indiekit-eleventy-theme

### Submodule Sync Workflow

**When the theme repo is updated, you MUST update this repo's submodule reference:**

```bash
# Pull latest theme changes into submodule
git submodule update --remote eleventy-site

# Commit the submodule pointer update
git add eleventy-site
git commit -m "chore: update eleventy-site submodule"
git push origin main

# Rebuild and deploy
cloudron build --no-cache
cloudron update --app rmendes.net
```

### Working on Theme Changes

If you need to modify the Eleventy theme:

1. **Work in the theme repo** (`/home/rick/code/indiekit-eleventy-theme`)
2. Commit and push changes there
3. **Return to this repo** and update the submodule (commands above)
4. Rebuild and deploy

### Checking Submodule Status

```bash
# See which commit the submodule points to
git submodule status

# Check if submodule is behind remote
cd eleventy-site && git fetch && git log HEAD..origin/main --oneline
```

### Common Submodule Issues

**Submodule shows as "modified" but you didn't change it:**
```bash
# Reset submodule to committed state
git submodule update --init
```

**Theme changes not appearing on live site:**
- Did you update the submodule reference in THIS repo?
- Did you push THIS repo after updating the submodule?
- Did you rebuild with `cloudron build --no-cache`?

## Commands

```bash
# Build the Cloudron app image
cloudron build

# Build with no cache (REQUIRED after Dockerfile or dependency changes)
cloudron build --no-cache

# Deploy to Cloudron
cloudron update --app rmendes.net

# View logs
cloudron logs -f --app rmendes.net

# SSH into running container
cloudron exec --app rmendes.net
```

**CRITICAL: Always use `cloudron build`, never `docker build` directly.**

## Architecture

### Directory Structure

```
Docker Image (read-only at runtime):
├── /app/code/                    # Indiekit core + plugins
│   └── node_modules/             # Indiekit dependencies
├── /app/pkg/
│   ├── eleventy-site/            # Static site generator
│   │   ├── node_modules/         # Eleventy dependencies (NEVER copy to /app/data)
│   │   ├── _includes/            # Nunjucks templates
│   │   ├── _data/                # Site data files
│   │   ├── css/                  # Compiled CSS (Tailwind)
│   │   ├── content -> /app/data/content    # SYMLINK (created in Dockerfile)
│   │   ├── _site -> /app/data/site         # SYMLINK
│   │   ├── .cache -> /app/data/cache       # SYMLINK
│   │   └── uploads -> /app/data/uploads    # SYMLINK
│   ├── start.sh
│   ├── nginx.conf
│   └── indiekit.config.js.template

Runtime (writable, backed up):
├── /app/data/
│   ├── config/                   # indiekit.config.js, env.sh, .secret
│   ├── content/                  # User posts (notes/, articles/, etc.)
│   ├── site/                     # Generated static HTML
│   ├── cache/                    # Eleventy cache
│   ├── images/                   # User-uploaded images
│   └── uploads/                  # Media uploads
```

### Process Architecture

1. **nginx (port 3000)** - Entry point, serves static files, proxies to Indiekit
2. **Eleventy (watcher)** - Rebuilds site when content changes
3. **Indiekit (port 8080)** - Handles Micropub, authentication, admin UI

## Critical Patterns (MUST FOLLOW)

### 1. Symlinks MUST Be Created in Dockerfile

The /app/pkg filesystem is **read-only at runtime**. Symlinks cannot be created in start.sh.

```dockerfile
# CORRECT - Create symlinks in Dockerfile (dangling during build, valid at runtime)
RUN rm -rf /app/pkg/eleventy-site/content && ln -s /app/data/content /app/pkg/eleventy-site/content && \
    rm -rf /app/pkg/eleventy-site/_site && ln -s /app/data/site /app/pkg/eleventy-site/_site && \
    rm -rf /app/pkg/eleventy-site/.cache && ln -s /app/data/cache /app/pkg/eleventy-site/.cache
```

```bash
# WRONG - This fails at runtime
ln -sf /app/data/content /app/pkg/eleventy-site/content  # Read-only file system error
```

### 2. NEVER Copy node_modules to /app/data

Copying node_modules to /app/data causes:
- Massive backup sizes (100MB+ for each backup)
- Slow deployments
- Wasted storage

```bash
# WRONG - node_modules gets backed up
cp -r /app/pkg/eleventy-site/* /app/data/eleventy/

# CORRECT - Run from /app/pkg where node_modules already exists
cd /app/pkg/eleventy-site
./node_modules/.bin/eleventy
```

### 3. NODE_ENV Timing

Set NODE_ENV=production **AFTER** npm install and builds, not before:

```dockerfile
# CORRECT
RUN npm install                    # Gets all dependencies including devDependencies
RUN ./node_modules/.bin/tailwindcss -i css/tailwind.css -o css/style.css --minify
ENV NODE_ENV=production           # Set AFTER builds complete

# WRONG - devDependencies won't install
ENV NODE_ENV=production
RUN npm install                    # Tailwind not installed!
```

### 4. ESM Modules Configuration

The Eleventy site uses ESM modules. Both files must be consistent:

**package.json** must have:
```json
{
  "type": "module"
}
```

**eleventy.config.js** must use ESM syntax:
```javascript
import pluginWebmentions from "@chrisburnell/eleventy-cache-webmentions";
import { feedPlugin } from "@11ty/eleventy-plugin-rss";

export default function (eleventyConfig) {
  // ...
}
```

### 5. Disable Markdown Template Engine

Markdown content may contain code samples with `{{` syntax. Prevent Nunjucks from parsing markdown:

```javascript
// eleventy.config.js
return {
  markdownTemplateEngine: false,  // CRITICAL - prevents parsing {{ in markdown
  htmlTemplateEngine: "njk",
};
```

### 6. Cache Busting for Clean Builds

After changing Dockerfile or dependencies, increment CACHE_BUST:

```dockerfile
# Increment to force rebuild
ARG CACHE_BUST=47  # Change to 48, 49, etc.
```

Then run: `cloudron build --no-cache`

### 7. Eleventy Collection Paths

Collections use paths relative to Eleventy's input directory. The symlink makes content appear at `content/`:

```javascript
// CORRECT - single content/ prefix
eleventyConfig.addCollection("posts", function (collectionApi) {
  return collectionApi.getFilteredByGlob("content/**/*.md");
});

// WRONG - double content/content/
eleventyConfig.addCollection("posts", function (collectionApi) {
  return collectionApi.getFilteredByGlob("content/content/**/*.md");
});
```

### 8. start.sh Must Run from /app/pkg

```bash
# CORRECT - run from where node_modules exists
cd /app/pkg/eleventy-site
gosu cloudron:cloudron ./node_modules/.bin/eleventy --output=/app/data/site

# WRONG - path doesn't exist
gosu cloudron:cloudron /app/code/node_modules/.bin/eleventy
```

### 9. Data Files Must Use ESM Syntax

All `_data/*.js` files must use ESM exports when package.json has `"type": "module"`:

```javascript
// CORRECT - ESM syntax
export default {
  name: process.env.SITE_NAME || "My Site",
  url: process.env.SITE_URL || "https://example.com",
};

// WRONG - CommonJS syntax (causes "module is not defined" error)
module.exports = {
  name: process.env.SITE_NAME || "My Site",
};
```

### 10. Clear Stale Site Files Before Build

The start.sh must clear `/app/data/site` before building to prevent Eleventy from re-processing old generated files:

```bash
# In start.sh - clear before build
echo "==> Clearing stale site files"
rm -rf /app/data/site/*

echo "==> Building Eleventy site"
cd /app/pkg/eleventy-site
./node_modules/.bin/eleventy --output=/app/data/site
```

### 11. Ignore Output Directory in Eleventy Config

Prevent Eleventy from processing files in the output directory (which is a symlink):

```javascript
// eleventy.config.js
eleventyConfig.ignores.add("_site");
eleventyConfig.ignores.add("_site/**");
```

## Eleventy Site Configuration

### Required Plugins

The site depends on these plugins (all in package.json):
- `@11ty/eleventy` - Core
- `@11ty/eleventy-plugin-rss` - RSS feed generation
- `@11ty/eleventy-img` - Image optimization
- `@chrisburnell/eleventy-cache-webmentions` - Webmentions
- `eleventy-plugin-embed-everything` - Auto-embed social posts
- `@quasibit/eleventy-plugin-sitemap` - Sitemap generation

### Content Collections

| Collection | Path | Description |
|------------|------|-------------|
| posts | `content/**/*.md` | All content combined |
| notes | `content/notes/**/*.md` | Short posts |
| articles | `content/articles/**/*.md` | Long-form articles |
| bookmarks | `content/bookmarks/**/*.md` | Saved links |
| photos | `content/photos/**/*.md` | Photo posts |
| likes | `content/likes/**/*.md` | Liked content |
| feed | `content/**/*.md` (limit 20) | RSS feed |

### Pagination Configuration

Pagination must NOT use `reverse: true` because collections are already sorted newest-first:

```yaml
pagination:
  data: collections.notes
  size: 20
  alias: paginatedNotes
  # NO reverse: true - collections already sorted by date descending
```

## Debugging

### Common Errors

**"Blog coming soon" placeholder:**
- Eleventy build failed
- Check: `cloudron logs -f --app rmendes.net`
- Look for: template errors, missing modules, path issues

**"module is not defined in ES module scope":**
- package.json missing `"type": "module"` or config using CommonJS syntax
- Fix: Ensure both package.json and config use ESM consistently

**"unexpected token: /" in templates:**
- `markdownTemplateEngine: "njk"` is parsing code in markdown
- Fix: Set `markdownTemplateEngine: false`

**"Cannot find module":**
- Wrong path to node_modules
- Fix: Run from directory where npm install was executed

**Massive backup sizes:**
- node_modules in /app/data
- Fix: Remove any code that copies to /app/data, run from /app/pkg

### Useful Debug Commands

```bash
# Check what's in /app/data (should NOT have node_modules)
cloudron exec --app rmendes.net -- ls -la /app/data/

# Check symlinks are correct
cloudron exec --app rmendes.net -- ls -la /app/pkg/eleventy-site/

# Manual Eleventy build
cloudron exec --app rmendes.net -- bash -c "cd /app/pkg/eleventy-site && ./node_modules/.bin/eleventy"

# Check Eleventy version
cloudron exec --app rmendes.net -- bash -c "cd /app/pkg/eleventy-site && ./node_modules/.bin/eleventy --version"
```

## File Checklist for Changes

When modifying this app, verify:

| File | Check |
|------|-------|
| Dockerfile | Symlinks created with `ln -s`, NODE_ENV after installs |
| start.sh | Runs from /app/pkg/eleventy-site, clears /app/data/site/*, no cp to /app/data |
| package.json | Has `"type": "module"` |
| eleventy.config.js | ESM syntax, `markdownTemplateEngine: false`, ignores `_site`, correct glob paths |
| _data/*.js | All use `export default`, not `module.exports` |
| nginx.conf | Serves from /app/data/site, proxies /admin to port 8080 |

## Anti-Patterns (NEVER DO)

1. ❌ `docker build` - Use `cloudron build`
2. ❌ Creating symlinks in start.sh - filesystem is read-only at runtime
3. ❌ Copying anything to /app/data/eleventy/ - bloats backups
4. ❌ Setting NODE_ENV=production before npm install
5. ❌ Using `reverse: true` with already-sorted collections
6. ❌ Using CommonJS (`module.exports`) in ESM project (`"type": "module"`)
7. ❌ `markdownTemplateEngine: "njk"` with code samples in content
8. ❌ Referencing `/app/code/node_modules/.bin/eleventy` for Eleventy
9. ❌ Not clearing `/app/data/site` before Eleventy build - stale files cause errors
10. ❌ Using `blog.rmendes.net` instead of `rmendes.net` - this is the production domain

## Data Corruption Recovery

### Circular Symlink in /app/data/content

If you see `ELOOP: too many symbolic links encountered` with paths like `content/content/content/...`, there's a circular symlink:

```bash
# Check for circular symlink
cloudron exec --app rmendes.net -- ls -la /app/data/content/

# If you see: content -> /app/data/content (symlink back to itself), remove it:
cloudron exec --app rmendes.net -- rm /app/data/content/content
```

This can happen when buggy code copies symlinks instead of following them.

### Cleaning Up Old /app/data/eleventy Directory

If `/app/data/eleventy/` exists (from buggy old start.sh), remove it:

```bash
cloudron exec --app rmendes.net -- rm -rf /app/data/eleventy
```

### Manual Rebuild After Data Cleanup

After fixing data issues, trigger a manual rebuild:

```bash
cloudron exec --app rmendes.net -- bash -c "rm -rf /app/data/site/* && cd /app/pkg/eleventy-site && ./node_modules/.bin/eleventy --output=/app/data/site"
```

## References

- Cloudron packaging guide: `/home/rick/code/cloudron-skills/packaging-cloudron-apps/SKILL.md`
- Indiekit lessons learned: `/home/rick/code/cloudron-skills/packaging-cloudron-apps/indiekit-lessons-learned.md`
- taiga-app (symlink pattern): https://git.cloudron.io/cloudron/taiga-app
