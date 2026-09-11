# site-default

The generic site overlay. Two jobs:

1. **It backs the public image.** `.github/workflows/build-image.yml` copies this
   directory to `sites/default/` and builds from it. Nothing private belongs here.
2. **It shows the shape of a site overlay**, for anyone adding their own.

## How overlays work

`sites/` is gitignored: an operator's own overlays are their configuration, and
have no place in a package other people deploy. Keep them in a separate
repository cloned into `sites/`, or simply create the directory locally.

```
sites/<site>/config/
├── plugins.yaml           # which plugins this site enables
├── indiekit.config.js     # Indiekit configuration
├── env.sh                 # secrets — never commit, anywhere
├── nginx.conf             # only if the site must diverge from the template
├── redirects.map          # optional legacy URL redirects
└── old-blog-redirects.map # optional
```

Only the first three are usually needed. `make prepare` falls back to the
repo-root `*.template` files for anything a site does not provide, so a site
with no `nginx.conf` gets `nginx.conf.template` unchanged — which is what you
want unless it genuinely needs different routes. A copy that merely duplicates
the template will drift out of sync with it.

`make new-site NAME=<site>` scaffolds `plugins.yaml`, `indiekit.config.js` and
`env.sh`, and deliberately creates none of the rest.

## plugins.yaml

Only list what differs from the registry. An empty manifest — as here — means
every plugin takes its `default_enabled` value from
`plugin-registry/plugin-registry.yaml`, which is that registry's own definition
of a sane deployment.

```yaml
post_types:
  event: { enabled: true }      # on for this site, off by default

endpoints:
  activitypub: { enabled: false }  # off for this site, on by default
```

The `core` tier is implicit and cannot be disabled.

To change what the **public image** ships, change `default_enabled` in the
registry — not this file.

## indiekit.config.js

Site identity, post types, syndication targets, plugin options. Read secrets
from `process.env`, never as literals:

```js
// Correct — the value lives in env.sh, which is never committed
password: process.env.BLUESKY_PASSWORD,

// Wrong — a literal here is committed, and stays in git history
password: "hunter2",
```

Per-site identity and branding are **not** set here: they come from MongoDB at
runtime via `@rmdes/indiekit-endpoint-site-config`, which is why one image can
serve visually distinct sites.

## env.sh

Secrets only, never committed — not to this repository, not to an overlay
repository. Moving a site to another machine means copying this file by hand.

```bash
make push-env SITE=<site> APP=<app>   # push it to a running app
cloudron restart --app <app>
```

A few non-secret settings also live here because the theme reads them at build
time rather than from MongoDB:

| Variable | Effect |
|---|---|
| `AUTHOR_AVATAR` | h-card photo, and the avatar on generated OpenGraph cards. A path (`/images/me.jpg`) or same-origin URL; `.jpg`/`.png` only for the OG card. **Leave empty and the cards carry no avatar** — which is what a site without one wants. |
| `OG_CARD_HIDE` | Comma-separated list of OG card elements to drop: `badge`, `date`, `avatar`, `description`, `siteName`. Empty (the default) shows all of them; the title is always shown. |

Everything else about the card — site name, description, accent colour — comes
from the Site-Config admin UI, so one image serves visually distinct sites.

## Building

```bash
make compose SITE=<site>              # registry + plugins.yaml -> .compiled/
make deploy  SITE=<site> APP=<app>    # compose + prepare + build + update
```

`make deploy` runs the whole chain. Never call `cloudron build` directly — it
would build without `--build-arg SITE` and produce an image with no plugin set.
