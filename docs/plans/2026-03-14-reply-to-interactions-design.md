# Design: Reply-to-Interactions

**Date:** 2026-03-14
**Status:** APPROVED
**Scope:** indiekit-endpoint-comments, indiekit-eleventy-theme

## Problem

The site owner cannot reply to interactions (webmentions, social media backfills, native comments) displayed under their posts. Visitors from Bluesky, Mastodon, or the IndieWeb who interact with content receive no direct response from the author. There is no reply button, no provenance display showing where interactions originate, and the admin session is disconnected from the comments system.

## Goals

1. Site owner can reply to any interaction from any post page
2. Replies route to the correct platform (Bluesky reply threads on Bluesky, Mastodon reply threads on Mastodon, IndieWeb replies send webmentions)
3. Owner replies display threaded under the interaction they respond to
4. Platform provenance badges show where each interaction originated
5. Owner is visually distinguished with an "Author" badge
6. No duplicate syndication — replies only syndicate to the relevant platform

## Decisions

| Question | Decision |
|----------|----------|
| Reply form UX | Inline form on the post page (Alpine.js), POSTs to Micropub |
| Owner detection | Auto-detect admin session, bypass IndieAuth sign-in |
| Reply targets | All three interaction types from day one |
| Owner visual distinction | "Author" badge next to name |
| Provenance badges | Add to post views (ported from /interactions page) |
| Reply threading display | Inline threaded, one level deep |
| Reply data retrieval | Client-side API fetch (not build-time Eleventy) |
| Syndication override | Reply only syndicates to the matching platform |
| Native comment replies | Stored in comment_items with parent_id (not Micropub) |

## Architecture

### Existing Infrastructure (No Changes Needed)

Both syndicators already support reply threading:

- **Bluesky syndicator:** `resolveReplyRef(postUrl)` fetches AT Protocol `{root, parent}` references when `in-reply-to` contains a bsky.app URL. Posts as a threaded reply on Bluesky.
- **Mastodon syndicator:** `resolveRemoteStatus(statusUrl)` uses Mastodon v2 search API with `resolve: true` to get the local status ID for cross-instance threading. Posts as a threaded reply on Mastodon.
- **Micropub endpoint:** Standard `mp-syndicate-to` in request body overrides default syndication targets.
- **Webmention sender:** Automatically sends webmentions for reply posts with `in-reply-to`.
- **Conversation items:** The `url` field already stores the platform-specific URL needed by both syndicators.

### Component 1: Owner Detection & Admin Session Bridge

**New endpoint in `indiekit-endpoint-comments`:**

```
GET /comments/api/is-owner
```

Checks the existing Indiekit admin session cookie. Returns:

```json
// 200 — owner is logged in
{
  "isOwner": true,
  "name": "Ricardo Mendes",
  "url": "https://rmendes.net/",
  "photo": "https://rmendes.net/photo.jpg",
  "syndicationTargets": {
    "bluesky": "https://bsky.app/profile/rmendes.net",
    "mastodon": "https://indieweb.social/@rmdes"
  }
}

// 401 — not the owner
{ "isOwner": false }
```

The `syndicationTargets` map provides the syndicator UIDs the frontend needs to set `mp-syndicate-to` correctly per provenance.

**Frontend behavior when owner detected:**
- Hide the IndieAuth sign-in form
- Show "Author" badge on owner's existing comments
- Show Reply buttons on all interactions
- Pre-populate reply form author info

### Component 2: Inline Reply Form

Alpine.js component that renders below any interaction when the owner clicks "Reply."

**UI flow:**
1. Reply button appears on each interaction (owner only)
2. Click expands a textarea below that interaction
3. Textarea has "Send Reply" button and "Cancel" link
4. Submit shows spinner, then success/error message
5. On success, reply renders inline immediately (optimistic UI)

**Data attributes on each Reply button:**

