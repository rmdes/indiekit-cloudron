# Indiekit for Cloudron

An IndieWeb-ready blog platform for [Cloudron](https://cloudron.io). Deploy your own IndieWeb site with full Micropub support, webmentions, and syndication to Mastodon/Bluesky.

## Features

### IndieWeb Standards
- **Micropub** - Post from any Micropub client (Quill, Indigenous, iA Writer, etc.)
- **Webmentions** - Receive and display likes, reposts, and replies
- **IndieAuth** - Sign in with your domain
- **Microformats2** - Full h-entry, h-card, h-feed, h-cite markup
- **POSSE** - Syndicate to Mastodon and Bluesky
- **Bridgy** - Content classes for cross-posting

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
- **YouTube** - Display channel activity
- **CV/Resume** - Optional homepage sections

## Installation

### Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/indiekit-cloudron.git
   cd indiekit-cloudron
   ```

2. (Optional) Create personal overrides for your deployment:
   ```bash
   # Copy templates to create your personal config files
   cp nginx.conf.template nginx.conf.rmendes
   cp indiekit.config.js.template indiekit.config.js.rmendes
   # Edit .rmendes files with your personal values
   ```

3. Build and install:
   ```bash
   make deploy APP=yourdomain.com
   # Or without Makefile:
   # cloudron build && cloudron install --app yourdomain.com
   ```

4. Configure secrets in Cloudron:
   - SSH into container: `make shell` (or `cloudron exec --app yourdomain.com`)
   - Edit `/app/data/config/env.sh` with your API tokens
   - Restart the app

## Configuration

### Environment Variables

All configuration is done via environment variables. Copy `env.example` to `env.sh` and fill in your values.

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

### Personal Configuration Overrides

For personal deployments, you can override template files without modifying the repo. Create files with `.rmendes` suffix (or any suffix you choose) - these are gitignored but applied during Docker build.

| Template | Override | Purpose |
|----------|----------|---------|
| `nginx.conf.template` | `nginx.conf.rmendes` | Custom nginx config, legacy URL redirects |
| `redirects.map` (empty) | `redirects.map.rmendes` | Legacy URL mappings (e.g., micro.blog) |
| `old-blog-redirects.map` (empty) | `old-blog-redirects.map.rmendes` | Old blog URL mappings |
| `eleventy-site/_data/cv.js` | `eleventy-site/_data/cv.js.rmendes` | Personal CV/resume data |
| `indiekit.config.js.template` | `indiekit.config.js.rmendes` | Personal Indiekit config (syndicators, integrations) |

The Dockerfile automatically:
1. Uses templates as defaults for fresh installs
2. Applies `.rmendes` overrides if they exist
3. Creates empty placeholder files where needed

### Legacy URL Redirects

If migrating from another platform (micro.blog, Known, WordPress), you can set up redirects:

1. Create `redirects.map.rmendes` with mappings:
   ```
   /2023/01/15/old-post.html /content/notes/2023-01-15-new-slug/;
   ```

2. The `nginx.conf.template` includes example patterns for common legacy URL formats.

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

The project includes a Makefile for streamlined deployment workflows:

```bash
make help           # Show all available commands
make prepare        # Apply personal .rmendes overrides to base files
make build          # Apply overrides + build Docker image (no cache)
make build-cached   # Apply overrides + build Docker image (with cache)
make deploy         # Build + deploy to Cloudron
make update         # Deploy without rebuild (use existing image)
make clean          # Restore base templates (undo overrides)
make logs           # View Cloudron logs
make shell          # SSH into Cloudron container
```

**Typical workflow:**

```bash
# First time or after changing Dockerfile/dependencies
make deploy

# Quick update (reuse existing image)
make update

# After editing .rmendes files
make prepare && make deploy

# Prepare repo for git commit (restore templates)
make clean
git add . && git commit -m "Update"
```

**Override pattern:**

The Makefile applies personal `.rmendes` overrides before building:

| Override File | Copies To | Purpose |
|---------------|-----------|---------|
| `nginx.conf.rmendes` | `nginx.conf` | Custom nginx, legacy redirects |
| `redirects.map.rmendes` | `redirects.map` | Legacy URL mappings |
| `old-blog-redirects.map.rmendes` | `old-blog-redirects.map` | Old blog URLs |
| `eleventy-site/_data/cv.js.rmendes` | `cv.js` | Personal CV data |
| `indiekit.config.js.rmendes` | `indiekit.config.js` | Personal Indiekit config |

All `.rmendes` files are gitignored, keeping personal data out of the public repo.

**Changing target app:**

```bash
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

If you prefer not to use the Makefile:

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
├── nginx.conf              # Applied config (from template or override)
├── nginx.conf.template     # Default nginx config
├── indiekit.config.js.template
├── redirects.map           # Legacy URL redirects (empty or from override)
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

1. Copy `eleventy-site/_data/cv.js` to `eleventy-site/_data/cv.js.rmendes`
2. Fill in your experience, projects, skills, education
3. Rebuild - sections only appear when data exists

### Custom Theme Modifications

Edit files in `eleventy-site/`:
- `_includes/layouts/` - Page layouts
- `_includes/components/` - Reusable components
- `css/tailwind.css` - Custom styles
- `tailwind.config.js` - Tailwind configuration

## Indiekit Plugins

This deployment includes these Indiekit plugins:

- `@indiekit/preset-eleventy` - Eleventy content paths
- `@indiekit/store-file-system` - Local file storage
- `@indiekit/syndicator-mastodon` - Mastodon syndication
- `@indiekit/syndicator-bluesky` - Bluesky syndication
- `@indiekit/endpoint-syndicate` - Syndication endpoint
- `@indiekit/endpoint-json-feed` - JSON feed
- `@indiekit/endpoint-webmention-io` - Webmention.io integration
- `@rmdes/indiekit-endpoint-github` - GitHub activity
- `@rmdes/indiekit-endpoint-funkwhale` - Funkwhale integration
- `@rmdes/indiekit-endpoint-youtube` - YouTube integration

## Credits

- [Indiekit](https://getindiekit.com) by Paul Robert Lloyd
- [Eleventy](https://www.11ty.dev) static site generator
- [Cloudron](https://cloudron.io) app platform
- [IndieWeb](https://indieweb.org) community

## License

MIT License
