import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Display commits list
 * @type {import("express").RequestHandler}
 */
export const commitsController = {
  async get(request, response, next) {
    try {
      const { username, token, cacheTtl, limits } =
        request.app.locals.application.githubConfig;

      if (!username) {
        return response.render("commits", {
          title: response.locals.__("github.commits.title"),
          error: { message: response.locals.__("github.error.noUsername") },
        });
      }

      const client = new GitHubClient({ token, cacheTtl });

      let events = [];
      try {
        events = await client.getUserEvents(username, 100);
      } catch (apiError) {
        console.error("GitHub API error:", apiError);
        return response.render("commits", {
          title: response.locals.__("github.commits.title"),
          actions: [],
          parent: {
            href: request.baseUrl,
            text: response.locals.__("github.title"),
          },
          error: { message: apiError.message || "Failed to fetch commits" },
        });
      }

      const commits = utils.extractCommits(events).slice(0, limits.commits * 3);

      response.render("commits", {
        title: response.locals.__("github.commits.title"),
        actions: [],
        parent: {
          href: request.baseUrl,
          text: response.locals.__("github.title"),
        },
        commits,
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

      let events = [];
      try {
        events = await client.getUserEvents(username, 50);
      } catch (apiError) {
        return response
          .status(apiError.status || 500)
          .json({ error: apiError.message });
      }

      const commits = utils.extractCommits(events).slice(0, limits.commits);

      response.json({ commits });
    } catch (error) {
      next(error);
    }
  },
};
