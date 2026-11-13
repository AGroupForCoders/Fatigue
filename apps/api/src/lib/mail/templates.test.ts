import { describe, expect, it } from "vitest";
import { escapeHtml, resetPasswordEmail, verifyEmail } from "./templates";

const url = "http://localhost:8787/api/auth/reset-password/abc?callbackURL=http%3A%2F%2Flocalhost%3A8787%2Fauth%2Freset-password";

describe("email templates", () => {
  it("puts the link in both the text and the HTML of the reset email", () => {
    const email = resetPasswordEmail({ name: "Anton", url });
    expect(email.subject).toBe("Reset your Fatigue password");
    expect(email.text).toContain("Hi Anton,");
    expect(email.text).toContain(url);
    expect(email.html).toContain(`href="${escapeHtml(url)}"`);
  });

  it("puts the link in both the text and the HTML of the verification email", () => {
    const email = verifyEmail({ name: "Anton", url });
    expect(email.subject).toBe("Verify your email for Fatigue");
    expect(email.text).toContain(url);
    expect(email.html).toContain(`href="${escapeHtml(url)}"`);
    expect(email.text).toContain("keep using the app");
  });

  it("escapes a name that looks like markup", () => {
    const email = verifyEmail({ name: "<b>Anton</b>", url });
    expect(email.html).not.toContain("<b>Anton</b>");
    expect(email.html).toContain("&lt;b&gt;Anton&lt;/b&gt;");
  });
});
