import express from "express";

const APP_NAME = "aws-deployment-demo";

/**
 * Creates and returns the Express application.
 *
 * Configuration is injectable (config argument) so tests can verify the
 * behavior without touching process.env. When not provided, values are read
 * from environment variables:
 *   NODE_ENV      - deployment environment shown at "/"
 *   APP_VERSION   - git commit SHA baked into the Docker image at build time
 */
export function createApp(config = {}) {
  const app = express();

  app.disable("x-powered-by");

  // Central place to resolve runtime config so every endpoint reports the
  // same values for a given deployment.
  const resolveConfig = () => ({
    environment: config.environment || process.env.NODE_ENV || "development",
    version: config.version || process.env.APP_VERSION || "unknown",
  });

  app.get("/", (req, res) => {
    const { environment, version } = resolveConfig();
    res.status(200).json({
      application: APP_NAME,
      environment,
      version,
      timestamp: new Date().toISOString(),
    });
  });

  // Liveness probe target for Docker HEALTHCHECK and the deploy scripts.
  app.get("/health", (req, res) => {
    res.status(200).json({ status: "healthy" });
  });

  // Readiness endpoint: the process is up and able to serve requests.
  app.get("/ready", (req, res) => {
    res.status(200).json({
      status: "ready",
      uptimeSeconds: Math.floor(process.uptime()),
      timestamp: new Date().toISOString(),
    });
  });

  // Unknown routes -> structured 404 (never leaks internals).
  app.use((req, res) => {
    res.status(404).json({
      error: "not_found",
      message: `No route for ${req.method} ${req.originalUrl}`,
    });
  });

  // Error handler: logs details server-side, returns a generic body so no
  // secrets or stack traces are exposed through the API.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    console.error(`[error] ${req.method} ${req.originalUrl}: ${err.message}`);
    res.status(500).json({ error: "internal_server_error" });
  });

  return app;
}
