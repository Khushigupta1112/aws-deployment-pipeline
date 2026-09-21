# Multi-stage build: dependencies stage keeps the runtime image free of
# build tooling, cache files, and dev dependencies.
FROM node:24-alpine AS deps
WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Runtime stage: official lightweight LTS image, non-root user.
FROM node:24-alpine
WORKDIR /app

# APP_VERSION is the short git commit SHA; the workflow passes it as a build
# arg so the image always reports the exact commit it was built from.
ARG APP_VERSION=local
ENV NODE_ENV=production \
    PORT=3000 \
    APP_VERSION=${APP_VERSION}

COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node app/package.json ./package.json
COPY --chown=node:node app/src ./src

# Official images ship a non-root "node" user.
USER node

EXPOSE 3000

# Container-level liveness probe, independent of any orchestration layer.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 || exit 1

CMD ["node", "src/server.js"]
