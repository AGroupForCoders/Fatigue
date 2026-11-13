import { describe, expect, it } from "vitest";
import { createApp } from "../../app";
import { emailVerifiedDeepLink, resetPasswordDeepLink } from "./auth.pages";

const env = { APP_DEEP_LINK_SCHEME: "fatigue" };

describe("deep links", () => {
  it("builds the reset link with the token escaped", () => {
    expect(resetPasswordDeepLink("fatigue", "abc/def")).toBe("fatigue://reset-password?token=abc%2Fdef");
    expect(emailVerifiedDeepLink("fatigue")).toBe("fatigue://email-verified");
  });
});

describe("auth landing pages", () => {
  it("hands a valid reset token to the app", async () => {
    const res = await createApp().request("/auth/reset-password?token=abc123", {}, env);
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('href="fatigue://reset-password?token=abc123"');
    expect(html).toContain('url=fatigue://reset-password?token=abc123');
  });

  it("explains an expired reset link instead of opening the app", async () => {
    const res = await createApp().request("/auth/reset-password?error=INVALID_TOKEN", {}, env);
    expect(res.status).toBe(400);
    expect(await res.text()).not.toContain("fatigue://");
  });

  it("falls back to the default scheme and opens the app after verifying", async () => {
    const res = await createApp().request("/auth/email-verified", {}, {});
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('href="fatigue://email-verified"');
  });

  it("explains an expired verification link", async () => {
    const res = await createApp().request("/auth/email-verified?error=INVALID_TOKEN", {}, env);
    expect(res.status).toBe(400);
  });
});
