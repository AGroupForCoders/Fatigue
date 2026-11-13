import type { Email } from "./mailer";

/** The parts of an email a template produces. The caller adds `to`. */
export type EmailContent = Omit<Email, "to">;

type Recipient = { name: string; url: string };

/** Sent when someone taps "Forgot password?". The link is good for an hour. */
export function resetPasswordEmail({ name, url }: Recipient): EmailContent {
  return {
    subject: "Reset your Fatigue password",
    text: [
      `Hi ${name},`,
      "",
      "Someone asked to reset the password for this Fatigue account. If it was you, open this link on your phone:",
      "",
      url,
      "",
      "The link works for one hour. If you didn't ask for this, you can ignore this email and your password stays as it is.",
    ].join("\n"),
    html: layout({
      heading: "Reset your password",
      body: `Hi ${escapeHtml(name)},<br><br>Someone asked to reset the password for this Fatigue account. If it was you, open the link below on your phone.`,
      action: "Set a new password",
      url,
      footer: "The link works for one hour. If you didn't ask for this, you can ignore this email and your password stays as it is.",
    }),
  };
}

/** Sent right after sign-up, and again from Settings on request. */
export function verifyEmail({ name, url }: Recipient): EmailContent {
  return {
    subject: "Verify your email for Fatigue",
    text: [
      `Hi ${name},`,
      "",
      "Thanks for making a Fatigue account. Open this link to confirm this is your email:",
      "",
      url,
      "",
      "You can keep using the app before you do. If you didn't sign up, you can ignore this email.",
    ].join("\n"),
    html: layout({
      heading: "Verify your email",
      body: `Hi ${escapeHtml(name)},<br><br>Thanks for making a Fatigue account. Tap the button to confirm this is your email.`,
      action: "Verify email",
      url,
      footer: "You can keep using the app before you do. If you didn't sign up, you can ignore this email.",
    }),
  };
}

type Layout = { heading: string; body: string; action: string; url: string; footer: string };

/** Plain, one-column HTML in the light palette from packages/tokens. Inline styles, since email clients strip the rest. */
function layout({ heading, body, action, url, footer }: Layout) {
  const href = escapeHtml(url);
  return `<!doctype html>
<html>
  <body style="margin:0;padding:32px 16px;background:#ECE8E1;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#1C1B19;">
    <div style="max-width:480px;margin:0 auto;">
      <p style="margin:0 0 24px;font-size:13px;letter-spacing:0.08em;text-transform:uppercase;color:#625E58;">Fatigue</p>
      <h1 style="margin:0 0 16px;font-size:24px;font-weight:600;">${escapeHtml(heading)}</h1>
      <p style="margin:0 0 24px;font-size:16px;line-height:1.5;">${body}</p>
      <p style="margin:0 0 24px;"><a href="${href}" style="display:inline-block;padding:14px 20px;background:#1C1B19;color:#ECE8E1;text-decoration:none;border-radius:8px;font-size:16px;font-weight:600;">${escapeHtml(action)}</a></p>
      <p style="margin:0 0 24px;font-size:13px;line-height:1.5;color:#625E58;">If the button doesn't work, copy this link into Safari:<br><a href="${href}" style="color:#1C1B19;word-break:break-all;">${href}</a></p>
      <p style="margin:0;font-size:13px;line-height:1.5;color:#625E58;">${escapeHtml(footer)}</p>
    </div>
  </body>
</html>`;
}

export function escapeHtml(text: string) {
  return text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}
