# Indiekit Cloudron — multi-site Makefile
#
# Layout convention:
#
#   indiekit-cloudron/
#   ├── *.template                  (committed, generic defaults)
#   ├── eleventy-site/              (git submodule — public theme)
#   ├── overrides/eleventy-site/    (legacy: optional rmendes-style override)
#   └── sites/                      (GITIGNORED, one directory per site)
#       ├── rmendes/
#       │   ├── config/
#       │   │   ├── nginx.conf
#       │   │   ├── indiekit.config.js
#       │   │   ├── redirects.map
#       │   │   ├── old-blog-redirects.map
#       │   │   └── env.sh
#       │   └── overrides/eleventy-site/   (applied on top of submodule)
#       └── chardonsbleus/
#           ├── config/
#           │   ├── nginx.conf
#           │   ├── indiekit.config.js
#           │   ├── redirects.map
#           │   ├── old-blog-redirects.map
#           │   └── env.sh
#           └── theme/                     (full theme replacement; may be a symlink)
#
# Usage:
#   make build SITE=chardonsbleus           build for chardonsbleus
#   make deploy SITE=rmendes APP=rmendes.net deploy rmendes to its Cloudron app
#   make use SITE=chardonsbleus             remember the default site for `make` without SITE=
#   make prepare                             apply overrides for the default site (no build)
#
# Default site is read from .current-site (gitignored) if SITE is not provided.

# ─── Configuration ───

# Determine the active site: explicit SITE > .current-site > none
SITE ?= $(shell cat .current-site 2>/dev/null)
APP  ?=

# Path to the active site's overlay
SITE_DIR   := sites/$(SITE)
CONFIG_DIR := $(SITE_DIR)/config

# The 5 config files we materialize at the repo root before docker build.
CONFIG_FILES := nginx.conf indiekit.config.js redirects.map old-blog-redirects.map env.sh

# Docker Hub release tagging
CLOUDRON_IMAGE   := rmdes/indiekit-cloudron
UPSTREAM_VERSION := $(shell node -p "require('./CloudronManifest.json').upstreamVersion" 2>/dev/null)

# Build counter for cache-busting (incremented per package release).
# Stays decoupled from UPSTREAM_VERSION so the manifest's upstreamVersion can
# track the actual upstream @indiekit/indiekit release without artificial bumps.
BUILD_NUMBER := $(shell cat .cloudron-build 2>/dev/null || echo 0)

# Per-site image tag: <site>-<upstream>-build<n>  (e.g. rmendes-1.0.0-beta.27-build30)
# This prevents building chardonsbleus from overwriting rmendes's image in the registry.
IMAGE_TAG  := $(SITE)-$(UPSTREAM_VERSION)-build$(BUILD_NUMBER)
FULL_IMAGE := $(CLOUDRON_IMAGE):$(IMAGE_TAG)

# Guard that errors out when an action requires a SITE but none is set.
define require_site
	@if [ -z "$(SITE)" ]; then \
		echo "ERROR: no SITE specified."; \
		echo "  Usage:  make $@ SITE=<sitename>"; \
		echo "  Or:     make use SITE=<sitename>  (remember as default)"; \
		echo "  Sites available:"; \
		ls -1 sites/ 2>/dev/null | sed 's/^/    - /' || echo "    (none — create sites/<name>/ to begin)"; \
		exit 1; \
	fi
	@if [ ! -d "$(SITE_DIR)" ]; then \
		echo "ERROR: sites/$(SITE)/ does not exist."; \
		exit 1; \
	fi
endef

# ─── Setup ───

.PHONY: init
init: ## Initialize git submodules (first time only)
	@echo "==> Initializing submodules..."
	git submodule update --init --recursive
	@echo "==> Done."

.PHONY: theme-update
theme-update: ## Pull latest from the public eleventy-site submodule
	@echo "==> Updating theme submodule..."
	cd eleventy-site && git fetch origin && git checkout main && git pull origin main
	@echo "==> Theme updated. Commit the submodule pointer change if you want to ship it:"
	@echo "    git add eleventy-site && git commit -m 'chore: update theme'"