```html
<button
  data-reply-url="https://bsky.app/profile/user/post/123"
  data-platform="bluesky"
  data-syndicate-to="https://bsky.app/profile/rmendes.net"
>Reply</button>
```

**Submit behavior by provenance:**

For Bluesky, Mastodon, and IndieWeb webmention interactions — POST to `/micropub`:

```json
{
  "type": ["h-entry"],
  "properties": {
    "content": ["Owner's reply text"],
    "in-reply-to": ["https://bsky.app/profile/user/post/123"],
    "mp-syndicate-to": ["https://bsky.app/profile/rmendes.net"]
  }
}
```

For native comment replies — POST to `/comments/api/reply`:

```json
{
  "parent_id": "comment-object-id",
  "content": "Owner's reply text",
  "target": "/notes/2026/03/03/8a851/"
}
```

### Component 3: Syndication Target Override

When replying to a provenance-specific interaction, only the matching syndicator fires. The inline reply form explicitly sets `mp-syndicate-to` based on provenance, overriding the defaults (where both Bluesky and Mastodon are pre-checked).

| Replying to | `mp-syndicate-to` | Result |
|-------------|-------------------|--------|
| Bluesky interaction | `["bluesky-uid"]` | Threaded reply on Bluesky only |
| Mastodon interaction | `["mastodon-uid"]` | Threaded reply on Mastodon only |
| IndieWeb webmention | `[]` (empty) | No syndication — webmention sender delivers |
| Native comment | N/A (not Micropub) | Stored in comment_items only |

The syndicator UIDs are provided by the `/api/is-owner` response and mapped by the frontend using the interaction's `platform` field.

### Component 4: Provenance Badges on Post Views

Port the platform badge system from `interactions.njk` to post view components.

**Badge types:**
- Mastodon — purple Mastodon logo SVG
- Bluesky — blue butterfly SVG
- ActivityPub/Fediverse — purple fediverse icon SVG
- IndieWeb — rose webmention icon SVG
- No badge for native comments

**Platform detection:**
- Conversation items: `platform` field already present in JF2 API response
- Webmention-io items: Heuristic detection via `detectPlatform()` (checks `wm-source` for brid.gy patterns, author URL domain matching for known instances)

**Rendered in:**
- `webmentions.njk` — build-time interactions
- `webmentions.js` — client-side dynamically loaded interactions
- `comments.njk` / `comments.js` — native comments (no badge, but owner replies get "Author" badge)

### Component 5: Threaded Reply Display

Owner replies display nested under the interaction they respond to, one level deep.

**For Micropub replies (social/webmention interactions):**

New endpoint:

```
GET /comments/api/owner-replies?target={postUrl}
```

Queries the posts collection for owner posts where `properties.in-reply-to` matches any interaction URL associated with the target post. Returns a list of reply posts with their `in-reply-to` value as the threading key.

The frontend matches each reply's `in-reply-to` against the displayed interactions' source URLs and renders the reply indented below its parent.

**For native comment replies:**

The `comment_items` collection gets an optional `parent_id` field (MongoDB ObjectId reference). The existing `/comments/api/comments?target={url}` response includes `_id` and `parent_id` on each comment. The Alpine.js component groups comments by parent and renders children indented below.

**Display styling:**
- Indented with a subtle left border
- "Author" badge next to owner's name
- Avatar, reply content, timestamp
- One level deep only (no nested reply chains)

### Component 6: Native Comment Reply Schema

**Schema change to `comment_items`:**

```javascript
{
  _id: ObjectId,
  target: String,
  author: { url, name, photo },
  content: { text, html },
  published: String,       // ISO 8601
  status: String,          // "public" | "deleted"
  ip_hash: String,
  parent_id: ObjectId|null // NEW — references parent comment's _id
}
```

**New endpoint:**

```
POST /comments/api/reply
```

Accepts owner reply to a native comment. Validates admin session, stores in `comment_items` with `parent_id` set. Author populated from admin session profile.

### Component 7: Bug Fix — Comments Auto-Expand

