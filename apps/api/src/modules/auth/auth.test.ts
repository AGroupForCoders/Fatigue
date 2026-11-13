import { betterAuth } from "better-auth";
import { memoryAdapter } from "better-auth/adapters/memory";
import { describe, expect, it } from "vitest";
import type { Email, Mailer } from "../../lib/mail/mailer";
import { authOptions } from "./auth";

/** Remembers every email instead of sending it. */
class RecordingMailer implements Mailer {
  sent: Email[] = [];
  async send(email: Email) {
    this.sent.push(email);
  }
}

function makeAuth(mailer: Mailer) {
  return betterAuth({
    ...authOptions({ secret: "test-secret-that-is-long-enough-for-tests", baseURL: "http://localhost:8787", mailer }),
    database: memoryAdapter({ user: [], session: [], account: [], verification: [] }),
  });
}

describe("auth", () => {
  it("sends a verification email on sign-up and still signs you in", async () => {
    const mailer = new RecordingMailer();
    const auth = makeAuth(mailer);

    const result = await auth.api.signUpEmail({
      body: { name: "Anton", email: "lifter@example.com", password: "password123", callbackURL: "http://localhost:8787/auth/email-verified" },
    });

    expect(result.token).toBeTruthy();
    expect(result.user.emailVerified).toBe(false);
    expect(mailer.sent).toHaveLength(1);
    expect(mailer.sent[0]!.to).toBe("lifter@example.com");
    expect(mailer.sent[0]!.subject).toBe("Verify your email for Fatigue");
    expect(mailer.sent[0]!.text).toMatch(/http:\/\/localhost:8787\/api\/auth\/verify-email\?token=.+&callbackURL=http%3A%2F%2Flocalhost%3A8787%2Fauth%2Femail-verified/);
  });

  it("emails a reset link that ends on the landing page, and the token then changes the password", async () => {
    const mailer = new RecordingMailer();
    const auth = makeAuth(mailer);
    await auth.api.signUpEmail({ body: { name: "Anton", email: "lifter@example.com", password: "password123" } });
    mailer.sent = [];

    await auth.api.requestPasswordReset({ body: { email: "lifter@example.com", redirectTo: "http://localhost:8787/auth/reset-password" } });

    expect(mailer.sent).toHaveLength(1);
    expect(mailer.sent[0]!.subject).toBe("Reset your Fatigue password");
    const link = mailer.sent[0]!.text.match(/http:\/\/localhost:8787\/api\/auth\/reset-password\/(\S+)\?callbackURL=(\S+)/);
    expect(link).not.toBeNull();
    expect(decodeURIComponent(link![2]!)).toBe("http://localhost:8787/auth/reset-password");

    await auth.api.resetPassword({ body: { token: link![1]!, newPassword: "newpassword456" } });
    const signedIn = await auth.api.signInEmail({ body: { email: "lifter@example.com", password: "newpassword456" } });
    expect(signedIn.user.email).toBe("lifter@example.com");
  });

  it("says nothing about an unknown email", async () => {
    const mailer = new RecordingMailer();
    const auth = makeAuth(mailer);
    const result = await auth.api.requestPasswordReset({ body: { email: "nobody@example.com" } });
    expect(result.status).toBe(true);
    expect(mailer.sent).toHaveLength(0);
  });
});
