import express from "express";

import { activityController } from "./lib/controllers/activity.js";
import { commitsController } from "./lib/controllers/commits.js";
import { contributionsController } from "./lib/controllers/contributions.js";
import { dashboardController } from "./lib/controllers/dashboard.js";
import { starsController } from "./lib/controllers/stars.js";

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
  },
  repos: [], // Empty = all repos, or specify ['owner/repo', ...]
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
      iconName: "github",
      requiresDatabase: false,
    };
  }

  get routes() {
    const router = express.Router();
    const { options } = this;

    // Inject options into request
    router.use((request, response, next) => {
      request.githubOptions = options;
      next();
    });

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
  }
}
