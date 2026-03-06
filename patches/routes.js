// Patched version of @indiekit/indiekit/lib/routes.js
//
// Changes from upstream (1.0.0-beta.25):
// - Removed rate limiting from authenticated routes (after indieauth.authenticate())
//   Authenticated routes are already protected by the auth middleware. Applying
//   rate limiting to them punishes legitimate admin users during normal browsing,
//   because each page view (posts, plugins, status, custom endpoints) counts
//   against the same shared pool.
// - Split rate limiting into two tiers:
//   - sessionLimit (50/15min): Session/auth routes — strict brute force protection
//   - apiLimit (1000/15min): Public API + .well-known endpoints — generous for
//     legitimate use (Interactions page fetches many API pages in sequence)

import path from "node:path";

import { assetsPath } from "@indiekit/frontend";
import express from "express";
import rateLimit from "express-rate-limit";

import * as assetsController from "./controllers/assets.js";
import * as clientController from "./controllers/client.js";
import * as feedController from "./controllers/feed.js";
import * as homepageController from "./controllers/homepage.js";
import * as manifestController from "./controllers/manifest.js";
import * as offlineController from "./controllers/offline.js";
import * as pluginController from "./controllers/plugin.js";
import * as sessionController from "./controllers/session.js";
import * as statusController from "./controllers/status.js";
import { IndieAuth } from "./indieauth.js";

const router = express.Router();

// Strict rate limiter for session/auth routes (brute force protection)
const sessionLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 50,
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
});

// Generous rate limiter for public API endpoints (read-only data)
const apiLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
  validate: false,
});

/**
 * Expose configuration to frontend templates and plug-ins
 * @param {object} Indiekit - Indiekit instance
 * @returns {import("express").Router} Express router
 */
export const routes = (Indiekit) => {
  const { endpoints, installedPlugins, publication } = Indiekit;

  const indieauth = new IndieAuth({
    devMode: process.env.NODE_ENV === "development",
    me: publication.me,
  });

  // Prevent pages from being indexed
  router.use((request, response, next) => {
    response.setHeader("X-Robots-Tag", "noindex");
    next();
  });
  router.get("/robots.txt", (request, response) => {
    response.type("text/plain");
    response.send("User-agent: *\nDisallow: /");
  });

  // Assets
  router.use("/assets", express.static(assetsPath, { maxAge: "7d" }));
  router.get("/assets/app-:hash.js", assetsController.getScripts);
  router.get("/assets/app-:hash.css", assetsController.getStyles);
  router.get(
    "/assets/app-icon-:size-:purpose.png",
    assetsController.getAppIcon,
  );
  router.get(
    "/assets/shortcut-icon-:size-:name.png",
    assetsController.getShortcutIcon,
  );

  // Service worker
  router.get("/serviceworker.js", offlineController.serviceworker);
  router.get("/offline", offlineController.offline);

  // Plug-in assets
  for (const plugin of installedPlugins) {
    if (plugin.filePath) {
      const assetsPath = path.join(plugin.filePath, "assets");
      router.use(`/assets/${plugin.id}`, express.static(assetsPath));
    }
  }

  // Feed
  router.get("/feed.jf2", feedController.jf2);

  // Web App Manifest
  router.get("/app.webmanifest", manifestController.get);

  // Client metadata
  router.get("/id", clientController.get);

  // Session (rate-limited: brute force protection)
  router.get("/session/login", sessionLimit, sessionController.login);
  router.post("/session/login", sessionLimit, indieauth.login());
  router.get("/session/auth", sessionLimit, indieauth.authorize());
  router.get("/session/logout", sessionController.logout);

  // Public and .well-known endpoints (rate-limited: abuse protection)
  for (const endpoint of endpoints) {
    // Internal routing
    // Currently used for endpoint-image which requires configuration values
    // to be passed on to express-sharp middleware
    if (endpoint.mountPath && endpoint._routes) {
      router.use(endpoint.mountPath, apiLimit, endpoint._routes(Indiekit));
    }

    if (endpoint.mountPath && endpoint.routesPublic) {
      // Skip rate limiting for root-mounted endpoints (mountPath "/") because
      // router.use("/", apiLimit, ...) matches ALL routes, applying the rate
      // limiter globally. This caused 429 errors on authenticated routes
      // (e.g. endpoint-json-feed mounts routesPublic at "/").
      if (endpoint.mountPath === "/") {
        router.use(endpoint.mountPath, endpoint.routesPublic);
      } else {
        router.use(endpoint.mountPath, apiLimit, endpoint.routesPublic);
      }
    }

    if (endpoint.routesWellKnown) {
      router.use("/.well-known/", apiLimit, endpoint.routesWellKnown);
    }
  }

  // Content negotiation routes — serves ActivityPub JSON-LD for post URLs
  // and handles NodeInfo data at /nodeinfo/2.1. Mounted at root before auth
  // so unauthenticated AP clients can fetch post representations.
  for (const endpoint of endpoints) {
    if (endpoint.contentNegotiationRoutes) {
      router.use("/", endpoint.contentNegotiationRoutes);
    }
  }

  // Authenticate subsequent requests
  router.use(indieauth.authenticate());

  // --- Authenticated routes below ---
  // No rate limiting: auth middleware is the protection.
  // Rate limiting here caused 429 errors during normal admin browsing because
  // all clients behind a reverse proxy share the same IP (Docker bridge).

  // Homepage
  router.get("/", homepageController.viewHomepage);

  // Plugin
  router.get("/plugins", pluginController.list);
  router.get("/plugins/:pluginId", pluginController.view);

  // Status
  router.get("/status", statusController.viewStatus);

  // Authenticated endpoints
  for (const endpoint of endpoints) {
    if (endpoint.mountPath && endpoint.routes) {
      router.use(endpoint.mountPath, endpoint.routes);
    }
  }

  return router;
};
