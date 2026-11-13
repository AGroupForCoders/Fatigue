import { describe, expect, it, vi } from "vitest";
import { ConsoleMailer, ResendMailer, createMailer } from "./mailer";

const email = { to: "lifter@example.com", subject: "Hi", text: "Hello", html: "<p>Hello</p>" };

describe("ResendMailer", () => {
  it("posts the email to Resend with the key as a bearer token", async () => {
    const fetchFn = vi.fn(async () => new Response("{}", { status: 200 }));
    await new ResendMailer("re_test", "Fatigue <no-reply@example.com>", fetchFn).send(email);

    expect(fetchFn).toHaveBeenCalledOnce();
    const [endpoint, init] = fetchFn.mock.calls[0] as unknown as [string, RequestInit];
    expect(endpoint).toBe("https://api.resend.com/emails");
    expect(init.method).toBe("POST");
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer re_test");
    expect(JSON.parse(init.body as string)).toEqual({
      from: "Fatigue <no-reply@example.com>",
      to: ["lifter@example.com"],
      subject: "Hi",
      text: "Hello",
      html: "<p>Hello</p>",
    });
  });

  it("throws when Resend says no", async () => {
    const fetchFn = vi.fn(async () => new Response("bad key", { status: 401 }));
    await expect(new ResendMailer("re_bad", "x@example.com", fetchFn).send(email)).rejects.toThrow("401");
  });
});

describe("createMailer", () => {
  it("prints to the console when there is no Resend key", async () => {
    const lines: string[] = [];
    const mailer = createMailer({});
    expect(mailer).toBeInstanceOf(ConsoleMailer);
    await new ConsoleMailer((line) => lines.push(line)).send(email);
    expect(lines[0]).toContain("lifter@example.com");
    expect(lines[0]).toContain("Hello");
  });

  it("uses Resend once the key is set, and insists on a sender", () => {
    expect(createMailer({ RESEND_API_KEY: "re_test", EMAIL_FROM: "x@example.com" })).toBeInstanceOf(ResendMailer);
    expect(() => createMailer({ RESEND_API_KEY: "re_test" })).toThrow("EMAIL_FROM");
  });
});
