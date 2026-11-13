/** The secrets and settings the API reads at runtime. */
export type Bindings = {
  DATABASE_URL: string;
  BETTER_AUTH_SECRET: string;
  BETTER_AUTH_URL: string;
  /** Resend API key. Leave unset locally and emails are printed to the console instead. */
  RESEND_API_KEY?: string;
  /** The sender, such as `Fatigue <no-reply@fatigue.app>`. Required once RESEND_API_KEY is set. */
  EMAIL_FROM?: string;
  /** The private R2 bucket for photos and videos, reached through R2's S3 API (see the Social docs page). */
  R2_BUCKET?: string;
  /** The Cloudflare account that owns the bucket. It makes up the S3 endpoint. */
  R2_ACCOUNT_ID?: string;
  /** S3 keys from an R2 API token scoped to that bucket alone. */
  R2_ACCESS_KEY_ID?: string;
  R2_SECRET_ACCESS_KEY?: string;
  /** The iOS app's URL scheme, which the reset and verification pages hand off to. */
  APP_DEEP_LINK_SCHEME?: string;
};

export const defaultDeepLinkScheme = "fatigue";
