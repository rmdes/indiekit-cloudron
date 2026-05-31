/**
 * Indiekit configuration for Cloudron
 * Documentation: https://getindiekit.com/configuration
 */

export default {
  application: {
    mongodbUrl: process.env.MONGODB_URL,
    url: process.env.CLOUDRON_APP_URL,
    name: "Indiekit",
    locale: "en",
    timeZone: "Europe/London",
  },

  publication: {
    me: "https://rmendes.net/",
    categories: ["blog", "notes", "links", "photos"],
    layouts: [
      { name: "Full width", path: "layouts/fullwidth.njk" },
    ],
  },

  plugins: [
    // PLAN B: this array is composed by scripts/compose-site.mjs from
    // sites/rmendes/config/plugins.yaml + plugin-registry/plugin-registry.yaml.
    // The marker below is replaced with the rendered package list at compose time.
    // Edit plugins.yaml (or `make plugin-add SITE=rmendes KEY=foo`), then `make
    // compose SITE=rmendes` to regenerate sites/rmendes/.compiled/indiekit.config.js.
{{PLUGINS}}
  ],

  // Local file storage - persisted in /app/data/content
  "@indiekit/store-file-system": {
    directory: "/app/data/content",
  },

  "@rmdes/indiekit-syndicator-mastodon": {
    url: "https://indieweb.social",
    user: "rmdes",
    accessToken: process.env.MASTODON_ACCESS_TOKEN,
    checked: false,
    syndicateExternalLikes: true,
    syndicateExternalReposts: true,
  },

  "@rmdes/indiekit-syndicator-bluesky": {
    handle: "rmendes.net",
    password: process.env.BLUESKY_PASSWORD,
    checked: true,
    syndicateExternalLikes: true,
    syndicateExternalReposts: true,
  },

  // LinkedIn syndicator - post notes and articles to LinkedIn
  "@rmdes/indiekit-syndicator-linkedin": {
    accessToken: process.env.LINKEDIN_ACCESS_TOKEN,
    authorName: "Ricardo Mendes",
    authorProfileUrl: "https://www.linkedin.com/in/mendesr/",
    checked: false,
  },

  // LinkedIn OAuth endpoint - manages access tokens
  "@rmdes/indiekit-endpoint-linkedin": {
    mountPath: "/linkedin",
    clientId: process.env.LINKEDIN_CLIENT_ID,
    clientSecret: process.env.LINKEDIN_CLIENT_SECRET,
  },

  // IndieNews syndicator - submit posts to IndieNews aggregator
  "@rmdes/indiekit-syndicator-indienews": {
    languages: ["en", "fr"],
    checked: false,
  },

  // GitHub activity endpoint - accessible at /githubapi (API for Eleventy widgets)
  "@rmdes/indiekit-endpoint-github": {
    mountPath: "/githubapi",
    username: "rmdes",
    token: process.env.GITHUB_TOKEN,
    cacheTtl: 900_000,
    limits: { commits: 10, stars: 20, repos: 10 },
    repos: [],
    featuredRepos: [
      "osintukraine/tg-archiver",
      "osintukraine/osint-intelligence-platform",
    ],
  },

  // Funkwhale listening activity endpoint
  "@rmdes/indiekit-endpoint-funkwhale": {
    mountPath: "/funkwhaleapi",
    instanceUrl: process.env.FUNKWHALE_INSTANCE,
    username: process.env.FUNKWHALE_USERNAME,
    token: process.env.FUNKWHALE_TOKEN,
    cacheTtl: 900_000,
    syncInterval: 300_000,
    limits: {
      listenings: 20,
      favorites: 20,
      topArtists: 10,
      topAlbums: 10,
    },
  },

  // Last.fm listening activity endpoint - accessible at /lastfmapi
  "@rmdes/indiekit-endpoint-lastfm": {
    mountPath: "/lastfmapi",
    apiKey: process.env.LASTFM_API_KEY,
    username: process.env.LASTFM_USERNAME,
    cacheTtl: 900_000,
    syncInterval: 300_000,
    limits: {
      scrobbles: 20,
      loved: 20,
      topArtists: 10,
      topAlbums: 10,
    },
  },

  // YouTube channel endpoint - accessible at /youtubeapi
  "@rmdes/indiekit-endpoint-youtube": {
    mountPath: "/youtubeapi",
    apiKey: process.env.YOUTUBE_API_KEY,
    channels: process.env.YOUTUBE_CHANNELS?.split(",").map((handle) => ({
      handle: handle.trim(),
      name: handle.trim().replace("@", ""),
    })) || [],
    cacheTtl: 300_000,
    liveCacheTtl: 60_000,
    limits: { videos: 10 },
  },

  // RSS feed reader endpoint - accessible at /rssapi
  // Admin dashboard at /rssapi/, public API for Eleventy at /rssapi/api/*
  "@rmdes/indiekit-endpoint-rss": {
    mountPath: "/rssapi",
    syncInterval: 900_000, // 15 minutes
    maxItemsPerFeed: 50,
    fetchTimeout: 10_000,
    maxConcurrentFetches: 3,
  },

  // Microsub social reader - accessible at /microsub (API) and /microsub/reader (UI)
  "@rmdes/indiekit-endpoint-microsub": {
    mountPath: "/microsub",
    // Redis is optional but enables real-time SSE updates
    redisUrl: process.env.REDIS_URL,
  },

  // Webmention moderation — MongoDB cache, blocklist, privacy removal, public API
  // Admin dashboard at /webmentions, public API at /webmentions/api/mentions
  "@rmdes/indiekit-endpoint-webmention-io": {
    token: process.env.WEBMENTION_IO_TOKEN,
    domain: "rmendes.net",
    syncInterval: 900_000, // 15 minutes
    cacheTtl: 60,
  },

  // Podroll endpoint - aggregates podcast episodes from FreshRSS
  // Powers the /podroll/ page with episode listings and OPML sidebar
  "@rmdes/indiekit-endpoint-podroll": {
    mountPath: "/podrollapi",
    episodesUrl: process.env.PODROLL_EPISODES_URL,
    opmlUrl: process.env.PODROLL_OPML_URL,
    syncInterval: 900_000, // 15 minutes
    maxEpisodes: 100,
  },

  // Blogroll endpoint - aggregates blogs from OPML sources
  // Admin dashboard at /blogrollapi/, public API at /blogrollapi/api/*
  "@rmdes/indiekit-endpoint-blogroll": {
    mountPath: "/blogrollapi",
    syncInterval: 900_000, // 15 minutes
    maxItemAge: 7, // Keep items for 7 days to encourage fresh discovery
  },

  // CV editor - admin UI at /cv, public API at /cv/data.json
  "@rmdes/indiekit-endpoint-cv": {
    mountPath: "/cv",
  },

  // Conversations - threaded discussion view for posts
  // Admin UI at /conversations, public API at /conversations/api/post
  "@rmdes/indiekit-endpoint-conversations": {
    mountPath: "/conversations",
  },

  // Comments - IndieAuth-based comment system for blog posts
  // Admin dashboard at /comments, JF2 API at /comments/api/comments
  // Auth flow at /comments/api/auth, submit at /comments/api/submit
  "@rmdes/indiekit-endpoint-comments": {
    mountPath: "/comments",
    replyTargets: {
      mastodon: "ActivityPub (Fediverse)",
      activitypub: "ActivityPub (Fediverse)",
      bluesky: "Bluesky",
    },
  },

  // ActivityPub federation — makes the site a full AP actor (@rick@rmendes.net)
  // Admin UI at /activitypub, federation at /activitypub/inbox, /activitypub/outbox, etc.
  "@rmdes/indiekit-endpoint-activitypub": {
    mountPath: "/activitypub",
    actor: {
      handle: "rick",
      name: "Ricardo Mendes",
      summary: "Personal website of Ricardo Mendes",
      icon: "https://rmendes.net/images/user/avatar.jpg",
    },
    checked: true,
    alsoKnownAs: "",
    activityRetentionDays: 90,
    storeRawActivities: false,
    redisUrl: process.env.CLOUDRON_REDIS_URL || "",
    parallelWorkers: 5,
    actorType: "Person",
    // Fedify log level — controls verbosity of federation logs in container output
    // Uncomment ONE of the following lines (restart required to take effect):
    logLevel: "info",          // Debugging — delivery attempts, HTTP signatures, queue processing
    // logLevel: "info",       // Debugging — delivery attempts, HTTP signatures, queue processing
    // logLevel: "debug",      // Full Fedify internals — very verbose
    // logLevel: "error",      // Errors only — minimal output
    // Fedify 2.0 debug dashboard — live traces, activities, HTTP signatures, OpenTelemetry
    // Accessible at /activitypub/__debug__/ (password-protected)
    debugDashboard: false,
    debugPassword: "kX9mQ7vR3pW2nJ8s",
  },
};
