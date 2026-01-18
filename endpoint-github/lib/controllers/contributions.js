import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Display PRs and issues created by user
 * @type {import("express").RequestHandler}
 */
export const contributionsController = {
  async get(request, response, next) {
    try {
      const { username, token, cacheTtl, limits } =
        request.app.locals.application.githubConfig;

      if (!username) {
        return response.render("contributions", {
          title: response.locals.__("github.contributions.title"),
          error: { message: response.locals.__("github.error.noUsername") },
        });
      }

      const client = new GitHubClient({ token, cacheTtl });

      let events = [];
      try {
        events = await client.getUserEvents(username, 100);
      } catch (apiError) {
        console.error("GitHub API error:", apiError);
        return response.render("contributions", {
          title: response.locals.__("github.contributions.title"),
          actions: [],
          parent: {
            href: request.baseUrl,
            text: response.locals.__("github.title"),
          },
          error: {
            message: apiError.message || "Failed to fetch contributions",
          },
        });
      }

      const contributions = utils
        .extractContributions(events)
        .slice(0, limits.contributions * 2);

      response.render("contributions", {
        title: response.locals.__("github.contributions.title"),
        actions: [],
        parent: {
          href: request.baseUrl,
          text: response.locals.__("github.title"),
        },
        contributions,
        username,
        mountPath: request.baseUrl,
      });
    } catch (error) {
      next(error);
    }
  },
};
