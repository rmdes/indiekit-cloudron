FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

RUN mkdir -p /app/pkg /app/code
WORKDIR /app/code

# Install Node.js 22 (required by Indiekit)
ARG NODE_VERSION=22.22.0
RUN mkdir -p /usr/local/node-$NODE_VERSION && \
    curl -L https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz | tar zxf - --strip-components 1 -C /usr/local/node-$NODE_VERSION
ENV PATH /usr/local/node-$NODE_VERSION/bin:$PATH

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
        @indiekit/store-github \
        @indiekit/syndicator-mastodon \
        @indiekit/syndicator-bluesky \
        @indiekit/endpoint-json-feed \
        @indiekit/post-type-article \
        @indiekit/post-type-note \
        @indiekit/post-type-photo \
        @indiekit/post-type-bookmark \
        @indiekit/post-type-reply \
        @indiekit/post-type-like

ENV NODE_ENV=production

COPY start.sh indiekit.config.js.template /app/pkg/

CMD [ "/app/pkg/start.sh" ]
