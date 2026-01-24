# Indiekit Cloudron Makefile
# Usage:
#   make init      - Initialize submodules (first time setup)
#   make build     - Apply overrides and build Docker image
#   make deploy    - Build and deploy to Cloudron
#   make clean     - Restore base templates
#   make prepare   - Apply personal overrides without building

APP ?= rmendes.net
THEME_REPO = https://github.com/rmdes/indiekit-eleventy-theme.git

# Initialize git submodules (run once after cloning)
.PHONY: init
init:
	@echo "==> Initializing submodules..."
	git submodule update --init --recursive
	@echo "==> Done. Run 'make prepare' to apply personal overrides."

# Update theme submodule to latest version
.PHONY: theme-update
theme-update:
	@echo "==> Updating theme submodule to latest..."
	cd eleventy-site && git fetch origin && git checkout main && git pull origin main
	@echo "==> Theme updated. Don't forget to commit the submodule change:"
	@echo "    git add eleventy-site && git commit -m 'chore: update theme'"

# Apply personal overrides (from .rmendes files and overrides/ directory)
# Falls back to .template files if no .rmendes override exists
.PHONY: prepare
prepare:
	@echo "==> Applying configuration..."
	@# nginx.conf
	@if [ -f nginx.conf.rmendes ]; then \
		echo "    nginx.conf.rmendes -> nginx.conf"; \
		cp nginx.conf.rmendes nginx.conf; \
	elif [ -f nginx.conf.template ]; then \
		echo "    nginx.conf.template -> nginx.conf"; \
		cp nginx.conf.template nginx.conf; \
	fi
	@# redirects.map
	@if [ -f redirects.map.rmendes ]; then \
		echo "    redirects.map.rmendes -> redirects.map"; \
		cp redirects.map.rmendes redirects.map; \
	elif [ -f redirects.map.template ]; then \
		echo "    redirects.map.template -> redirects.map"; \
		cp redirects.map.template redirects.map; \
	fi
	@# old-blog-redirects.map
	@if [ -f old-blog-redirects.map.rmendes ]; then \
		echo "    old-blog-redirects.map.rmendes -> old-blog-redirects.map"; \
		cp old-blog-redirects.map.rmendes old-blog-redirects.map; \
	elif [ -f old-blog-redirects.map.template ]; then \
		echo "    old-blog-redirects.map.template -> old-blog-redirects.map"; \
		cp old-blog-redirects.map.template old-blog-redirects.map; \
	fi
	@# indiekit.config.js
	@if [ -f indiekit.config.js.rmendes ]; then \
		echo "    indiekit.config.js.rmendes -> indiekit.config.js"; \
		cp indiekit.config.js.rmendes indiekit.config.js; \
	elif [ -f indiekit.config.js.template ]; then \
		echo "    indiekit.config.js.template -> indiekit.config.js"; \
		cp indiekit.config.js.template indiekit.config.js; \
	fi
	@# Copy overrides/ directory contents over submodule
	@if [ -d overrides/eleventy-site ]; then \
		echo "    Applying overrides/eleventy-site/* -> eleventy-site/"; \
		cp -r overrides/eleventy-site/* eleventy-site/; \
	fi
	@echo "==> Done"

# Build Docker image
.PHONY: build
build: init prepare
	@echo "==> Building Cloudron app..."
	cloudron build --no-cache

# Build without cache reset
.PHONY: build-cached
build-cached: init prepare
	@echo "==> Building Cloudron app (cached)..."
	cloudron build

# Deploy to Cloudron
.PHONY: deploy
deploy: build
	@echo "==> Deploying to $(APP)..."
	cloudron update --app $(APP)

# Deploy without rebuild (use existing image)
.PHONY: update
update:
	@echo "==> Deploying to $(APP)..."
	cloudron update --app $(APP)

# Restore base templates (undo personal overrides in working directory)
.PHONY: clean
clean:
	@echo "==> Restoring base templates..."
	@if [ -f nginx.conf.template ]; then \
		cp nginx.conf.template nginx.conf; \
		echo "    nginx.conf restored from template"; \
	fi
	@if [ -f redirects.map.template ]; then \
		cp redirects.map.template redirects.map; \
		echo "    redirects.map restored from template"; \
	fi
	@if [ -f old-blog-redirects.map.template ]; then \
		cp old-blog-redirects.map.template old-blog-redirects.map; \
		echo "    old-blog-redirects.map restored from template"; \
	fi
	@if [ -f indiekit.config.js.template ]; then \
		cp indiekit.config.js.template indiekit.config.js; \
		echo "    indiekit.config.js restored from template"; \
	fi
	@# Reset submodule to clean state
	@echo "==> Resetting theme submodule..."
	cd eleventy-site && git checkout . && git clean -fd
	@echo "==> Done. Run 'make prepare' to re-apply personal overrides."

# View logs
.PHONY: logs
logs:
	cloudron logs -f --app $(APP)

# SSH into container
.PHONY: shell
shell:
	cloudron exec --app $(APP)

# Push env.sh to container
.PHONY: push-env
push-env:
	@if [ -f env.sh.rmendes ]; then \
		echo "==> Pushing env.sh.rmendes to container..."; \
		cloudron push --app $(APP) env.sh.rmendes /app/data/config/env.sh; \
		echo "==> Done. Restart with: cloudron restart --app $(APP)"; \
	else \
		echo "Error: env.sh.rmendes not found"; \
		exit 1; \
	fi

# Restart container
.PHONY: restart
restart:
	cloudron restart --app $(APP)

# Show help
.PHONY: help
help:
	@echo "Indiekit Cloudron Makefile"
	@echo ""
	@echo "Setup:"
	@echo "  make init         Initialize git submodules (first time)"
	@echo "  make theme-update Update theme submodule to latest"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make build        Apply overrides and build Docker image (no cache)"
	@echo "  make build-cached Apply overrides and build (with cache)"
	@echo "  make deploy       Build and deploy to Cloudron (APP=$(APP))"
	@echo "  make update       Deploy without rebuild"
	@echo ""
	@echo "Maintenance:"
	@echo "  make prepare      Apply personal overrides without building"
	@echo "  make clean        Restore base templates (reset overrides)"
	@echo "  make push-env     Push env.sh.rmendes to container"
	@echo "  make restart      Restart the Cloudron app"
	@echo "  make logs         View Cloudron logs"
	@echo "  make shell        SSH into Cloudron container"
	@echo ""
	@echo "Structure:"
	@echo "  eleventy-site/                 Theme (git submodule)"
	@echo "  overrides/eleventy-site/       Personal theme overrides"
	@echo "  *.rmendes                      Personal config overrides"
	@echo ""
	@echo "Set APP variable to change target:"
	@echo "  make deploy APP=mysite.example.com"

.DEFAULT_GOAL := help
