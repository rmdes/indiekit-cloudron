# Deploy handover to the Framework laptop — 2026-10-10

State on this machine (it15) at 20:30 CEST: every repo under `~/indiekit` is committed and pushed, all eleven cut forks match upstream `main` (f8c73766, after Paul merged #978, #981, #983, #985, #987, #989, #991, #992 this evening), and nine forks carry a version bump that is **not yet on npm**. Nothing else is needed from this side; the rest is `npm publish` (OTP), pins, and `make deploy`.

## 1. Publish, in any order

Each repo is on `main`, pushed, with the bump as its last commit. `git pull`, then `npm publish` in each.

| Repo | Publish | What changed since the published version |
|---|---|---|
| `indiekit-endpoint-auth` | **1.0.0-beta.42** | Upstream only: aciccarello's "use publication me when signing authorization code", Paul's `strictNullChecks` and dependency passes. Zero code diff from upstream `main`. |
| `indiekit-endpoint-micropub` | **1.0.0-beta.39** | Upstream's `filter` and `category` on `q=source` (replaces the fork's `search`), category normalisation on write (fork keeps its canonical fold against the publication's list), uid on create and `q=source&uid=`, `q=config` post-type discovery by vocabulary, strictNullChecks. `query.js` is byte-identical to upstream. |
| `indiekit-endpoint-syndicate` | **1.0.0-beta.46** | Upstream's `getPostsAwaitingSyndication`; the fork keeps its controller (readiness gate, force mode, delay) and the og:image probe from 28 Sep. |
| `indiekit-endpoint-share` | **1.1.2** | Upstream's final form of the syndication checkboxes and Paul's translations of the label. Zero code diff from upstream `main`. |
| `indiekit-frontend` | **1.0.0-beta.55** | Paul's `getElement` refactor and strictNullChecks fixes, the closed add-another selector, `globalThis` for the Alpine attach; fork components (media browser, suggestions, floating toolbar) adapted. |
| `indiekit-preset-eleventy` | **1.0.0-beta.41** | Upstream's page post type support and #916 (posts written where the advertised URL resolves); the fork keeps `pages/{slug}.md` and the `permalink`/`mpUrl` front matter. |
| `indiekit-syndicator-mastodon` | **1.1.4** | Upstream's remote-reply threading form, "require access token", media uploads without an id skipped; fork keeps its text policy and external likes/reposts. |
| `indiekit-syndicator-bluesky` | **1.1.6** | Upstream's reply threading and link facets, "require password", typed signatures; fork keeps external cards, bookmarks and every-href text. |
| `indiekit-endpoint-webmention-io` | **1.2.3** | Upstream's "require token" and dependency passes; the fork's own controllers unchanged. |

**Not published, on purpose:**

- `indiekit-endpoint-posts` stays at **1.2.3**. Its `main` (8f7eebc) now looks a post up through Micropub `q=source&uid=`, which needs the uid backfill that lives in `@indiekit/indiekit` on `main` and is **not in beta.29 on npm**. Pinning the synced posts fork on a site before core beta.30 makes older posts 404 again. Wait for the core release, then bump and publish posts together with the core move.
- `indiekit-endpoint-files` has zero diff and its override was already retired in cloudron (commit aee94ed); nothing to publish.

## 2. Pin

In `indiekit-cloudron/package.json` → `overrides`:

```
@indiekit/endpoint-auth      -> npm:@rmdes/indiekit-endpoint-auth@1.0.0-beta.42
@indiekit/endpoint-micropub  -> npm:@rmdes/indiekit-endpoint-micropub@1.0.0-beta.39
@indiekit/endpoint-syndicate -> npm:@rmdes/indiekit-endpoint-syndicate@1.0.0-beta.46
@indiekit/frontend           -> npm:@rmdes/indiekit-frontend@1.0.0-beta.55
@indiekit/endpoint-share     -> npm:@rmdes/indiekit-endpoint-share@1.1.2
@indiekit/endpoint-posts     -> unchanged, 1.2.3
```

The same five lines in `indiekit-deploy/package.json` → `overrides`.

In `indiekit-plugin-registry/plugin-registry.yaml`:

```
@rmdes/indiekit-preset-eleventy        version: "^1.0.0-beta.41"
@rmdes/indiekit-syndicator-mastodon    version: "^1.1.4"
@rmdes/indiekit-syndicator-bluesky     version: "^1.1.6"
@rmdes/indiekit-endpoint-webmention-io version: "^1.2.3"
```

then `node scripts/validate.mjs`, commit and push the registry, and in `indiekit-cloudron`: `make registry-update`, commit the submodule pointer.

## 3. Deploy and check

```
make deploy SITE=rmendes APP=rmendes.net
make deploy SITE=chardonsbleus APP=v2.chardonsbleus.org
```

Wait for `[11ty] Wrote` in the logs (no `Eleventy Fatal Error`), then on rmendes.net:

- `/posts/create?type=bookmark&url=https://example.website/x&name=Test` pre-fills the bookmark field and the name (frontend + posts form; the posts *lookup* change is not in this deploy).
- `/share` offers a checkbox per syndication target and a chosen target reaches the post as `mp-syndicate-to`.
- `/micropub?q=source&filter=web&limit=5` returns only matching posts, paging works within the match.
- A note with `category=Cheese&category=+cheese+` ends up with one category.
- A Mastodon reply to a status on another server threads under it.
- The add-another button focuses the new item.

## 4. After `@indiekit/indiekit` 1.0.0-beta.30 lands on npm

`bin/upstream-watch` reports it under "published on npm". Then, per the ledger's untangle checklist (step 1b first: `git log v1.0.0-beta.30..origin/main -- packages/<pkg>` must be empty for each):

1. Delete the `@indiekit/endpoint-auth` and `@indiekit/endpoint-share` overrides in cloudron and deploy manifests; delete the `auth` and `share` registry entries (a versionless non-overridden entry would be added to the plugins array and load a default plugin twice).
2. Bump and publish `indiekit-endpoint-posts`, pin it, deploy; the core backfill runs at startup and the uid lookup becomes safe.
3. Fix the comment in the theme's `base.njk` (line ~150) that says the auth endpoints are served by the fork.
4. `npm deprecate` and archive auth, files and share.

Ledger: `documentation-central/plans/2026-09-13-fork-retirement-ledger.md`. Sync detail: `documentation-central/reports/2026-09-05-fork-upstream-sync.md`, rounds 4–7.
