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

---

# Execution record — Framework laptop, 2026-10-10 19:00–19:45Z

Everything in sections 1–2 is done. Both sites deployed and verified.

## Published (10, not 9)

All nine from section 1, plus **`@rmdes/indiekit-endpoint-funkwhale` 1.0.17** —
fixed on this laptop after the handover was written (PR #1, merged 18:58 CEST:
legacy `Date` `listenedAt` values sorted above every ISO string in MongoDB, so
incremental sync refetched 80 API pages every 5 minutes). Registry pinned
`^1.0.16` → `^1.0.17`.

dist-tags: `micropub@1.0.0-beta.39` and `preset-eleventy@1.0.0-beta.41` published
but their `latest` move failed separately (see "publish round" below); both
corrected afterwards. All ten now have `latest` where intended.

## Pins

- `indiekit-cloudron/package.json` overrides — 5, exact (commit 9b719cd)
- `indiekit-deploy/package.json` overrides — 5, caret (its own convention) (d9afec2)
- `plugin-registry.yaml` — 5 ranges incl. funkwhale, `validate.mjs`: 47 plugins / 4 tiers (26077e9)
- Submodule pointer committed; `make compose` on both sites
- **Loadout diff gate: plugin sets identical** (rmendes 45, chardonsbleus 34); only
  the intended version deltas (5 and 4 — funkwhale is not in chardonsbleus's set)

## Deployed

| | rmendes.net | v2.chardonsbleus.org |
|---|---|---|
| Image | build227 | build176 |
| Pins verified in container | 11/11 | 9/9 |
| Eleventy build | 400.7s, state ok | 7.3s, state ok |
| Swap | → 1791660832 (3,547 files) | → 1791660980 (39 files) |
| Fatals | none | none |

Versions were verified by reading `/app/code/node_modules/*/package.json` in each
container, NOT from `cloudron update` saying "App is updated" — a failed image
push prints that too (it happened earlier the same day; see below).

## Section 3 checks

RUN AT RUNTIME, PASSING:
- `q=config` post-type discovery by vocabulary — 13 types
- `q=source` cursor paging via `after`/`before`
- **Category normalisation on write** — called `normaliseProperties` from the
  installed `jf2.js` inside the container (a pure function, so no post created):
  `["Cheese"," cheese "]`→`["Cheese"]`; `["CHEESE","cheese","Cheese"]`→`["Cheese"]`;
  `["Cheese","brandnewtag"]`→ both kept; bare `"Cheese"`→`["Cheese"]`.
  Not proven: that a real Micropub write routes through it. That needs a post.

RUN AT RUNTIME, **FAILING** — see section 4 addition 1:
- `/micropub?q=source&filter=web&limit=5` does NOT filter. `filter=zzzqqqnotathing`
  returns a full page.

NOT RUN — need an authenticated admin session (workspace CLAUDE.md forbids
Playwright against rmendes without the user logging in) or real federated
activity:
- `/posts/create?type=bookmark&url=…&name=Test` pre-fill
- `/share` checkbox per syndication target
- add-another button focuses the new item
- a Mastodon reply to a status on another server threads under it

Both routes return **302 to auth** (mounted, new code loads cleanly, not 500), and
the behaviours are present in the deployed artifacts (`share.njk` has
`checkboxes`/`syndicate-to`; `add-another/index.js:51` `$focusable.focus()`;
`posts/lib/controllers/new.js:16` reads `request.query`). That is static presence,
NOT a passing test — do not record it as one.

## Section 4 — two additions

**1. `q=source&filter=` and `&category=` are inert until core beta.30.**
micropub beta.39 calls

    getCursor(postsCollection, after, before, limit, { filter: postsFilter })

but `@indiekit/util` **beta.29** declares

    export const getCursor = async (collection, after, before, limit) => {

JavaScript discards the fifth argument silently, so a correct Mongo filter is
built and thrown away. Same shape of dependency the handover already caught for
`endpoint-posts` — upstream's `filter` work landed alongside a `getCursor`
signature change — but it failed silently rather than loudly, so nothing flagged
it. No regression: `q=source` and cursor paging are unaffected, and `filter`
replaced the fork's `search`. It starts working with NO code change when beta.30
lands; add it to the step-2 verification list there.

**2. `indiekit-deploy` still carries the `@indiekit/endpoint-files` override.**
indiekit-cloudron retired it 2026-10-07 (aee94ed) because upstream absorbed
multi-file upload and then hardened the same path, leaving the fork behind. The
same reasoning applies here. Left in place: separate deployment, own cadence, not
part of this round.

## Incidental fixes (not in the handover)

- **`make push-env` reported success on a failed push.** It chained the push and
  the "==> Done" message with `;` inside one `@if … fi` block, discarding the exit
  status. Now `|| { …; exit 1; }` naming the likely cause.
- **Every Docker push had been failing since 2026-08-29.**
  `~/.gnupg/public-keys.d/pubring.db.lock` was held by a dead PID (22977), so
  `docker-credential-pass` could not reach the keyring; the error reads
  `gpg: decryption failed: No secret key` + `are you logged in?`, which points at
  credentials rather than a stale lock. `gpgconf --kill gpg-agent` is NOT enough —
  the lock is a file; it has to be removed once its PID is confirmed dead.
- **`cloudron` CLI fails ~50% of calls with `ENETUNREACH`** — this host has no
  IPv6 default route while the instances publish AAAA. Always
  `export NODE_OPTIONS="--dns-result-order=ipv4first"` before a `make deploy`.
- **`indiekit-scripts/publish-all.sh` rewritten.** The round took ~25 minutes and
  reported "1 published, 9 failed" when 6 had in fact published. Causes: npm 11
  defaults to `auth-type=web`, one browser approval per operation with a ~5 minute
  TTL (15 approvals for this round, five timed out); verification polled per
  package mid-flight; and "already published" was treated as "done", so a failed
  dist-tag could not be repaired by re-running. Now: auth preflight, plan printed
  in full before anything ships, publishes, dist-tags grouped after, ONE
  verification sweep at the end, and `--repair-tags` for a stale `latest`.
  `--auth-type=legacy` is NOT usable on this account — it prompts for a TOTP code,
  and the account authenticates with a passkey. `--latest-never` halves the
  approvals; a granular token with "bypass 2FA for automation" removes them.