# Set the default site for subsequent commands. Stored in .current-site (gitignored).
.PHONY: use
use:
	$(require_site)
	@echo "$(SITE)" > .current-site
	@echo "==> Default SITE set to: $(SITE)"

.PHONY: which
which:
	@if [ -z "$(SITE)" ]; then \
		echo "No site selected. Set with: make use SITE=<sitename>"; \
	else \
		echo "Active SITE: $(SITE)"; \
		echo "Overlay:     $(SITE_DIR)"; \
	fi

.PHONY: which-image
which-image: ## Print the full image tag that 'make build' would produce
	$(require_site)
	@echo "$(FULL_IMAGE)"

# ─── Prepare ───

.PHONY: prepare
prepare: ## Materialize per-site config + theme into the repo root
	$(require_site)
	@echo "==> Preparing build for SITE=$(SITE)"
	@echo "    overlay: $(SITE_DIR)"
	@# Copy the 5 config files from the site overlay; fall back to *.template
	@for f in $(CONFIG_FILES); do \
		if [ -f "$(CONFIG_DIR)/$$f" ]; then \
			echo "    $(CONFIG_DIR)/$$f -> $$f"; \
			cp "$(CONFIG_DIR)/$$f" "$$f"; \
		elif [ -f "$$f.template" ]; then \
			echo "    $$f.template -> $$f"; \
			cp "$$f.template" "$$f"; \
		fi; \
	done
	@# Eleventy theme: single canonical theme (indiekit-eleventy-theme submodule).
	@# Per-site variance lives in MongoDB siteConfig (via the site-config plugin's
	@# runtime CSS generation) — NOT in per-site theme forks. Per v2 design,
	@# acceptance criterion #1: "One canonical Eleventy theme used by every
	@# deployment. No per-site theme forks."
	@echo "    (using submodule as-is — per-site theme variants are not supported; use siteConfig MongoDB instead)"
	@# migrated-content — seeded once into /app/data/content by start.sh on first
	@# container boot. Per-site:
	@#   1. sites/$(SITE)/migrated-content/  → use as-is (explicit per-site)
	@#   2. neither                          → keep tree-default migrated-content/
	@#                                         (which is empty/placeholder only per
	@#                                         the 8a8690d cleanup that moved
	@#                                         chardonsbleus content out)
	@if [ -d "$(SITE_DIR)/migrated-content" ]; then \
		echo "    $(SITE_DIR)/migrated-content/* -> migrated-content/ (explicit per-site)"; \
		rm -rf migrated-content; \
		mkdir -p migrated-content; \
		rsync -aL "$(SITE_DIR)/migrated-content/" migrated-content/; \
	else \
		echo "    (no per-site migrated-content for $(SITE) — keeping repo default)"; \
	fi
	@echo "==> Done"

# ─── Build & Deploy ───

.PHONY: build
build: prepare ## Apply overrides and build via `cloudron build --no-cache`
	$(require_site)
	@echo "==> Building Cloudron app for SITE=$(SITE) → $(FULL_IMAGE)"
	cloudron build --no-cache --tag $(IMAGE_TAG)

.PHONY: build-cached
build-cached: prepare ## Build with cache
	$(require_site)
	@echo "==> Building Cloudron app for SITE=$(SITE) (cached) → $(FULL_IMAGE)"
	cloudron build --tag $(IMAGE_TAG)

.PHONY: deploy
deploy: build ## Build and deploy to the Cloudron app named in APP=
	$(require_site)
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required for deploy"; exit 1; fi
	@echo "==> Deploying $(SITE) ($(FULL_IMAGE)) to Cloudron app $(APP)..."
	cloudron update --app $(APP) --image $(FULL_IMAGE) --no-backup

.PHONY: update
update: ## Deploy without rebuild (requires SITE= and APP=)
	$(require_site)
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required for update"; exit 1; fi
	@echo "==> Updating $(APP) with image $(FULL_IMAGE)..."
	cloudron update --app $(APP) --image $(FULL_IMAGE) --no-backup

