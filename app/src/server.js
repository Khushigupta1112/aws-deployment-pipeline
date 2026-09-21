import { createApp } from "./app.js";

const PORT = Number(process.env.PORT || 3000);
const NODE_ENV = process.env.NODE_ENV || "development";
const APP_VERSION = process.env.APP_VERSION || "unknown";

const app = createApp();

const server = app.listen(PORT, () => {
  console.log(
    `[server] application=${app.get("name") ?? "aws-deployment-demo"} ` +
      `environment=${NODE_ENV} version=${APP_VERSION} listening on port ${PORT}`
  );
});

// Graceful shutdown: stop accepting new connections, let in-flight requests
// finish, then exit. Docker stop sends SIGTERM first; the timeout is a
// safety net so the process never hangs forever.
function shutdown(signal) {
  console.log(`[server] ${signal} received, shutting down gracefully...`);
  server.close(() => {
    console.log("[server] server closed, exiting.");
    process.exit(0);
  });
  setTimeout(() => {
    console.error("[server] graceful shutdown timed out, forcing exit.");
    process.exit(1);
  }, 10_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
