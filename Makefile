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

# Per-site cache-busting build counter, auto-incremented after every successful
# build (see `build` / `build-cached`). Each site keeps its own counter file
# (.cloudron-build.<site>) so numbers never interleave across sites and every
# deploy gets a UNIQUE image tag — a repeated tag makes Cloudron serve a stale
# cached image instead of the freshly built one. Falls back to the legacy
# shared .cloudron-build (for migration), then 0.
# Decoupled from UPSTREAM_VERSION so the manifest can track the real upstream
# @indiekit/indiekit release without artificial bumps.
BUILD_COUNTER_FILE := .cloudron-build.$(SITE)
BUILD_NUMBER := $(shell cat .cloudron-build.$(SITE) 2>/dev/null || cat .cloudron-build 2>/dev/null || echo 0)

# Per-site image tag: <site>-<upstream>-build<n>  (e.g. rmendes-1.0.0-beta.27-build30)
# This prevents building chardonsbleus from overwriting rmendes's image in the registry.
IMAGE_TAG  := $(SITE)-$(UPSTREAM_VERSION)-build$(BUILD_NUMBER)
FULL_IMAGE := $(CLOUDRON_IMAGE):$(IMAGE_TAG)

# Most-recently-built image (counter - 1): `build` advances the counter on
# success, so the just-built image is one behind. `make update` (redeploy
# without rebuild — e.g. retry after a transient deploy failure) targets this.
LAST_BUILD_NUMBER := $(shell echo $$(( $(BUILD_NUMBER) - 1 )))
LAST_IMAGE_TAG := $(SITE)-$(UPSTREAM_VERSION)-build$(LAST_BUILD_NUMBER)
LAST_FULL_IMAGE := $(CLOUDRON_IMAGE):$(LAST_IMAGE_TAG)

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
build: compose prepare ## Apply overrides and build via `cloudron build --no-cache`
	$(require_site)
	@echo "==> Building Cloudron app for SITE=$(SITE) → $(FULL_IMAGE)"
	cloudron build --no-cache --tag $(IMAGE_TAG) --build-arg SITE=$(SITE)
	@echo $$(( $(BUILD_NUMBER) + 1 )) > $(BUILD_COUNTER_FILE)
	@echo "==> $(SITE) build counter → $$(cat $(BUILD_COUNTER_FILE)) (used for next build)"

.PHONY: build-cached
build-cached: compose prepare ## Build with cache
	$(require_site)
	@echo "==> Building Cloudron app for SITE=$(SITE) (cached) → $(FULL_IMAGE)"
	cloudron build --tag $(IMAGE_TAG) --build-arg SITE=$(SITE)
	@echo $$(( $(BUILD_NUMBER) + 1 )) > $(BUILD_COUNTER_FILE)
	@echo "==> $(SITE) build counter → $$(cat $(BUILD_COUNTER_FILE)) (used for next build)"

# ─── Plugin manifest (Plan B) ───

.PHONY: compose
compose: ## Compose per-site package.json + indiekit.config.js from plugins.yaml
	$(require_site)
	@echo "==> Composing $(SITE)..."
	@cd scripts && SITE=$(SITE) node compose-site.mjs
	@echo "==> Composed: sites/$(SITE)/.compiled/"

.PHONY: check-compiled
check-compiled: ## Assert sites/$(SITE)/.compiled/ exists and is fresh
	$(require_site)
	@[ -f "sites/$(SITE)/.compiled/package.json" ] || { echo "ERROR: sites/$(SITE)/.compiled/ missing. Run: make compose SITE=$(SITE)"; exit 1; }
	@if [ "sites/$(SITE)/config/plugins.yaml" -nt "sites/$(SITE)/.compiled/package.json" ]; then \
		echo "ERROR: plugins.yaml is newer than .compiled/. Run: make compose SITE=$(SITE)"; exit 1; \
	fi

