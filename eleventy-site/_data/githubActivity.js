/**
 * GitHub Activity Data
 * Fetches from Indiekit's endpoint-github API or directly from GitHub
 */

import EleventyFetch from "@11ty/eleventy-fetch";

const GITHUB_USERNAME = process.env.GITHUB_USERNAME || "rmdes";
const INDIEKIT_URL = process.env.SITE_URL || "https://rmendes.net";

/**
 * Fetch from Indiekit's GitHub API endpoint
 */
async function fetchFromIndiekit(endpoint) {
  try {
    const url = `${INDIEKIT_URL}/github/api/${endpoint}`;
    return await EleventyFetch(url, {
      duration: "15m",
      type: "json",
    });
  } catch (error) {
    console.log(
      `Indiekit API not available for ${endpoint}, falling back to GitHub API`
    );
    return null;
  }
}

/**
 * Fetch directly from GitHub API
 */
async function fetchFromGitHub(endpoint) {
  const url = `https://api.github.com${endpoint}`;
  const headers = {
    Accept: "application/vnd.github.v3+json",
    "User-Agent": "Eleventy-Site",
  };

  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  return await EleventyFetch(url, {
    duration: "15m",
    type: "json",
    fetchOptions: { headers },
  });
}

/**
 * Truncate text with ellipsis
 */
function truncate(text, maxLength = 80) {
  if (!text || text.length <= maxLength) return text || "";
  return text.slice(0, maxLength - 1) + "...";
}

/**
 * Extract commits from push events
 */
function extractCommits(events) {
  if (!Array.isArray(events)) return [];

  return events
    .filter((event) => event.type === "PushEvent")
    .flatMap((event) =>
      (event.payload?.commits || []).map((commit) => ({
        sha: commit.sha.slice(0, 7),
        message: truncate(commit.message.split("\n")[0]),
        url: `https://github.com/${event.repo.name}/commit/${commit.sha}`,
        repo: event.repo.name,
        repoUrl: `https://github.com/${event.repo.name}`,
        date: event.created_at,
      }))
    )
    .slice(0, 10);
}

/**
 * Extract PRs/Issues created from events
 */
function extractContributions(events) {
  if (!Array.isArray(events)) return [];

  return events
    .filter(
      (event) =>
        (event.type === "PullRequestEvent" || event.type === "IssuesEvent") &&
        event.payload?.action === "opened"
    )
    .map((event) => {
      const item = event.payload.pull_request || event.payload.issue;
      return {
        type: event.type === "PullRequestEvent" ? "pr" : "issue",
        title: truncate(item?.title),
        url: item?.html_url,
        repo: event.repo.name,
        repoUrl: `https://github.com/${event.repo.name}`,
        number: item?.number,
        date: event.created_at,
      };
    })
    .slice(0, 10);
}

/**
 * Format starred repos for display
 */
function formatStarred(repos) {
  if (!Array.isArray(repos)) return [];

  return repos.map((repo) => ({
    name: repo.full_name,
    description: truncate(repo.description, 120),
    url: repo.html_url,
    stars: repo.stargazers_count,
    language: repo.language,
    topics: repo.topics?.slice(0, 5) || [],
  }));
}

export default async function () {
  try {
    // Try Indiekit API first (if running)
    const indiekitStars = await fetchFromIndiekit("stars");
    const indiekitCommits = await fetchFromIndiekit("commits");
    const indiekitActivity = await fetchFromIndiekit("activity");
    const indiekitFeatured = await fetchFromIndiekit("featured");

    // If Indiekit API is available, use its data
    if (indiekitStars?.stars || indiekitCommits?.commits) {
      return {
        stars: indiekitStars?.stars || [],
        commits: indiekitCommits?.commits || [],
        activity: indiekitActivity?.activity || [],
        featured: indiekitFeatured?.featured || [],
        source: "indiekit",
      };
    }

    // Fallback to direct GitHub API
    console.log("Fetching GitHub data directly from API...");

    const [events, starred] = await Promise.all([
      fetchFromGitHub(`/users/${GITHUB_USERNAME}/events/public?per_page=50`),
      fetchFromGitHub(
        `/users/${GITHUB_USERNAME}/starred?per_page=20&sort=created`
      ),
    ]);

    return {
      stars: formatStarred(starred || []),
      commits: extractCommits(events || []),
      contributions: extractContributions(events || []),
      featured: [], // Featured repos only available via Indiekit config
      source: "github",
    };
  } catch (error) {
    console.error("Error fetching GitHub activity:", error.message);
    return {
      stars: [],
      commits: [],
      contributions: [],
      featured: [],
      source: "error",
    };
  }
}