The Comments `<details>` element should be `open` when comments exist. After the `/comments/api/comments` fetch returns with `comments.length > 0`, set the details element to open.

## File Changes

### indiekit-endpoint-comments

| File | Change |
|------|--------|
| `lib/controllers/comments.js` | Add `isOwner` endpoint, `ownerReplies` endpoint, `submitReply` handler |
| `lib/storage/comment-items.js` | Add `parent_id` support, include `_id` in API responses |
| `lib/transforms/jf2.js` | Include `_id` and `parent_id` in JF2 output |
| `index.js` | Register new routes |

### indiekit-eleventy-theme

| File | Change |
|------|--------|
| `_includes/components/comments.njk` | Owner detection, Reply buttons, inline form, auto-expand, Author badge, threaded display |
| `_includes/components/webmentions.njk` | Provenance badges, Reply buttons (owner only), threaded owner reply display |
| `js/comments.js` | Owner session check, inline reply form Alpine.js logic, optimistic rendering, native comment reply submission |
| `js/webmentions.js` | Provenance badges, Reply buttons, `detectPlatform()`, threaded owner reply display |

## Data Flow Diagrams

### Replying to a social media interaction

```
Owner clicks Reply on Bluesky interaction
  |
  v
Inline textarea expands below interaction
  |
  v
Owner types reply, clicks Send
  |
  v
Frontend POST /micropub
  { content, in-reply-to: bsky.app/..., mp-syndicate-to: [bluesky-uid] }
  |
  v
Micropub creates reply post
  |
  +---> Bluesky syndicator fires
  |       resolveReplyRef() -> threaded reply on Bluesky
  |
  +---> Webmention sender fires
  |       sends webmention to bsky.app URL (may be ignored, harmless)
  |
  v
Frontend renders reply inline with Author badge (optimistic)
  |
  v
Next page load: /api/owner-replies confirms the reply
```

### Replying to a native comment

```
Owner clicks Reply on visitor's comment
  |
  v
Inline textarea expands below comment
  |
  v
Owner types reply, clicks Send
  |
  v
Frontend POST /comments/api/reply
  { parent_id: "abc123", content: "...", target: "/post-url" }
  |
  v
Stored in comment_items with parent_id
  |
  v
Frontend renders reply threaded under parent with Author badge
```

### Replying to an IndieWeb webmention

```
Owner clicks Reply on webmention interaction
  |
  v
Inline textarea expands below interaction
  |
  v
Owner types reply, clicks Send
  |
  v
Frontend POST /micropub
  { content, in-reply-to: source-site.com/post, mp-syndicate-to: [] }
  |
  v
Micropub creates reply post (no syndication)
  |
  +---> Webmention sender fires
          sends webmention to source-site.com/post
          -> reply appears on commenter's site
  |
  v
Frontend renders reply inline with Author badge (optimistic)
```

## Edge Cases

| Case | Behavior |
|------|----------|
| Deleted source post | Syndicator's resolveReplyRef/resolveRemoteStatus fails gracefully — reply posts as standalone, not threaded |
| Private/followers-only Mastodon status | resolveRemoteStatus may fail — reply posts as standalone |
| Bridgy Fed interactions | Use `conversation_items.url` (original platform URL), not `bridgy_url` |
| Multi-syndicated post | Reply only syndicates to matching platform via explicit `mp-syndicate-to` |
| ActivityPub interactions | Route through Mastodon syndicator if URL is Mastodon-compatible |
| Rate limits | Syndicators handle 429 retry — frontend shows error if reply fails |
| Owner replies to own comment | Allowed — parent_id points to own comment, displayed threaded |

## Out of Scope

- Inline form upgrade to support photos/formatting (future enhancement)
- Reply notifications to commenters (email, push)
- Multi-level reply threading (only one level deep)
- Editing or deleting owner replies after posting
- Unifying admin and comments auth sessions globally (only bridged for owner detection)