.PHONY: push-env
push-env: ## Push the active site's env.sh into the running container
	$(require_site)
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required"; exit 1; fi
	@if [ -f "$(CONFIG_DIR)/env.sh" ]; then \
		echo "==> Pushing $(CONFIG_DIR)/env.sh to $(APP)..."; \
		cloudron push --app $(APP) "$(CONFIG_DIR)/env.sh" /app/data/config/env.sh; \
		echo "==> Done. Restart with: cloudron restart --app $(APP)"; \
	else \
		echo "ERROR: $(CONFIG_DIR)/env.sh not found"; exit 1; \
	fi

.PHONY: restart
restart:
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required"; exit 1; fi
	cloudron restart --app $(APP)

.PHONY: logs
logs:
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required"; exit 1; fi
	cloudron logs -f --app $(APP)

.PHONY: shell
shell:
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required"; exit 1; fi
	cloudron exec --app $(APP)

# ─── Clean ───

.PHONY: clean
clean: ## Restore base templates (undo prepare in working dir)
	@echo "==> Restoring base templates..."
	@for f in $(CONFIG_FILES); do \
		if [ -f "$$f.template" ]; then \
			cp "$$f.template" "$$f"; echo "    $$f restored from template"; \
		fi; \
	done
	@echo "==> Resetting theme submodule..."
	@if [ -d eleventy-site/.git ] || [ -f eleventy-site/.git ]; then \
		cd eleventy-site && git checkout . && git clean -fd; \
	fi
	@echo "==> Done."

# ─── Docker Hub ───

.PHONY: docker-build
docker-build: prepare ## Build image for Docker Hub
	docker build --no-cache -t $(CLOUDRON_IMAGE):latest -t $(CLOUDRON_IMAGE):$(UPSTREAM_VERSION) .

.PHONY: docker-push
docker-push:
	docker push $(CLOUDRON_IMAGE):latest
	docker push $(CLOUDRON_IMAGE):$(UPSTREAM_VERSION)

.PHONY: docker-release
docker-release: docker-build docker-push
	@echo "==> Released $(UPSTREAM_VERSION) to Docker Hub"

.PHONY: docker-version
docker-version:
	@echo $(UPSTREAM_VERSION)

# ─── CI/CD ───

.PHONY: ci
ci:
	gh workflow run build-image.yml

.PHONY: ci-status
ci-status:
	gh run list --workflow=build-image.yml --limit=5

# ─── Help ───

.PHONY: help
help:
	@echo "Indiekit Cloudron — multi-site Makefile"
	@echo ""
	@echo "Active SITE: $${SITE:-$$(cat .current-site 2>/dev/null || echo '(none)')}"
	@echo ""
	@echo "Setup:"
	@echo "  make init                       Initialize git submodules"
	@echo "  make theme-update               Pull latest submodule theme"
	@echo "  make use SITE=<name>            Set default site"
	@echo "  make which                      Show active site + overlay path"
	@echo "  make which-image SITE=<name>    Show image tag that 'make build' would produce"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make build SITE=<name>          Build for a specific site"
	@echo "  make build-cached SITE=<name>   Build with cache"
	@echo "  make deploy SITE=<name> APP=<app.example.com>"
	@echo "  make update APP=<app.example.com>"
	@echo "  make push-env SITE=<name> APP=<app.example.com>"
	@echo ""
	@echo "Maintenance:"
	@echo "  make prepare SITE=<name>        Materialize config/theme without building"
	@echo "  make clean                      Reset to templates"
	@echo "  make restart APP=<app.example.com>"
	@echo "  make logs APP=<app.example.com>"
	@echo "  make shell APP=<app.example.com>"
	@echo ""
	@echo "Docker Hub:"
	@echo "  make docker-build SITE=<name>   Build image"
	@echo "  make docker-push                Push to Hub"
	@echo "  make docker-release SITE=<name> Build + push"
	@echo ""
	@echo "Adding a new site:"
	@echo "  mkdir -p sites/<name>/config"
	@echo "  # populate the 5 config files (or copy from *.template)"
	@echo "  # optional: sites/<name>/theme  (full theme replacement)"
	@echo "  # optional: sites/<name>/overrides/eleventy-site/  (overlay submodule)"
	@echo "  make use SITE=<name>            (optional default)"

.DEFAULT_GOAL := help
