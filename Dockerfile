FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# Cache buster - increment to force rebuild
ARG CACHE_BUST=129

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
ARG INDIEKIT_VERSION=1.0.0-beta.25
RUN chown -R cloudron:cloudron /app/code && \
    gosu cloudron:cloudron npm cache clean --force && \
    gosu cloudron:cloudron npm install \
        @indiekit/indiekit@${INDIEKIT_VERSION} \
        @indiekit/preset-hugo \
        @indiekit/store-file-system \
        @indiekit/syndicator-mastodon \
        @indiekit/syndicator-bluesky \
        @indiekit/endpoint-syndicate \
        @indiekit/endpoint-json-feed \
        @indiekit/endpoint-webmention-io \
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
        @rmdes/indiekit-endpoint-github \
        @rmdes/indiekit-endpoint-funkwhale \
        @rmdes/indiekit-endpoint-lastfm \
        @rmdes/indiekit-endpoint-youtube \
        @rmdes/indiekit-endpoint-rss \
        @rmdes/indiekit-endpoint-microsub \
        @rmdes/indiekit-endpoint-webmentions-proxy \
        @rmdes/indiekit-preset-eleventy

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

ENV NODE_ENV=production

WORKDIR /app/code

# Copy migrated legacy content to be merged on first run
COPY migrated-content /app/pkg/migrated-content

# Copy config files
# Base files are templates in repo, personal overrides applied via Makefile before build
COPY start.sh indiekit.config.js.template nginx.conf.template /app/pkg/
COPY indiekit.config.js nginx.conf redirects.map old-blog-redirects.map /app/pkg/

CMD [ "/app/pkg/start.sh" ]
