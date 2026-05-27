# Indiekit for Cloudron

An IndieWeb-ready blog platform for [Cloudron](https://cloudron.io). Deploy your own IndieWeb site with full Micropub support, webmentions, and syndication to Mastodon/Bluesky.

## Features

### IndieWeb Standards
- **Micropub** - Post from any Micropub client (Quill, Indigenous, iA Writer, etc.)
- **Webmentions** - Receive and display likes, reposts, and replies
- **IndieAuth** - Sign in with your domain
- **Microformats2** - Full h-entry, h-card, h-feed, h-cite markup
- **POSSE** - Syndicate to Mastodon, Bluesky, IndieNews, and LinkedIn
- **Bridgy** - Content classes for cross-posting
- **ActivityPub** - Native fediverse federation via Fedify (actor, inbox, outbox, followers/following, Mastodon migration)
- **Mastodon Client API** - Compatible with Phanpy, Elk, Moshidon, Fedilab — post and read your timeline from any Mastodon client
- **Microsub** - Built-in social reader with feed subscriptions and channels

### Post Types
- Articles (long-form)
- Notes (short posts)
- Photos
- Bookmarks
- Likes
- Replies
- Reposts
- Events, RSVPs, Jams, Audio, Video

### Theme Features
- Responsive design with dark mode
- Tailwind CSS styling
- RSS and JSON feeds
- Sitemap generation
- Image optimization
- Social embeds (YouTube, Mastodon, Bluesky)
- Reply context display (h-cite)
- Interactions pages (likes, replies, reposts)

### Optional Integrations
- **GitHub** - Display activity, starred repos, contributions
- **Funkwhale** - Show listening history
- **Last.fm** - Show scrobbles, loved tracks, statistics
- **YouTube** - Display channel activity, latest videos, live status
- **RSS reader** - Aggregate feeds, cache in MongoDB
- **Microsub** - Social reader with channels and feed subscriptions
- **Blogroll** - Aggregate blogs from OPML/Microsub
- **Podroll** - Aggregate podcast episodes
- **Conversations** - Cross-platform notification aggregation (Mastodon, Bluesky, ActivityPub)
- **Comments** - Visitor comments via IndieAuth/RelMeAuth
- **Read Later** - Save URLs for later consumption
- **CV/Resume** - Optional homepage sections with admin editor
- **Homepage builder** - Drag-drop sections from CV, GitHub, Funkwhale, Last.fm, etc.
- **LinkedIn** - OAuth + syndication to LinkedIn

### Post Type Plugins
- **Pages** - Slash pages (`/about`, `/now`, `/uses`) via `@rmdes/indiekit-post-type-page`

## Installation

### Using the Pre-built Image (recommended)

A pre-built image is automatically published on every commit to both Docker Hub and GitHub Container Registry:

| Registry | Image |
|----------|-------|
| Docker Hub | [`rmdes/indiekit-cloudron`](https://hub.docker.com/r/rmdes/indiekit-cloudron) |
| GHCR | `ghcr.io/rmdes/indiekit-cloudron` |

Images are tagged `:latest`, `:VERSION` (e.g. `1.0.0-beta.25`), and `:sha-SHORT`.

To install on Cloudron without building locally:

```bash
cloudron install --image rmdes/indiekit-cloudron:latest --app yourdomain.com
```

To update an existing installation:

```bash
cloudron update --image rmdes/indiekit-cloudron:latest --app yourdomain.com
```

To pin a specific version:

```bash
cloudron install --image rmdes/indiekit-cloudron:1.0.0-beta.25 --app yourdomain.com
```

### Building Locally

If you want to customize the image before deploying:

1. Clone this repository:
   ```bash
   git clone https://github.com/rmdes/indiekit-cloudron.git
   cd indiekit-cloudron
   make init
   ```

2. Create your site overlay (see [Multi-site deployment](#multi-site-deployment) below):
   ```bash
   mkdir -p sites/mysite/config
   cp nginx.conf.template            sites/mysite/config/nginx.conf
   cp indiekit.config.js.template    sites/mysite/config/indiekit.config.js
   cp redirects.map.template         sites/mysite/config/redirects.map
   cp old-blog-redirects.map.template sites/mysite/config/old-blog-redirects.map
   # write your env vars
   touch sites/mysite/config/env.sh
   make use SITE=mysite
   ```

3. Build and install:
   ```bash
   make deploy SITE=mysite APP=mysite.example.com
   ```

### Multi-site deployment

This repo is **site-agnostic by design**. The committed files are all
generic (`*.template` config, a `Makefile`, a `Dockerfile`, a public
theme submodule). Per-deployment overrides live in `sites/<name>/` and
are gitignored — so the same clone can build multiple sites without
leaking deployment-specific data into the public repo.

```
indiekit-cloudron/
├── *.template                         # committed: generic defaults
├── eleventy-site/                     # submodule: public theme
├── Makefile, Dockerfile, CloudronManifest.json, …
└── sites/                             # gitignored, one dir per site
    ├── mysite/
    │   ├── config/
    │   │   ├── nginx.conf
    │   │   ├── indiekit.config.js
    │   │   ├── redirects.map
    │   │   ├── old-blog-redirects.map
    │   │   └── env.sh
    │   └── overrides/eleventy-site/    # optional: tweak the public theme
    └── theirsite/
        ├── config/…
        └── theme/                      # optional: full theme replacement
                                        # (may be a symlink to another repo)
```

**Choosing config-only vs theme-replacement:**

- **Override the submodule** (most users): keep the public theme, add
  your own tweaks under `sites/<name>/overrides/eleventy-site/`.
- **Replace the theme entirely** (custom branded sites): drop a
  full Eleventy project at `sites/<name>/theme/`. Often a symlink to a
  sibling repo where you actually edit the theme:
  ```bash
  ln -s ~/code/mysite/cloudron-overlay/theme sites/mysite/theme
  ```
  `make prepare` `rsync -aL`'s the symlink target into `eleventy-site/`
  so the Docker build sees real files.

**Switching sites:**

```bash
make use SITE=mysite        # remember as default (writes .current-site)
make which                  # show active site
make build                  # uses the default
make build SITE=othersite   # one-off override
```

**Migrating from the legacy `*.rmendes` pattern:**

```bash
# One-time move (per existing site that used the old convention)
mkdir -p sites/rmendes/config
mv nginx.conf.rmendes               sites/rmendes/config/nginx.conf
mv indiekit.config.js.rmendes       sites/rmendes/config/indiekit.config.js
mv redirects.map.rmendes            sites/rmendes/config/redirects.map
mv old-blog-redirects.map.rmendes   sites/rmendes/config/old-blog-redirects.map
mv env.sh.rmendes                   sites/rmendes/config/env.sh
[ -d overrides/eleventy-site ] && mkdir -p sites/rmendes/overrides && \
    mv overrides/eleventy-site sites/rmendes/overrides/
make use SITE=rmendes
```

### First-Run Configuration

1. SSH into the container: `cloudron exec --app yourdomain.com`
2. Edit `/app/data/config/env.sh` with your API tokens and site settings
3. Restart the app: `cloudron restart --app yourdomain.com`

## Configuration

### Environment Variables

All configuration is done via environment variables in `/app/data/config/env.sh`. Copy `env.example` as a reference.

#### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SITE_URL` | Your site URL (no trailing slash) | `https://example.com` |
| `SITE_NAME` | Site name | `My Blog` |
| `AUTHOR_NAME` | Your name | `Jane Doe` |

#### Optional Variables

See [env.example](env.example) for all options:
- Author details (bio, avatar, location, email)
- Social links (for rel="me" verification)
- Syndication (Mastodon, Bluesky credentials)
- Webmentions (webmention.io token)
- Integrations (GitHub, Funkwhale, YouTube)

### Legacy URL Redirects

If migrating from another platform (micro.blog, Known, WordPress), you can set up redirects in `redirects.map`:

```
/2023/01/15/old-post.html /content/notes/2023-01-15-new-slug/;
```

The `nginx.conf.template` includes example patterns for common legacy URL formats.

## Usage

### Posting

Use any Micropub client:
- **Web**: [Quill](https://quill.p3k.io)
- **iOS**: [Indigenous](https://indigenous.realize.be)
- **macOS**: iA Writer, Ulysses (with Micropub)

Or use the built-in editor at `/create` on your site.

### Admin Dashboard

Access `/admin` or `/dashboard` on your site to:
- View recent posts
- Check syndication status
- Manage content

### Webmentions

1. Sign up at [webmention.io](https://webmention.io)
2. Add your token to `WEBMENTION_IO_TOKEN` in env.sh
3. Webmentions will appear on your posts automatically

### Bridgy for Cross-Posting

To syndicate and receive responses from Mastodon/Bluesky:
1. Connect your accounts at [brid.gy](https://brid.gy)
2. The theme includes Bridgy-compatible content classes

## Development

### Makefile Commands

```bash
make help           # Show all available commands
make build          # Build Docker image (no cache)
make build-cached   # Build Docker image (with cache)
make deploy         # Build + deploy to Cloudron
make update         # Deploy without rebuild (use existing image)
make logs           # View Cloudron logs
make shell          # SSH into Cloudron container
make ci             # Trigger GitHub Actions build
make ci-status      # Show recent CI workflow runs
```

### Building from Source

```bash
# First time or after changing Dockerfile/dependencies
make deploy APP=yourdomain.com

# Quick update (reuse existing image)
make update

# Change target app
make deploy APP=mysite.example.com
```

### Local Eleventy Development

```bash
cd eleventy-site
npm install
npm run build:css   # Build Tailwind CSS
npm run build       # Build site
npm run serve       # Development server with watch
```

### Manual Cloudron Commands

```bash
# Build app image
cloudron build

# Build without cache (after Dockerfile or dependency changes)
cloudron build --no-cache

# Deploy to Cloudron
cloudron update --app yourdomain.com

# View logs
cloudron logs -f --app yourdomain.com

# SSH into container
cloudron exec --app yourdomain.com
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    nginx (port 3000)                │
│         Static files + Proxy to Indiekit           │
└─────────────────┬───────────────────────────────────┘
                  │
      ┌───────────┴───────────┐
      │                       │
      ▼                       ▼
┌─────────────┐       ┌─────────────┐
│  Eleventy   │       │   Indiekit  │
│  (watcher)  │       │ (port 8080) │
│             │       │             │
│ Builds HTML │       │ Micropub    │
│ from content│◄──────│ IndieAuth   │
│             │       │ Syndication │
└─────────────┘       └─────────────┘
      │                       │
      ▼                       ▼
┌─────────────────────────────────────────────────────┐
│              /app/data (persistent)                 │
│  content/  site/  config/  images/  uploads/       │
└─────────────────────────────────────────────────────┘
```

### Directory Structure

```
/app/pkg (read-only, Docker image)
├── eleventy-site/          # Theme and build tools
│   ├── _data/              # Site data (env-configured)
│   ├── _includes/          # Nunjucks templates
│   ├── css/                # Compiled Tailwind CSS
│   └── node_modules/       # Eleventy dependencies
├── start.sh                # Entry point
├── nginx.conf              # nginx config
├── indiekit.config.js.template
├── redirects.map           # Legacy URL redirects
└── old-blog-redirects.map

/app/data (persistent, backed up)
├── config/                 # Runtime config (env.sh, indiekit.config.js)
├── content/                # User posts (notes/, articles/, etc.)
├── site/                   # Generated static HTML
├── cache/                  # Eleventy cache
├── images/                 # User images
└── uploads/                # Media uploads
```

## Customization

### Adding Your Avatar

1. Set `AUTHOR_AVATAR` in env.sh to your image path
2. Place your avatar in `eleventy-site/images/` (or use `/images/user/` for runtime uploads)

### CV/Resume Sections

To display CV sections on the homepage:

1. Edit `eleventy-site/_data/cv.js` with your experience, projects, skills, education
2. Rebuild — sections only appear when data exists

### Custom Theme Modifications

Edit files in `eleventy-site/`:
- `_includes/layouts/` - Page layouts
- `_includes/components/` - Reusable components
- `css/tailwind.css` - Custom styles
- `tailwind.config.js` - Tailwind configuration

## Indiekit Plugins

This deployment includes these Indiekit plugins. See [`Dockerfile`](Dockerfile) for installed versions and [`indiekit.config.js.template`](indiekit.config.js.template) for the active runtime list.

### Core (forks of upstream defaults)
- `@rmdes/indiekit-preset-eleventy` - Eleventy preset (permalink fix for pages)
- `@indiekit/store-file-system` - Local file storage
- `@rmdes/indiekit-endpoint-auth` - IndieAuth fork (custom auth fixes)
- `@rmdes/indiekit-endpoint-micropub` - Micropub fork (typeConfig validation)
- `@rmdes/indiekit-endpoint-syndicate` - Syndication endpoint fork
- `@rmdes/indiekit-endpoint-posts` - Posts endpoint fork (syndicate form)
- `@rmdes/indiekit-endpoint-files` - Files endpoint fork (multi-file upload)
- `@rmdes/indiekit-endpoint-share` - Share endpoint fork (type selection)
- `@rmdes/indiekit-endpoint-webmention-io` - Webmention.io integration
- `@rmdes/indiekit-frontend` - Frontend fork (floating toolbar, service worker)
- `@indiekit/endpoint-json-feed` - JSON feed

### Federation & Social
- `@rmdes/indiekit-endpoint-activitypub` - **ActivityPub federation via Fedify** — actor, inbox, outbox, followers/following, Mastodon migration, Mastodon Client API
- `@rmdes/indiekit-endpoint-microsub` - Microsub social reader
- `@rmdes/indiekit-endpoint-conversations` - Conversation aggregation across Mastodon/Bluesky/ActivityPub
- `@rmdes/indiekit-endpoint-comments` - Visitor comments via IndieAuth/RelMeAuth
- `@rmdes/indiekit-endpoint-webmention-sender` - Webmention sender
- `@rmdes/indiekit-endpoint-bluesky-pds` - Bluesky PDS integration

### Syndication
- `@rmdes/indiekit-syndicator-mastodon` - Mastodon syndication (with external like/repost)
- `@rmdes/indiekit-syndicator-bluesky` - Bluesky syndication (with external like/repost)
- `@rmdes/indiekit-syndicator-indienews` - IndieNews submission
- `@rmdes/indiekit-syndicator-linkedin` - LinkedIn syndication
- `@rmdes/indiekit-endpoint-linkedin` - LinkedIn OAuth endpoint

### Aggregation & Feeds
- `@rmdes/indiekit-endpoint-rss` - RSS feed reader
- `@rmdes/indiekit-endpoint-blogroll` - Blog aggregator (OPML/Microsub)
- `@rmdes/indiekit-endpoint-podroll` - Podcast aggregator (FreshRSS, OPML)

### Identity & Activity
- `@rmdes/indiekit-endpoint-github` - GitHub activity (commits, stars, contributions)
- `@rmdes/indiekit-endpoint-funkwhale` - Funkwhale listening history
- `@rmdes/indiekit-endpoint-lastfm` - Last.fm scrobbles
- `@rmdes/indiekit-endpoint-youtube` - YouTube channel activity
- `@rmdes/indiekit-endpoint-cv` - CV/Resume management
- `@rmdes/indiekit-endpoint-homepage` - Drag-drop homepage builder
- `@rmdes/indiekit-endpoint-readlater` - Save URLs for later

### Post Types & Infrastructure
- `@rmdes/indiekit-post-type-page` - Slash pages (`/about`, `/now`, `/uses`)
- `@rmdes/indiekit-startup-gate` - Defers plugin background tasks until after first Eleventy build (memory contention prevention)

## Credits

- [Indiekit](https://getindiekit.com) by Paul Robert Lloyd
- [Eleventy](https://www.11ty.dev) static site generator
- [Cloudron](https://cloudron.io) app platform
- [IndieWeb](https://indieweb.org) community

## License

MIT License
