import express from "express";

import { activityController } from "./lib/controllers/activity.js";
import { commitsController } from "./lib/controllers/commits.js";
import { contributionsController } from "./lib/controllers/contributions.js";
import { dashboardController } from "./lib/controllers/dashboard.js";
import { starsController } from "./lib/controllers/stars.js";

const router = express.Router();

const defaults = {
  mountPath: "/github",
  username: "",
  token: process.env.GITHUB_TOKEN,
  cacheTtl: 900_000, // 15 minutes in ms
  limits: {
    commits: 10,
    stars: 20,
    contributions: 10,
    activity: 20,
    repos: 10,
  },
  repos: [], // Empty = all repos, or specify ['owner/repo', ...] for filtering activity
  featuredRepos: [], // Repos to showcase with commits, e.g. ['owner/repo', ...]
};

export default class GitHubEndpoint {
  name = "GitHub activity endpoint";

  constructor(options = {}) {
    this.options = { ...defaults, ...options };
    this.mountPath = this.options.mountPath;
  }

  get environment() {
    return ["GITHUB_TOKEN"];
  }

  get navigationItems() {
    return {
      href: this.options.mountPath,
      text: "github.title",
      requiresDatabase: false,
    };
  }

  get shortcutItems() {
    return {
      url: this.options.mountPath,
      name: "github.activity",
      iconName: "syndicate",
      requiresDatabase: false,
    };
  }

  get routes() {
    // Dashboard
    router.get("/", dashboardController.get);

    // Individual sections
    router.get("/commits", commitsController.get);
    router.get("/stars", starsController.get);
    router.get("/contributions", contributionsController.get);
    router.get("/activity", activityController.get);

    // JSON API for widgets
    router.get("/api/commits", commitsController.api);
    router.get("/api/stars", starsController.api);
    router.get("/api/activity", activityController.api);

    return router;
  }

  init(Indiekit) {
    Indiekit.addEndpoint(this);

    // Store GitHub config in application for controller access
    Indiekit.config.application.githubConfig = this.options;
    Indiekit.config.application.githubEndpoint = this.mountPath;
  }
}
