/** The secrets and settings the API reads at runtime. */
export type Bindings = {
  DATABASE_URL: string;
  BETTER_AUTH_SECRET: string;
  BETTER_AUTH_URL: string;
  /** Resend API key. Leave unset locally and emails are printed to the console instead. */
  RESEND_API_KEY?: string;
  /** The sender, such as `Fatigue <no-reply@fatigue.app>`. Required once RESEND_API_KEY is set. */
  EMAIL_FROM?: string;
  /** The iOS app's URL scheme, which the reset and verification pages hand off to. */
  APP_DEEP_LINK_SCHEME?: string;
};

export const defaultDeepLinkScheme = "fatigue";