.PHONY: manifest-validate
manifest-validate: ## Validate registry + site manifest parses
	$(require_site)
	@cd plugin-registry && node scripts/validate.mjs
	@node -e "import('js-yaml').then(({default: yaml}) => import('node:fs').then(({readFileSync}) => { const m = yaml.load(readFileSync('sites/$(SITE)/config/plugins.yaml','utf8')); console.log('Site manifest OK:', Object.keys(m).join(', ')); }))"

.PHONY: manifest-from-current
manifest-from-current: ## Generate plugins.yaml from current Dockerfile (one-time migration helper)
	$(require_site)
	SITE=$(SITE) node scripts/manifest-from-current.mjs

# ─── Plugin management ───

.PHONY: plugin-add
plugin-add: ## Enable a plugin. Usage: make plugin-add SITE=foo KEY=github
	$(require_site)
	@[ -n "$(KEY)" ] || { echo "ERROR: KEY=<plugin-key> required"; exit 1; }
	node scripts/plugin-edit.mjs add $(SITE) $(KEY)

.PHONY: plugin-remove
plugin-remove: ## Disable a plugin. Usage: make plugin-remove SITE=foo KEY=funkwhale
	$(require_site)
	@[ -n "$(KEY)" ] || { echo "ERROR: KEY=<plugin-key> required"; exit 1; }
	node scripts/plugin-edit.mjs remove $(SITE) $(KEY)

.PHONY: plugin-list
plugin-list: ## Show effective plugin loadout (reads .compiled/plugin-loadout.json)
	$(require_site)
	@[ -f "sites/$(SITE)/.compiled/plugin-loadout.json" ] || { echo "Run: make compose SITE=$(SITE) first"; exit 1; }
	@node -e "const d=JSON.parse(require('fs').readFileSync('sites/$(SITE)/.compiled/plugin-loadout.json','utf8')); d.selected.forEach(s => console.log('  '+s.tier.padEnd(13)+s.key.padEnd(25)+' ('+s.package+')'));"

.PHONY: plugin-diff
plugin-diff: ## Diff plugin loadout between two sites. Usage: make plugin-diff SITE_A=rmendes SITE_B=chardonsbleus
	@[ -n "$(SITE_A)" ] && [ -n "$(SITE_B)" ] || { echo "ERROR: SITE_A and SITE_B required"; exit 1; }
	@diff <(node -e "const d=require('./sites/$(SITE_A)/.compiled/plugin-loadout.json'); d.selected.forEach(s=>console.log(s.key));" | sort) <(node -e "const d=require('./sites/$(SITE_B)/.compiled/plugin-loadout.json'); d.selected.forEach(s=>console.log(s.key));" | sort) || true

# ─── Site lifecycle ───

.PHONY: new-site
new-site: ## Scaffold a new site overlay. Usage: make new-site NAME=foo
	@[ -n "$(NAME)" ] || { echo "ERROR: NAME=<sitename> required"; exit 1; }
	node scripts/new-site.mjs $(NAME)

.PHONY: site-list
site-list: ## List all configured sites
	@ls -1 sites/ 2>/dev/null | sed 's/^/  - /'

.PHONY: site-rename
site-rename: ## Rename a site. Usage: make site-rename FROM=foo TO=bar
	@[ -n "$(FROM)" ] && [ -n "$(TO)" ] || { echo "ERROR: FROM= and TO= required"; exit 1; }
	mv sites/$(FROM) sites/$(TO)
	@if [ -f .current-site ] && grep -q "^$(FROM)$$" .current-site; then echo "$(TO)" > .current-site; fi
	@echo "Renamed sites/$(FROM) → sites/$(TO)"

.PHONY: site-delete
site-delete: ## Delete a site. Usage: make site-delete NAME=foo CONFIRM=1
	@[ -n "$(NAME)" ] || { echo "ERROR: NAME=<sitename> required"; exit 1; }
	@[ "$(CONFIRM)" = "1" ] || { echo "ERROR: refuse without CONFIRM=1"; exit 1; }
	rm -rf sites/$(NAME)
	@echo "Deleted sites/$(NAME)"

