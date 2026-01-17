import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Display GitHub activity dashboard
 * @type {import("express").RequestHandler}
 */
export const dashboardController = {
  async get(request, response, next) {
    try {
      const { username, token, cacheTtl, limits } = request.githubOptions;

      if (!username) {
        return response.render("github", {
          title: response.locals.__("github.title"),
          error: { message: response.locals.__("github.error.noUsername") },
        });
      }

      const client = new GitHubClient({ token, cacheTtl });

      const [user, events, starred] = await Promise.all([
        client.getUser(username),
        client.getUserEvents(username, 30),
        client.getUserStarred(username, limits.stars),
      ]);

      const commits = utils.extractCommits(events).slice(0, limits.commits);
      const contributions = utils.extractContributions(events).slice(0, 5);
      const stars = utils.formatStarred(starred).slice(0, 6);

      response.render("github", {
        title: response.locals.__("github.title"),
        user,
        commits,
        contributions,
        stars,
        mountPath: request.baseUrl,
      });
    } catch (error) {
      next(error);
    }
  },
};
