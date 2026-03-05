FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# Cache buster - increment to force rebuild
ARG CACHE_BUST=298

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

# Copy package.json with npm overrides
COPY package.json /app/code/

# Install Indiekit and plugins
# Note: @indiekit/endpoint-auth is overridden via package.json
# Note: @rmdes/indiekit-preset-eleventy replaces @indiekit/preset-eleventy (permalink fix)
# Note: @rmdes/indiekit-endpoint-micropub replaces @indiekit/endpoint-micropub (typeConfig validation fix)
ARG INDIEKIT_VERSION=1.0.0-beta.25
RUN chown -R cloudron:cloudron /app/code && \
    gosu cloudron:cloudron npm cache clean --force && \
    gosu cloudron:cloudron npm install --legacy-peer-deps \
        @indiekit/indiekit@${INDIEKIT_VERSION} \
        @indiekit/preset-hugo \
        @indiekit/store-file-system \
        @rmdes/indiekit-syndicator-mastodon@1.0.8 \
        @rmdes/indiekit-syndicator-bluesky@1.0.18 \
        @rmdes/indiekit-syndicator-linkedin@1.0.2 \
        @rmdes/indiekit-endpoint-linkedin@1.0.5 \
        @rmdes/indiekit-endpoint-micropub@1.0.0-beta.29 \
        @rmdes/indiekit-endpoint-syndicate@1.0.0-beta.36 \
        @rmdes/indiekit-endpoint-share@1.0.2 \
        @indiekit/endpoint-json-feed \
        @rmdes/indiekit-endpoint-webmention-io@1.0.7 \
        @indiekit/post-type-article \
        @indiekit/post-type-audio \
        @indiekit/post-type-bookmark \
        @indiekit/post-type-event \
        @indiekit/post-type-jam \
        @indiekit/post-type-like \
        @indiekit/post-type-note \
        @indiekit/post-type-photo \
        @indiekit/post-type-reply \
        @indiekit/post-type-repost \
        @indiekit/post-type-rsvp \
        @indiekit/post-type-video \
        @rmdes/indiekit-post-type-page@1.0.4 \
        @rmdes/indiekit-endpoint-github@1.2.3 \
        @rmdes/indiekit-endpoint-funkwhale@1.0.11 \
        @rmdes/indiekit-endpoint-lastfm@1.0.12 \
        @rmdes/indiekit-endpoint-youtube@1.2.3 \
        @rmdes/indiekit-endpoint-rss@1.0.14 \
        @rmdes/indiekit-endpoint-microsub@1.0.43 \
        @rmdes/indiekit-syndicator-indienews@1.0.1 \
        @rmdes/indiekit-endpoint-podroll@1.0.11 \
        @rmdes/indiekit-endpoint-webmention-sender@1.0.6 \
        @rmdes/indiekit-endpoint-blogroll@1.0.23 \
        @rmdes/indiekit-endpoint-homepage@1.0.21 \
        @rmdes/indiekit-endpoint-cv@1.0.24 \
        @rmdes/indiekit-preset-eleventy@1.0.0-beta.38 \
        @rmdes/indiekit-endpoint-files@1.0.0 \
        @rmdes/indiekit-endpoint-conversations@2.1.6 \
        @rmdes/indiekit-endpoint-comments@1.0.0 \
        @rmdes/indiekit-endpoint-readlater@1.0.2 \
        @rmdes/indiekit-endpoint-activitypub@2.7.1

# Copy Eleventy site (submodule with overrides already applied by Makefile)
# The Makefile's 'prepare' step copies overrides/ contents over the submodule before build
COPY eleventy-site /app/pkg/eleventy-site
RUN chown -R cloudron:cloudron /app/pkg/eleventy-site

# Install Eleventy site dependencies
WORKDIR /app/pkg/eleventy-site
RUN gosu cloudron:cloudron npm install

# Build Tailwind CSS
RUN gosu cloudron:cloudron ./node_modules/.bin/tailwindcss -i css/tailwind.css -o css/style.css --minify

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
COPY indiekit.config.js nginx.conf redirects.map old-blog-redirects.map /app/pkg/

CMD [ "/app/pkg/start.sh" ]
