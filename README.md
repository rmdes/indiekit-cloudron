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
   ```

2. Build and install:
   ```bash
   make deploy APP=yourdomain.com
   # Or without Makefile:
   # cloudron build && cloudron install --app yourdomain.com
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

This deployment includes these Indiekit plugins:

- `@rmdes/indiekit-preset-eleventy` - Eleventy content paths (permalink fix)
- `@indiekit/store-file-system` - Local file storage
- `@rmdes/indiekit-syndicator-mastodon` - Mastodon syndication
- `@rmdes/indiekit-syndicator-bluesky` - Bluesky syndication
- `@rmdes/indiekit-endpoint-syndicate` - Syndication endpoint
- `@indiekit/endpoint-json-feed` - JSON feed
- `@rmdes/indiekit-endpoint-webmention-io` - Webmention.io integration
- `@rmdes/indiekit-endpoint-github` - GitHub activity
- `@rmdes/indiekit-endpoint-funkwhale` - Funkwhale integration
- `@rmdes/indiekit-endpoint-lastfm` - Last.fm scrobbles
- `@rmdes/indiekit-endpoint-youtube` - YouTube integration
- `@rmdes/indiekit-endpoint-rss` - RSS feed reader
- `@rmdes/indiekit-endpoint-microsub` - Microsub social reader
- `@rmdes/indiekit-endpoint-blogroll` - Blog aggregator
- `@rmdes/indiekit-endpoint-podroll` - Podcast aggregator
- `@rmdes/indiekit-endpoint-webmention-sender` - Webmention sender
- `@rmdes/indiekit-syndicator-indienews` - IndieNews syndication
- `@rmdes/indiekit-syndicator-linkedin` - LinkedIn syndication
- `@rmdes/indiekit-endpoint-linkedin` - LinkedIn OAuth
- `@rmdes/indiekit-endpoint-homepage` - Homepage customization
- `@rmdes/indiekit-endpoint-cv` - CV/Resume sections

## Credits

- [Indiekit](https://getindiekit.com) by Paul Robert Lloyd
- [Eleventy](https://www.11ty.dev) static site generator
- [Cloudron](https://cloudron.io) app platform
- [IndieWeb](https://indieweb.org) community

## License

MIT License
