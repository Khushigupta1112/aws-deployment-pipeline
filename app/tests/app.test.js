import { describe, expect, it } from "vitest";
import request from "supertest";

import { createApp } from "../src/app.js";

// Tests build the app with an explicit config so assertions on environment
// and version are deterministic regardless of the machine running them.
const app = createApp({ environment: "production", version: "test-sha" });

describe("GET /", () => {
  it("returns application metadata with HTTP 200", async () => {
    const res = await request(app).get("/");

    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      application: "aws-deployment-demo",
      environment: "production",
      version: "test-sha",
    });
    expect(typeof res.body.timestamp).toBe("string");
    expect(Number.isNaN(Date.parse(res.body.timestamp))).toBe(false);
  });

  it("exposes a parseable JSON content type", async () => {
    const res = await request(app).get("/");
    expect(res.headers["content-type"]).toMatch(/application\/json/);
  });
});

describe("GET /health", () => {
  it("returns healthy with HTTP 200", async () => {
    const res = await request(app).get("/health");

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "healthy" });
  });
});

describe("GET /ready", () => {
  it("returns ready with HTTP 200", async () => {
    const res = await request(app).get("/ready");

    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ready");
    expect(res.body.uptimeSeconds).toBeGreaterThanOrEqual(0);
  });
});

describe("unknown routes", () => {
  it("returns 404 with a structured error for a bad path", async () => {
    const res = await request(app).get("/does-not-exist");

    expect(res.status).toBe(404);
    expect(res.body.error).toBe("not_found");
    expect(res.body.message).toContain("/does-not-exist");
  });

  it("returns 404 for unsupported methods on known paths", async () => {
    const res = await request(app).delete("/health");
    expect(res.status).toBe(404);
  });
});

describe("application startup configuration", () => {
  it("falls back to defaults when no config or env is provided", () => {
    const freshApp = createApp();
    expect(freshApp).toBeDefined();
    expect(typeof freshApp.listen).toBe("function");
  });

  it("reflects injected environment and version at runtime", async () => {
    const custom = createApp({ environment: "staging", version: "abc1234" });
    const res = await request(custom).get("/");

    expect(res.body.environment).toBe("staging");
    expect(res.body.version).toBe("abc1234");
  });
});
