import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Display starred repositories
 * @type {import("express").RequestHandler}
 */
export const starsController = {
  async get(request, response, next) {
    try {
      const { username, token, cacheTtl, limits } =
        request.app.locals.application.githubConfig;

      if (!username) {
        return response.render("stars", {
          title: response.locals.__("github.stars.title"),
          error: { message: response.locals.__("github.error.noUsername") },
        });
      }

      const client = new GitHubClient({ token, cacheTtl });

      let starred = [];
      try {
        starred = await client.getUserStarred(username, limits.stars * 2);
      } catch (apiError) {
        console.error("GitHub API error:", apiError);
        return response.render("stars", {
          title: response.locals.__("github.stars.title"),
          actions: [],
          parent: {
            href: request.baseUrl,
            text: response.locals.__("github.title"),
          },
          error: { message: apiError.message || "Failed to fetch stars" },
        });
      }

      const stars = utils.formatStarred(starred);

      response.render("stars", {
        title: response.locals.__("github.stars.title"),
        actions: [],
        parent: {
          href: request.baseUrl,
          text: response.locals.__("github.title"),
        },
        stars,
        username,
        mountPath: request.baseUrl,
      });
    } catch (error) {
      next(error);
    }
  },

  async api(request, response, next) {
    try {
      const { username, token, cacheTtl, limits } =
        request.app.locals.application.githubConfig;

      if (!username) {
        return response.status(400).json({ error: "No username configured" });
      }

      const client = new GitHubClient({ token, cacheTtl });

      let starred = [];
      try {
        starred = await client.getUserStarred(username, limits.stars);
      } catch (apiError) {
        return response
          .status(apiError.status || 500)
          .json({ error: apiError.message });
      }

      const stars = utils.formatStarred(starred);

      response.json({ stars });
    } catch (error) {
      next(error);
    }
  },
};
