/**
 * Indiekit configuration for Cloudron
 *
 * This is an IndieWeb-ready blog deployment with full Micropub support.
 * Documentation: https://getindiekit.com/configuration
 *
 * Required environment variables (set in Cloudron app settings):
 * - SITE_URL: Your site URL (e.g., https://example.com)
 *
 * Optional syndication (set to enable):
 * - MASTODON_INSTANCE: Mastodon instance URL (e.g., https://mastodon.social)
 * - MASTODON_USER: Your Mastodon username
 * - MASTODON_ACCESS_TOKEN: Mastodon access token
 * - BLUESKY_HANDLE: Your Bluesky handle (e.g., you.bsky.social)
 * - BLUESKY_PASSWORD: Bluesky app password
 * - BLUESKY_PDS_URL: Bluesky PDS URL (default: https://bsky.social)
 * - BLUESKY_PDS_HANDLE: Your Bluesky handle for PDS OAuth (e.g., you.bsky.social)
 * - LINKEDIN_ACCESS_TOKEN: LinkedIn access token (or use OAuth flow at /linkedin)
 * - LINKEDIN_AUTHOR_NAME: Your name on LinkedIn
 * - LINKEDIN_PROFILE_URL: Your LinkedIn profile URL
 * - LINKEDIN_CLIENT_ID: LinkedIn OAuth app Client ID
 * - LINKEDIN_CLIENT_SECRET: LinkedIn OAuth app Client Secret
 *
 * Optional integrations:
 * - GITHUB_USERNAME: GitHub username for activity display
 * - GITHUB_TOKEN: GitHub personal access token
 * - GITHUB_FEATURED_REPOS: Comma-separated repos (e.g., "user/repo1,user/repo2")
 * - FUNKWHALE_INSTANCE: Funkwhale instance URL
 * - FUNKWHALE_USERNAME: Funkwhale username
 * - FUNKWHALE_TOKEN: Funkwhale API token
 * - LASTFM_API_KEY: Last.fm API key (get from https://www.last.fm/api/account/create)
 * - LASTFM_USERNAME: Last.fm username
 * - YOUTUBE_API_KEY: YouTube Data API key
 * - YOUTUBE_CHANNELS: Comma-separated channel handles (e.g., "@channel1,@channel2")
 * - WEBMENTION_IO_TOKEN: Webmention.io token (get from https://webmention.io/settings)
 */

