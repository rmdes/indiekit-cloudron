import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Display starred repositories
 * @type {import("express").RequestHandler}
 */
export const starsController = {
  async get(request, response, next) {
    try {
      const { username, token, cacheTtl, limits } = request.githubOptions;

      if (!username) {
        return response.render("stars", {
          title: response.locals.__("github.stars.title"),
          error: { message: response.locals.__("github.error.noUsername") },
        });
      }

      const client = new GitHubClient({ token, cacheTtl });
      const starred = await client.getUserStarred(username, limits.stars * 2);
      const stars = utils.formatStarred(starred);

      response.render("stars", {
        title: response.locals.__("github.stars.title"),
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
      const { username, token, cacheTtl, limits } = request.githubOptions;

      if (!username) {
        return response.status(400).json({ error: "No username configured" });
      }

      const client = new GitHubClient({ token, cacheTtl });
      const starred = await client.getUserStarred(username, limits.stars);
      const stars = utils.formatStarred(starred);

      response.json({ stars });
    } catch (error) {
      next(error);
    }
  },
};
