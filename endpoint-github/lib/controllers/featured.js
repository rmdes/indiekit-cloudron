import { GitHubClient } from "../github-client.js";
import * as utils from "../utils.js";

/**
 * Featured repos controller
 */
export const featuredController = {
  /**
   * Get featured repos HTML page
   * @type {import("express").RequestHandler}
   */
  async get(request, response, next) {
    try {
      const { githubConfig } = request.app.locals.application;

      if (!githubConfig) {
        return response.status(500).render("github", {
          title: "GitHub",
          actions: [],
          error: { message: "GitHub endpoint not configured correctly" },
        });
      }

      const { token, cacheTtl, featuredRepos } = githubConfig;

      if (!featuredRepos || featuredRepos.length === 0) {
        return response.render("featured", {
          title: response.locals.__("github.featured.title"),
          actions: [],
          featured: [],
        });
      }

      const client = new GitHubClient({ token, cacheTtl });
      const featured = await fetchFeaturedRepos(client, featuredRepos);

      response.render("featured", {
        title: response.locals.__("github.featured.title"),
        actions: [],
        featured,
      });
    } catch (error) {
      console.error("[GitHub Endpoint] Featured error:", error);
      next(error);
    }
  },

  /**
   * Get featured repos JSON API
   * @type {import("express").RequestHandler}
   */
  async api(request, response, next) {
    try {
      const { githubConfig } = request.app.locals.application;

      if (!githubConfig) {
        return response.status(500).json({ error: "GitHub not configured" });
      }

      const { token, cacheTtl, featuredRepos } = githubConfig;

      if (!featuredRepos || featuredRepos.length === 0) {
        return response.json({ featured: [] });
      }

      const client = new GitHubClient({ token, cacheTtl });
      const featured = await fetchFeaturedRepos(client, featuredRepos);

      response.json({ featured });
    } catch (error) {
      console.error("[GitHub Endpoint] Featured API error:", error);
      next(error);
    }
  },
};

/**
 * Fetch featured repos with commits
 * @param {GitHubClient} client
 * @param {string[]} featuredRepos
 * @returns {Promise<Array>}
 */
async function fetchFeaturedRepos(client, featuredRepos) {
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
      console.error(
        `[GitHub Endpoint] Error fetching ${repoPath}:`,
        error.message,
      );
      return null;
    }
  });

  const featured = (await Promise.all(featuredPromises)).filter(Boolean);
  console.log("[GitHub Endpoint] Featured repos loaded:", featured.length);

  return featured;
}
