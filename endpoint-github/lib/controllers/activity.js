import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Display activity on user's repositories from others
 * @type {import("express").RequestHandler}
 */
export const activityController = {
  async get(request, response, next) {
    try {
      const { username, token, cacheTtl, limits, repos } =
        request.githubOptions;

      if (!username) {
        return response.render("activity", {
          title: response.locals.__("github.activity.title"),
          error: { message: response.locals.__("github.error.noUsername") },
        });
      }

      const client = new GitHubClient({ token, cacheTtl });

      let activity = [];

      if (repos.length > 0) {
        // Fetch events for specific repos
        const repoEventPromises = repos.map(async (repoPath) => {
          const [owner, repo] = repoPath.split("/");
          try {
            return await client.getRepoEvents(owner, repo, 30);
          } catch {
            return [];
          }
        });

        const repoEvents = await Promise.all(repoEventPromises);
        const allEvents = repoEvents.flat();
        activity = utils.extractRepoActivity(allEvents, username);
      } else {
        // Use received events (events on user's repos)
        const events = await client.fetch(
          `/users/${username}/received_events?per_page=${limits.activity * 2}`,
        );
        activity = utils.extractRepoActivity(events, username);
      }

      activity = activity.slice(0, limits.activity);

      response.render("activity", {
        title: response.locals.__("github.activity.title"),
        parent: {
          href: request.baseUrl,
          text: response.locals.__("github.title"),
        },
        activity,
        username,
        mountPath: request.baseUrl,
      });
    } catch (error) {
      next(error);
    }
  },

  async api(request, response, next) {
    try {
      const { username, token, cacheTtl, limits, repos } =
        request.githubOptions;

      if (!username) {
        return response.status(400).json({ error: "No username configured" });
      }

      const client = new GitHubClient({ token, cacheTtl });

      let activity = [];

      if (repos.length > 0) {
        const repoEventPromises = repos.map(async (repoPath) => {
          const [owner, repo] = repoPath.split("/");
          try {
            return await client.getRepoEvents(owner, repo, 20);
          } catch {
            return [];
          }
        });

        const repoEvents = await Promise.all(repoEventPromises);
        const allEvents = repoEvents.flat();
        activity = utils.extractRepoActivity(allEvents, username);
      } else {
        const events = await client.fetch(
          `/users/${username}/received_events?per_page=${limits.activity}`,
        );
        activity = utils.extractRepoActivity(events, username);
      }

      activity = activity.slice(0, limits.activity);

      response.json({ activity });
    } catch (error) {
      next(error);
    }
  },
};
