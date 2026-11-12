import { describe, expect, it } from "vitest";
import { createApp } from "./app";

describe("app", () => {
  it("answers the health check without touching the database", async () => {
    const res = await createApp().request("/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });
});