# ─── Registry submodule ───

.PHONY: registry-update
registry-update: ## Pull latest from plugin-registry submodule
	cd plugin-registry && git fetch origin && git checkout main && git pull origin main
	@echo "==> Registry updated. git add plugin-registry to commit the pointer change."

.PHONY: registry-pin
registry-pin: ## Pin registry to a specific commit. Usage: make registry-pin SHA=abc123
	@[ -n "$(SHA)" ] || { echo "ERROR: SHA=<commit> required"; exit 1; }
	cd plugin-registry && git checkout $(SHA)

.PHONY: registry-status
registry-status: ## Show plugin-registry submodule current commit
	@cd plugin-registry && git log -1 --format='%h %s (%cr)'

# ─── Site config (MongoDB) ───

.PHONY: config-export
config-export: ## Dump siteConfig from MongoDB. Usage: make config-export APP=foo > backup.json
	@[ -n "$(APP)" ] || { echo "ERROR: APP= required"; exit 1; }
	cloudron exec --app $(APP) -- bash -c 'mongoexport --uri "$$INDIEKIT_MONGO_URL" --collection siteConfig --jsonArray'

.PHONY: config-show
config-show: ## Show one siteConfig field. Usage: make config-show APP=foo KEY=branding.colors
	@[ -n "$(APP)" ] || { echo "ERROR: APP= required"; exit 1; }
	@[ -n "$(KEY)" ] || { echo "ERROR: KEY=<dot.path> required"; exit 1; }
	cloudron exec --app $(APP) -- bash -c "mongosh \$$INDIEKIT_MONGO_URL --quiet --eval 'JSON.stringify(db.siteConfig.findOne({_id:\"primary\"}).$(KEY))'"

.PHONY: deploy
deploy: build ## Build and deploy to the Cloudron app named in APP=
	$(require_site)
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required for deploy"; exit 1; fi
	@echo "==> Deploying $(SITE) ($(FULL_IMAGE)) to Cloudron app $(APP)..."
	cloudron update --app $(APP) --image $(FULL_IMAGE) --no-backup

.PHONY: update
update: ## Redeploy the last-built image without rebuilding (requires SITE= and APP=)
	$(require_site)
	@if [ -z "$(APP)" ]; then echo "ERROR: APP= required for update"; exit 1; fi
	@echo "==> Updating $(APP) with last-built image $(LAST_FULL_IMAGE)..."
	cloudron update --app $(APP) --image $(LAST_FULL_IMAGE) --no-backup

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

.PHONY: verify-agents
verify-agents: ## Smoke-test the agent-readable surface (usage: make verify-agents URL=https://rmendes.net)
	@curl -fsS -H "Accept: text/markdown" "$(URL)/" | grep -qi '^#' && echo "OK  homepage markdown" || { echo "FAIL homepage markdown"; exit 1; }
	@curl -fsS "$(URL)/about.md" | grep -qi '^#' && echo "OK  about.md" || { echo "FAIL about.md"; exit 1; }
	@curl -fsS "$(URL)/llms.txt" | grep -q '## Articles' && echo "OK  llms.txt" || { echo "FAIL llms.txt"; exit 1; }
	@art=$$(curl -fsS "$(URL)/sitemap.xml" | grep -oE '/articles/[0-9][^<]+/' | head -1); \
	  if [ -z "$$art" ]; then echo "SKIP article .md (no articles in sitemap)"; else \
	  code=$$(curl -fsS -o /dev/null -w '%{http_code}' "$(URL)$${art%/}.md"); \
	  [ "$$code" = "200" ] && echo "OK  article .md ($$art)" || { echo "FAIL article .md http=$$code"; exit 1; }; fi
	@curl -fsS "$(URL)/robots.txt" | grep -qi 'Content-Signal' && echo "OK  robots Content-Signal" || { echo "FAIL robots Content-Signal"; exit 1; }
