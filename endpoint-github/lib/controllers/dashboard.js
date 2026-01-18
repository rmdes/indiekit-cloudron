import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Display GitHub activity dashboard
 * @type {import("express").RequestHandler}
 */
export const dashboardController = {
  async get(request, response, next) {
    try {
      console.log("[GitHub Endpoint] Dashboard controller started");

      const { githubConfig } = request.app.locals.application;

      if (!githubConfig) {
        console.error("[GitHub Endpoint] ERROR: githubConfig is undefined");
        return response.status(500).render("github", {
          title: "GitHub",
          actions: [],
          error: { message: "GitHub endpoint not configured correctly" },
        });
      }

      const { username, token, cacheTtl, limits, featuredRepos } = githubConfig;
      console.log("[GitHub Endpoint] Config:", {
        username,
        hasToken: !!token,
        cacheTtl,
        limits,
        featuredRepos: featuredRepos || [],
      });

      if (!username) {
        console.log("[GitHub Endpoint] No username configured");
        return response.render("github", {
          title: response.locals.__("github.title"),
          actions: [],
          error: { message: response.locals.__("github.error.noUsername") },
        });
      }

      const client = new GitHubClient({ token, cacheTtl });
      console.log("[GitHub Endpoint] Using authenticated API:", !!token);

      let user;
      let events = [];
      let starred = [];
      let repos = [];

      try {
        console.log("[GitHub Endpoint] Fetching GitHub data for:", username);
        [user, events, starred, repos] = await Promise.all([
          client.getUser(username),
          client.getUserEvents(username, 30),
          client.getUserStarred(username, limits.stars),
          client.getUserRepos(username, limits.repos || 10),
        ]);
        console.log("[GitHub Endpoint] Raw user data:", JSON.stringify(user));
        console.log("[GitHub Endpoint] Events count:", events?.length);
        console.log("[GitHub Endpoint] Event types:", events?.map(e => e.type));
        console.log("[GitHub Endpoint] Starred count:", starred?.length);
        console.log("[GitHub Endpoint] Repos count:", repos?.length);
      } catch (apiError) {
        console.error("[GitHub Endpoint] API error:", apiError);
        return response.render("github", {
          title: response.locals.__("github.title"),
          actions: [],
          error: { message: apiError.message || "Failed to fetch GitHub data" },
        });
      }

      console.log("[GitHub Endpoint] Processing data...");
      const commits = utils.extractCommits(events);
      console.log("[GitHub Endpoint] Extracted commits:", commits?.length);

      const contributions = utils.extractContributions(events);
      console.log("[GitHub Endpoint] Extracted contributions:", contributions?.length);

      const stars = utils.formatStarred(starred);
      console.log("[GitHub Endpoint] Formatted stars:", stars?.length);

      const repositories = utils.formatRepos(repos);
      console.log("[GitHub Endpoint] Formatted repos:", repositories?.length);

      // Fetch commits from featured repos
      let featured = [];
      if (featuredRepos && featuredRepos.length > 0) {
        console.log("[GitHub Endpoint] Fetching featured repos:", featuredRepos);
        const featuredPromises = featuredRepos.map(async (repoPath) => {
          const [owner, repo] = repoPath.split("/");
          try {
            const [repoData, repoCommits] = await Promise.all([
              client.getRepo(owner, repo),
              client.getRepoCommits(owner, repo, 5),
            ]);
            return {
              ...utils.formatRepos([repoData])[0],
              commits: repoCommits.map((c) => ({
                sha: c.sha.slice(0, 7),
                message: utils.truncate(c.commit.message.split("\n")[0], 60),
                url: c.html_url,
                author: c.commit.author.name,
                date: c.commit.author.date,
              })),
            };
          } catch (error) {
            console.error(`[GitHub Endpoint] Error fetching ${repoPath}:`, error.message);
            return null;
          }
        });
        featured = (await Promise.all(featuredPromises)).filter(Boolean);
        console.log("[GitHub Endpoint] Featured repos loaded:", featured.length);
      }

      const starsLimit = limits.stars || 20;
      const reposLimit = limits.repos || 10;

      console.log("[GitHub Endpoint] Rendering with limits - stars:", starsLimit, "repos:", reposLimit);

      response.render("github", {
        title: response.locals.__("github.title"),
        actions: [],
        user,
        commits: commits.slice(0, limits.commits || 10),
        contributions: contributions.slice(0, limits.contributions || 5),
        stars: stars.slice(0, starsLimit),
        repositories: repositories.slice(0, reposLimit),
        featured,
        mountPath: request.baseUrl,
      });
      console.log("[GitHub Endpoint] Render complete");
    } catch (error) {
      console.error("[GitHub Endpoint] Unexpected error:", error);
      console.error("[GitHub Endpoint] Stack:", error.stack);
      next(error);
    }
  },
};
