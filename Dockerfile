# syntax=docker/dockerfile:1
FROM node:24.22.2-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9 AS frontend
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build-only

FROM ruby:3.4.12-slim-bookworm@sha256:c81ac5a2118161a9e01cfbb2da6d68ae1c96d3e6dff14fb1f7f485fee538babe AS gems
RUN apt-get update && apt-get install --no-install-recommends -y build-essential libpq-dev libyaml-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test BUNDLE_PATH=/usr/local/bundle
COPY backend/Gemfile backend/Gemfile.lock ./
RUN gem install bundler -v 4.0.22 --no-document && bundle _4.0.22_ install

FROM ruby:3.4.12-slim-bookworm@sha256:c81ac5a2118161a9e01cfbb2da6d68ae1c96d3e6dff14fb1f7f485fee538babe
RUN apt-get update && apt-get install --no-install-recommends -y libpq5 libyaml-0-2 curl && rm -rf /var/lib/apt/lists/* \
    && groupadd --system calendar && useradd --system --gid calendar --create-home calendar
WORKDIR /app
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test BUNDLE_PATH=/usr/local/bundle PORT=3000
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --chown=calendar:calendar backend/ ./
COPY --from=frontend --chown=calendar:calendar /build/frontend/dist/ ./public/
RUN mkdir -p tmp/pids log && chown -R calendar:calendar tmp log
USER calendar
EXPOSE 3000
ENTRYPOINT ["ruby", "/app/bin/container-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
