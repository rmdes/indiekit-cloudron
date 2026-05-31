FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# Cache buster - increment to force rebuild
ARG CACHE_BUST=325

# Per-site build target. Passed via `cloudron build --build-arg SITE=<name>`
# (or via `make build SITE=<name>`). The composed package.json + indiekit.config.js
# under sites/${SITE}/.compiled/ are produced by `make compose SITE=<name>`,
# which reads sites/<name>/config/plugins.yaml + plugin-registry/plugin-registry.yaml.
ARG SITE

RUN mkdir -p /app/pkg /app/code
WORKDIR /app/code

# Install Node.js 22 (required by Indiekit)
ARG NODE_VERSION=22.22.0
RUN mkdir -p /usr/local/node-$NODE_VERSION && \
    curl -L https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz | tar zxf - --strip-components 1 -C /usr/local/node-$NODE_VERSION
ENV PATH="/usr/local/node-$NODE_VERSION/bin:$PATH"

# Install build dependencies for native modules (sharp, bcrypt, etc.)
RUN apt-get update && \
    apt-get -y install build-essential python3 && \
    rm -rf /var/cache/apt /var/lib/apt/lists

# Per-site package.json composed by scripts/compose-site.mjs from
# plugin-registry.yaml + sites/${SITE}/config/plugins.yaml. The composed
# package.json carries the npm `overrides` field (upstream → @rmdes fork
# swaps) and the deps array (registry-pinned versions).
COPY sites/${SITE}/.compiled/package.json /app/code/package.json

# Install Indiekit and per-site plugin set. No hardcoded list — the
# plugin selection lives in sites/${SITE}/config/plugins.yaml,
# materialized to sites/${SITE}/.compiled/ by `make compose SITE=${SITE}`
# before this Docker build runs.
RUN chown -R cloudron:cloudron /app/code && \
    gosu cloudron:cloudron npm cache clean --force && \
    gosu cloudron:cloudron npm install --legacy-peer-deps

# Copy Eleventy site (submodule with overrides already applied by Makefile)
# The Makefile's 'prepare' step copies overrides/ contents over the submodule before build
COPY eleventy-site /app/pkg/eleventy-site
RUN chown -R cloudron:cloudron /app/pkg/eleventy-site

# Install Eleventy site dependencies
WORKDIR /app/pkg/eleventy-site
RUN gosu cloudron:cloudron npm install

# Run theme prebuild: seeds css/theme.css from css/theme.example.css and
# _data/site-config.json from _data/site.example.json if they don't exist.
# Without this, Eleventy's addPassthroughCopy("css") has no theme.css to copy,
# /css/theme.css 404s, all rgb(var(--c-X)) CSS classes resolve invalid, and
# cards/dark-mode visually regress. See v2 plan Bug #2 verified diagnosis.
# Safe to call: prebuild script is idempotent (only copies if file missing).
RUN if [ -f package.json ] && grep -q '"prebuild"' package.json; then \
        gosu cloudron:cloudron npm run prebuild; \
    else \
        echo "[build] no prebuild script in package.json — skipping"; \
    fi

# Build Tailwind CSS — only if the active theme uses Tailwind (rmendes does;
# chardonsbleus uses vanilla CSS at public/css/). Skip gracefully otherwise.
RUN if [ -f css/tailwind.css ] && [ -x ./node_modules/.bin/tailwindcss ]; then \
        gosu cloudron:cloudron ./node_modules/.bin/tailwindcss -i css/tailwind.css -o css/style.css --minify; \
    else \
        echo "[build] skipping tailwindcss — theme does not use Tailwind (no css/tailwind.css or no tailwindcss binary)"; \
    fi

# Create symlinks in Dockerfile (Cloudron pattern: dangling during build, valid at runtime)
# Like taiga-app: ln -s /app/data/media /app/code/taiga-back/media
RUN rm -rf /app/pkg/eleventy-site/content && ln -s /app/data/content /app/pkg/eleventy-site/content && \
    rm -rf /app/pkg/eleventy-site/_site && ln -s /app/data/site /app/pkg/eleventy-site/_site && \
    rm -rf /app/pkg/eleventy-site/images/user && mkdir -p /app/pkg/eleventy-site/images && ln -s /app/data/images /app/pkg/eleventy-site/images/user && \
    rm -rf /app/pkg/eleventy-site/.cache && ln -s /app/data/cache /app/pkg/eleventy-site/.cache && \
    ln -s /app/data/uploads /app/pkg/eleventy-site/uploads

# Patch routes.js: remove rate limiting from authenticated routes
# Upstream applies the same rate limiter to ALL routes. Authenticated routes (after
# indieauth.authenticate()) are already protected by auth — rate limiting them causes
# 429 errors during normal admin browsing, especially behind reverse proxies where
# all clients share a single IP. Rate limiting is kept on session routes (brute force)
# and public/well-known endpoints (abuse protection).
COPY patches/routes.js /app/code/node_modules/@indiekit/indiekit/lib/routes.js

# Patch error.js: suppress stack traces in production
# Upstream exposes full stack traces in both HTML and JSON error responses,
# leaking internal file paths and dependency versions. This patch only includes
# stack traces when NODE_ENV !== "production".
COPY patches/error.js /app/code/node_modules/@indiekit/indiekit/lib/middleware/error.js

# Patch indieauth.js: fix overly restrictive redirect URI validation
# Upstream regex /^\/[\w&/=?]*$/ rejects hyphens, dots, and percent-encoded
# characters in redirect paths, breaking login when returning to URLs like
# /auth/new-password or /files/upload-photos.
COPY patches/indieauth.js /app/code/node_modules/@indiekit/indiekit/lib/indieauth.js

ENV NODE_ENV=production

WORKDIR /app/code

# Copy migrated legacy content to be merged on first run
COPY migrated-content /app/pkg/migrated-content

# Copy config files
# Base files are templates in repo, personal overrides applied via Makefile before build
COPY start.sh syndicate-backlog.sh indiekit.config.js.template nginx.conf.template /app/pkg/
# Per-site indiekit.config.js composed by scripts/compose-site.mjs.
# start.sh copies this from /app/pkg/ to /app/data/config/ at container start.
COPY sites/${SITE}/.compiled/indiekit.config.js /app/pkg/indiekit.config.js
COPY nginx.conf redirects.map old-blog-redirects.map /app/pkg/

CMD [ "/app/pkg/start.sh" ]
