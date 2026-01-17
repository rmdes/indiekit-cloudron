FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# Cache buster - increment to force rebuild
ARG CACHE_BUST=2

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

# Install Indiekit and common plugins from npm
ARG INDIEKIT_VERSION=1.0.0-beta.25
RUN chown -R cloudron:cloudron /app/code && \
    gosu cloudron:cloudron npm install \
        @indiekit/indiekit@${INDIEKIT_VERSION} \
        @indiekit/preset-hugo \
        @indiekit/store-file-system \
        @indiekit/syndicator-mastodon \
        @indiekit/syndicator-bluesky \
        @indiekit/endpoint-json-feed \
        @indiekit/endpoint-webmention-io \
        @indiekit/preset-eleventy \
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
        @indiekit/post-type-video

# Copy and install local endpoint-github plugin
COPY endpoint-github /app/code/endpoint-github
RUN cd /app/code && gosu cloudron:cloudron npm install ./endpoint-github

ENV NODE_ENV=production

COPY start.sh indiekit.config.js.template /app/pkg/

CMD [ "/app/pkg/start.sh" ]
