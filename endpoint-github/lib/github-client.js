import { IndiekitError } from "@indiekit/error";

const BASE_URL = "https://api.github.com";

export class GitHubClient {
  /**
   * @param {object} options - Client options
   * @param {string} [options.token] - GitHub personal access token
   * @param {number} [options.cacheTtl] - Cache TTL in milliseconds
   */
  constructor(options = {}) {
    this.token = options.token;
    this.cacheTtl = options.cacheTtl || 900_000;
    this.cache = new Map();
  }

  /**
   * Fetch from GitHub API with caching
   * @param {string} endpoint - API endpoint
   * @returns {Promise<object>} - Response data
   */
  async fetch(endpoint) {
    const url = `${BASE_URL}${endpoint}`;

    // Check cache first
    const cached = this.cache.get(url);
    if (cached && Date.now() - cached.timestamp < this.cacheTtl) {
      return cached.data;
    }

    const headers = {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    };

    if (this.token) {
      headers.Authorization = `Bearer ${this.token}`;
    }

    const response = await fetch(url, { headers });

    if (!response.ok) {
      throw await IndiekitError.fromFetch(response);
    }

    const data = await response.json();

    // Cache result
    this.cache.set(url, { data, timestamp: Date.now() });

    return data;
  }

  /**
   * Get user's events (commits, PRs, issues, etc.)
   * Uses authenticated endpoint if token available (includes private activity)
   * @param {string} username - GitHub username
   * @param {number} [limit] - Number of events to fetch
   * @returns {Promise<Array>} - User events
   */
  async getUserEvents(username, limit = 30) {
    // Use non-public endpoint when authenticated to include private repo activity
    const endpoint = this.token
      ? `/users/${username}/events?per_page=${limit}`
      : `/users/${username}/events/public?per_page=${limit}`;
    return this.fetch(endpoint);
  }

  /**
   * Get commits for a specific repository
   * @param {string} owner - Repository owner
   * @param {string} repo - Repository name
   * @param {number} [limit] - Number of commits to fetch
   * @returns {Promise<Array>} - Repository commits
   */
  async getRepoCommits(owner, repo, limit = 10) {
    return this.fetch(`/repos/${owner}/${repo}/commits?per_page=${limit}`);
  }

  /**
   * Get user's starred repos
   * @param {string} username - GitHub username
   * @param {number} [limit] - Number of repos to fetch
   * @returns {Promise<Array>} - Starred repositories
   */
  async getUserStarred(username, limit = 30) {
    return this.fetch(
      `/users/${username}/starred?per_page=${limit}&sort=created`,
    );
  }

  /**
   * Get user profile
   * @param {string} username - GitHub username
   * @returns {Promise<object>} - User profile
   */
  async getUser(username) {
    return this.fetch(`/users/${username}`);
  }

  /**
   * Get user's repositories
   * When authenticated, uses /user/repos to include private repos
   * @param {string} username - GitHub username
   * @param {number} [limit] - Number of repos to fetch
   * @param {string} [sort] - Sort by: created, updated, pushed, full_name
   * @returns {Promise<Array>} - User repositories
   */
  async getUserRepos(username, limit = 30, sort = "pushed") {
    // When authenticated, use /user/repos for private repos access
    // Then filter by owner to get only the user's repos (not org repos)
    if (this.token) {
      const repos = await this.fetch(
        `/user/repos?per_page=${limit}&sort=${sort}&direction=desc&affiliation=owner`,
      );
      return repos;
    }
    // Unauthenticated: public repos only
    return this.fetch(
      `/users/${username}/repos?per_page=${limit}&sort=${sort}&direction=desc`,
    );
  }

  /**
   * Get repo details
   * @param {string} owner - Repository owner
   * @param {string} repo - Repository name
   * @returns {Promise<object>} - Repository details
   */
  async getRepo(owner, repo) {
    return this.fetch(`/repos/${owner}/${repo}`);
  }

  /**
   * Get repo events (activity from others)
   * @param {string} owner - Repository owner
   * @param {string} repo - Repository name
   * @param {number} [limit] - Number of events to fetch
   * @returns {Promise<Array>} - Repository events
   */
  async getRepoEvents(owner, repo, limit = 30) {
    return this.fetch(`/repos/${owner}/${repo}/events?per_page=${limit}`);
  }

  /**
   * Get user's PRs across all repos
   * @param {string} username - GitHub username
   * @param {number} [limit] - Number of PRs to fetch
   * @returns {Promise<object>} - Search results with PRs
   */
  async getUserPRs(username, limit = 30) {
    return this.fetch(
      `/search/issues?q=author:${username}+type:pr&per_page=${limit}&sort=created`,
    );
  }

  /**
   * Get user's issues across all repos
   * @param {string} username - GitHub username
   * @param {number} [limit] - Number of issues to fetch
   * @returns {Promise<object>} - Search results with issues
   */
  async getUserIssues(username, limit = 30) {
    return this.fetch(
      `/search/issues?q=author:${username}+type:issue&per_page=${limit}&sort=created`,
    );
  }
}
