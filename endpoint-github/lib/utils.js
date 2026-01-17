/**
 * Truncate text with ellipsis
 * @param {string} text - Text to truncate
 * @param {number} [maxLength] - Maximum length
 * @returns {string} - Truncated text
 */
export function truncate(text, maxLength = 80) {
  if (!text || text.length <= maxLength) return text || "";
  return text.slice(0, maxLength - 1) + "…";
}

/**
 * Extract commits from push events
 * @param {Array} events - GitHub events
 * @returns {Array} - Formatted commits
 */
export function extractCommits(events) {
  return events
    .filter((event) => event.type === "PushEvent")
    .flatMap((event) =>
      event.payload.commits.map((commit) => ({
        sha: commit.sha.slice(0, 7),
        message: truncate(commit.message.split("\n")[0]),
        url: `https://github.com/${event.repo.name}/commit/${commit.sha}`,
        repo: event.repo.name,
        repoUrl: `https://github.com/${event.repo.name}`,
        date: event.created_at,
      })),
    );
}

/**
 * Extract PRs/Issues created from events
 * @param {Array} events - GitHub events
 * @returns {Array} - Formatted contributions
 */
export function extractContributions(events) {
  return events
    .filter(
      (event) =>
        (event.type === "PullRequestEvent" || event.type === "IssuesEvent") &&
        event.payload.action === "opened",
    )
    .map((event) => {
      const item = event.payload.pull_request || event.payload.issue;
      return {
        type: event.type === "PullRequestEvent" ? "pr" : "issue",
        title: truncate(item.title),
        url: item.html_url,
        repo: event.repo.name,
        repoUrl: `https://github.com/${event.repo.name}`,
        number: item.number,
        date: event.created_at,
      };
    });
}

/**
 * Format starred repos for display
 * @param {Array} repos - Starred repositories
 * @returns {Array} - Formatted repos
 */
export function formatStarred(repos) {
  return repos.map((repo) => ({
    name: repo.full_name,
    description: truncate(repo.description, 120),
    url: repo.html_url,
    stars: repo.stargazers_count,
    language: repo.language,
    topics: repo.topics?.slice(0, 5) || [],
  }));
}

/**
 * Extract activity on user's repos from other users
 * @param {Array} events - Repository events
 * @param {string} username - Owner username to exclude
 * @returns {Array} - Formatted activity
 */
export function extractRepoActivity(events, username) {
  return events
    .filter((event) => event.actor.login !== username) // Exclude own activity
    .map((event) => ({
      type: event.type.replace("Event", "").toLowerCase(),
      actor: event.actor.login,
      actorUrl: `https://github.com/${event.actor.login}`,
      actorAvatar: event.actor.avatar_url,
      repo: event.repo.name,
      repoUrl: `https://github.com/${event.repo.name}`,
      date: event.created_at,
      detail: getEventDetail(event),
    }));
}

/**
 * Get human-readable detail for an event
 * @param {object} event - GitHub event
 * @returns {string} - Event description
 */
function getEventDetail(event) {
  switch (event.type) {
    case "WatchEvent": {
      return "starred";
    }
    case "ForkEvent": {
      return "forked";
    }
    case "PullRequestEvent": {
      return `${event.payload.action} PR #${event.payload.number}`;
    }
    case "IssuesEvent": {
      return `${event.payload.action} issue #${event.payload.number}`;
    }
    case "IssueCommentEvent": {
      return "commented";
    }
    case "CreateEvent": {
      return `created ${event.payload.ref_type}`;
    }
    case "DeleteEvent": {
      return `deleted ${event.payload.ref_type}`;
    }
    case "PushEvent": {
      return `pushed ${event.payload.size} commit(s)`;
    }
    default: {
      return event.type.replace("Event", "").toLowerCase();
    }
  }
}

/**
 * Format date for display
 * @param {string} dateString - ISO date string
 * @param {string} [locale] - Locale for formatting
 * @returns {string} - Formatted date
 */
export function formatDate(dateString, locale = "en") {
  const date = new Date(dateString);
  return date.toLocaleDateString(locale, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

/**
 * Format relative time
 * @param {string} dateString - ISO date string
 * @returns {string} - Relative time string
 */
export function formatRelativeTime(dateString) {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60_000);
  const diffHours = Math.floor(diffMs / 3_600_000);
  const diffDays = Math.floor(diffMs / 86_400_000);

  if (diffMins < 1) return "just now";
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;

  return formatDate(dateString);
}
