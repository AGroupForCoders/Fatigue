/** One email, ready to send. Templates in templates.ts build everything but `to`. */
export type Email = {
  to: string;
  subject: string;
  text: string;
  html: string;
};

/** Sends email. Resend in production, the console when there is no API key. */
export interface Mailer {
  send(email: Email): Promise<void>;
}

/**
 * Sends through Resend's REST API with plain `fetch`, which is all Workers need.
 * The SDK would only add weight for one endpoint.
 */
export class ResendMailer implements Mailer {
  static readonly endpoint = "https://api.resend.com/emails";

  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  async send(email: Email) {
    const res = await this.fetchFn(ResendMailer.endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: this.from, to: [email.to], subject: email.subject, text: email.text, html: email.html }),
    });
    if (!res.ok) {
      throw new Error(`Resend refused the email (${res.status}): ${await res.text()}`);
    }
  }
}

/** Prints the email instead of sending it, so local dev shows the link in the Wrangler log. */
export class ConsoleMailer implements Mailer {
  constructor(private readonly log: (message: string) => void = console.log) {}

  async send(email: Email) {
    this.log(`[mail] To: ${email.to}\n[mail] Subject: ${email.subject}\n${email.text}`);
  }
}

/** Does nothing. For tests that don't care about email. */
export class NoopMailer implements Mailer {
  async send() {}
}

export type MailSettings = { RESEND_API_KEY?: string; EMAIL_FROM?: string };

/** Resend when the key is set, the console otherwise. */
export function createMailer(settings: MailSettings): Mailer {
  if (!settings.RESEND_API_KEY) return new ConsoleMailer();
  if (!settings.EMAIL_FROM) throw new Error("EMAIL_FROM must be set when RESEND_API_KEY is.");
  return new ResendMailer(settings.RESEND_API_KEY, settings.EMAIL_FROM);
}
