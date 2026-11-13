import { Hono } from "hono";
import type { AppEnv } from "../../context";
import { defaultDeepLinkScheme } from "../../env";
import { escapeHtml } from "../../lib/mail/templates";

/**
 * Where the links in the emails land after Better Auth has checked them.
 *
 * Email clients open links in a browser, and a browser can't be redirected straight into the app
 * reliably from a 302. So Better Auth sends the browser here, and this page hands off to the app's
 * URL scheme: a redirect on load, and a button in case the redirect is blocked.
 */
export const authPages = new Hono<AppEnv>()
  .get("/reset-password", (c) => {
    const scheme = c.env.APP_DEEP_LINK_SCHEME || defaultDeepLinkScheme;
    const token = c.req.query("token");
    if (!token || c.req.query("error")) {
      return c.html(page({ heading: "This link has expired", body: "Ask for a new one from Forgot password? in the app." }), 400);
    }
    return c.html(page({ heading: "Set a new password", body: "Opening Fatigue…", open: resetPasswordDeepLink(scheme, token) }));
  })
  .get("/email-verified", (c) => {
    const scheme = c.env.APP_DEEP_LINK_SCHEME || defaultDeepLinkScheme;
    if (c.req.query("error")) {
      return c.html(page({ heading: "This link has expired", body: "Ask for a new one from Settings in the app." }), 400);
    }
    return c.html(page({ heading: "Email verified", body: "Thanks. You're all set.", open: emailVerifiedDeepLink(scheme) }));
  });

/** Opens the app on the "Set a new password" screen with the one-time token Better Auth issued. */
export function resetPasswordDeepLink(scheme: string, token: string) {
  return `${scheme}://reset-password?token=${encodeURIComponent(token)}`;
}

/** Opens the app so it refreshes the account and shows the email as verified. */
export function emailVerifiedDeepLink(scheme: string) {
  return `${scheme}://email-verified`;
}

type Page = { heading: string; body: string; open?: string };

function page({ heading, body, open }: Page) {
  const href = open ? escapeHtml(open) : null;
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(heading)} · Fatigue</title>
    ${href ? `<meta http-equiv="refresh" content="0;url=${href}">` : ""}
  </head>
  <body style="margin:0;padding:48px 24px;background:#ECE8E1;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#1C1B19;">
    <p style="margin:0 0 24px;font-size:13px;letter-spacing:0.08em;text-transform:uppercase;color:#625E58;">Fatigue</p>
    <h1 style="margin:0 0 16px;font-size:24px;font-weight:600;">${escapeHtml(heading)}</h1>
    <p style="margin:0 0 24px;font-size:16px;line-height:1.5;">${escapeHtml(body)}</p>
    ${href ? `<p style="margin:0;"><a href="${href}" style="display:inline-block;padding:14px 20px;background:#1C1B19;color:#ECE8E1;text-decoration:none;border-radius:8px;font-size:16px;font-weight:600;">Open Fatigue</a></p>` : ""}
  </body>
</html>`;
}