export default {
  application: {
    mongodbUrl: process.env.MONGODB_URL,
    // Redis URL for caching (Cloudron provides CLOUDRON_REDIS_* env vars)
    redisUrl: process.env.CLOUDRON_REDIS_HOST
      ? `redis://${process.env.CLOUDRON_REDIS_PASSWORD ? `:${process.env.CLOUDRON_REDIS_PASSWORD}@` : ""}${process.env.CLOUDRON_REDIS_HOST}:${process.env.CLOUDRON_REDIS_PORT || 6379}`
      : undefined,
    url: process.env.CLOUDRON_APP_URL,
    name: process.env.SITE_NAME || "My IndieWeb Blog",
    locale: process.env.SITE_LOCALE || "en",
    timeZone: process.env.SITE_TIMEZONE || "UTC",
  },

  publication: {
    me: process.env.SITE_URL,
    categories: process.env.SITE_CATEGORIES?.split(",") || ["blog", "notes", "links", "photos"],
    // Optional layouts for the post editor's layout selector
    // layouts: [
    //   { name: "Full width", path: "layouts/fullwidth.njk" },
    // ],
  },

  plugins: [
{{PLUGINS}}
  ],

  // Local file storage - persisted in /app/data/content
  "@indiekit/store-file-system": {
    directory: "/app/data/content",
  },

  // Mastodon syndication (optional - configure via env vars)
  // Custom version that syndicates likes of external URLs as posts
  "@rmdes/indiekit-syndicator-mastodon": {
    url: process.env.MASTODON_INSTANCE,
    user: process.env.MASTODON_USER,
    accessToken: process.env.MASTODON_ACCESS_TOKEN,
    checked: !!process.env.MASTODON_ACCESS_TOKEN,
    syndicateExternalLikes: true, // Post likes of external URLs as statuses
    syndicateExternalReposts: true, // Post reposts of external URLs as statuses
  },

  // Bluesky syndication (optional - configure via env vars)
  // Custom version that syndicates likes and reposts of external URLs as posts
  "@rmdes/indiekit-syndicator-bluesky": {
    handle: process.env.BLUESKY_HANDLE,
    password: process.env.BLUESKY_PASSWORD,
    checked: !!process.env.BLUESKY_PASSWORD,
    syndicateExternalLikes: true, // Post likes of external URLs as posts
    syndicateExternalReposts: true, // Post reposts of external URLs as posts
  },

  // Bluesky PDS endpoint — AT Protocol record management via OAuth
  // Admin UI at /bluesky-pds, handles site.standard.publication sync
  "@rmdes/indiekit-endpoint-bluesky-pds": {
    pdsUrl: process.env.BLUESKY_PDS_URL || "https://bsky.social",
    handle: process.env.BLUESKY_PDS_HANDLE || "",
    enableStandardSiteDocument: true,
    mountPath: "/bluesky-pds",
  },

  // LinkedIn syndication (optional - configure via env vars)
  // Posts notes and articles to LinkedIn
  "@rmdes/indiekit-syndicator-linkedin": {
    accessToken: process.env.LINKEDIN_ACCESS_TOKEN,
    authorName: process.env.LINKEDIN_AUTHOR_NAME,
    authorProfileUrl: process.env.LINKEDIN_PROFILE_URL,
    checked: !!process.env.LINKEDIN_ACCESS_TOKEN,
  },

  // LinkedIn OAuth endpoint - manages access tokens via OAuth flow
  // Visit /linkedin to connect your account
  "@rmdes/indiekit-endpoint-linkedin": {
    mountPath: "/linkedin",
    clientId: process.env.LINKEDIN_CLIENT_ID,
    clientSecret: process.env.LINKEDIN_CLIENT_SECRET,
  },

  // IndieNews syndicator (optional) - submit posts to IndieNews aggregator
  // Configure languages via env var: INDIENEWS_LANGUAGES=en,fr
  "@rmdes/indiekit-syndicator-indienews": {
    languages: process.env.INDIENEWS_LANGUAGES?.split(",") || ["en"],
    checked: false,
  },

  // GitHub activity endpoint (optional)
  // Accessible at /githubapi - powers the GitHub activity page
  "@rmdes/indiekit-endpoint-github": {
    mountPath: "/githubapi",
    username: process.env.GITHUB_USERNAME,
    token: process.env.GITHUB_TOKEN,
    cacheTtl: 900_000, // 15 minutes
    limits: { commits: 10, stars: 20, contributions: 10, activity: 20, repos: 10 },
    repos: [],
    featuredRepos: process.env.GITHUB_FEATURED_REPOS?.split(",") || [],
  },

  // Funkwhale listening activity endpoint (optional)
  // Accessible at /funkwhaleapi - powers the listening activity page
  "@rmdes/indiekit-endpoint-funkwhale": {
    mountPath: "/funkwhaleapi",
    instanceUrl: process.env.FUNKWHALE_INSTANCE,
    username: process.env.FUNKWHALE_USERNAME,
    token: process.env.FUNKWHALE_TOKEN,
    cacheTtl: 900_000, // 15 minutes
    syncInterval: 300_000, // 5 minutes
    limits: {
      listenings: 20,
      favorites: 20,
      topArtists: 10,
      topAlbums: 10,
    },
  },

  // Last.fm listening activity endpoint (optional)
  // Accessible at /lastfmapi - powers the listening activity page
  "@rmdes/indiekit-endpoint-lastfm": {
    mountPath: "/lastfmapi",
    apiKey: process.env.LASTFM_API_KEY,
    username: process.env.LASTFM_USERNAME,
    cacheTtl: 900_000, // 15 minutes
    syncInterval: 300_000, // 5 minutes
    limits: {
      scrobbles: 20,
      loved: 20,
      topArtists: 10,
      topAlbums: 10,
    },
  },

  // YouTube channel endpoint (optional)
  // Accessible at /youtubeapi - powers the YouTube activity page
  "@rmdes/indiekit-endpoint-youtube": {
    mountPath: "/youtubeapi",
    apiKey: process.env.YOUTUBE_API_KEY,
    channels: process.env.YOUTUBE_CHANNELS?.split(",").map((handle) => ({
      handle: handle.trim(),
      name: handle.trim().replace("@", ""),
    })) || [],
    cacheTtl: 300_000, // 5 minutes
    liveCacheTtl: 60_000, // 1 minute for live status
    limits: { videos: 10 },
  },

  // RSS feed reader endpoint (optional)
  // Accessible at /rssapi - powers the /news/ page
  // Add feeds via the admin UI at /rssapi/
  "@rmdes/indiekit-endpoint-rss": {
    mountPath: "/rssapi",
    syncInterval: 900_000, // 15 minutes
    maxItemsPerFeed: 50,
    fetchTimeout: 10_000,
    maxConcurrentFetches: 3,
  },

  // Webmention moderation endpoint
  // MongoDB-backed webmention cache with blocklist, privacy removal, and public API
  // Admin dashboard at /webmentions, public API at /webmentions/api/mentions
  "@rmdes/indiekit-endpoint-webmention-io": {
    token: process.env.WEBMENTION_IO_TOKEN,
    domain: process.env.SITE_URL?.replace(/^https?:\/\//, "").replace(/\/$/, ""),
    syncInterval: 900_000, // 15 minutes
    cacheTtl: 60,
  },

  // Podroll endpoint (optional)
  // Aggregates podcast episodes from FreshRSS, powers the /podroll/ page
  // Requires FreshRSS API URL and OPML export URL
  "@rmdes/indiekit-endpoint-podroll": {
    mountPath: "/podrollapi",
    episodesUrl: process.env.PODROLL_EPISODES_URL,
    opmlUrl: process.env.PODROLL_OPML_URL,
    syncInterval: 900_000, // 15 minutes
    maxEpisodes: 100,
  },

  // Blogroll endpoint (optional)
  // Aggregates blogs from OPML sources and RSS feeds
  // Admin dashboard at /blogrollapi/, public API at /blogrollapi/api/*
  "@rmdes/indiekit-endpoint-blogroll": {
    mountPath: "/blogrollapi",
    syncInterval: 900_000, // 15 minutes
    maxItemAge: 7, // Keep items for 7 days to encourage fresh discovery
  },

  // CV/Resume editor endpoint (optional)
  // Admin UI at /cv for managing work experience, projects, skills, etc.
  // Public API at GET /cv/data.json
  "@rmdes/indiekit-endpoint-cv": {
    mountPath: "/cv",
  },

  // Conversations - backend enrichment polling Mastodon/Bluesky notifications
  // Admin dashboard at /conversations, JF2 API at /conversations/api/mentions
  // Auto-detects credentials from env vars (MASTODON_ACCESS_TOKEN, BLUESKY_PASSWORD)
  // Webhook ingest at /conversations/ingest, health check at /conversations/api/status
  "@rmdes/indiekit-endpoint-conversations": {
    mountPath: "/conversations",
  },

  // Comments - IndieAuth-based comment system for blog posts
  // Admin dashboard at /comments, JF2 API at /comments/api/comments
  // Auth flow at /comments/api/auth, submit at /comments/api/submit
  // replyTargets maps detected platform → syndicator service.name for frontend replies.
  // With self-hosted AP: mastodon/activitypub → "ActivityPub (Fediverse)"
  // Without AP (external account only): mastodon → "Mastodon"
  "@rmdes/indiekit-endpoint-comments": {
    mountPath: "/comments",
    replyTargets: {
      mastodon: "ActivityPub (Fediverse)",
      activitypub: "ActivityPub (Fediverse)",
      bluesky: "Bluesky",
    },
  },

  // ActivityPub federation — makes the site a full AP actor
  // Admin UI at /activitypub, federation at /activitypub/inbox, /activitypub/outbox, etc.
  // Set AP_ACTOR_HANDLE, AP_ACTOR_NAME, AP_ACTOR_SUMMARY, AP_ACTOR_ICON env vars
  "@rmdes/indiekit-endpoint-activitypub": {
    mountPath: "/activitypub",
    actor: {
      handle: process.env.AP_ACTOR_HANDLE || "me",
      name: process.env.AP_ACTOR_NAME || "",
      summary: process.env.AP_ACTOR_SUMMARY || "",
      icon: process.env.AP_ACTOR_ICON || "",
    },
    checked: true,
    alsoKnownAs: process.env.AP_ALSO_KNOWN_AS || "",
    activityRetentionDays: 90,
    storeRawActivities: false,
    redisUrl: process.env.CLOUDRON_REDIS_URL || "",
    parallelWorkers: 5,
    actorType: process.env.AP_ACTOR_TYPE || "Person",
    // Fedify log level — controls verbosity of federation logs in container output
    // Uncomment ONE of the following lines (restart required to take effect):
    logLevel: "warning",       // Production default — only warnings and errors
    // logLevel: "info",       // Debugging — delivery attempts, HTTP signatures, queue processing
    // logLevel: "debug",      // Full Fedify internals — very verbose
    // logLevel: "error",      // Errors only — minimal output
    // Fedify 2.0 debug dashboard — live traces, activities, HTTP signatures, OpenTelemetry
    // Accessible at {mountPath}/__debug__/ (set a password to protect it!)
    // debugDashboard: true,
    // debugPassword: process.env.AP_DEBUG_PASSWORD || "",
  },
};
