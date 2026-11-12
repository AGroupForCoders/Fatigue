import { describe, expect, it } from "vitest";
import { withoutChannelBinding } from "./client";

describe("withoutChannelBinding", () => {
  it("drops channel binding from a Neon URL and keeps sslmode", () => {
    const url = "postgresql://user:pass@ep-example-pooler.aws.neon.tech/neondb?sslmode=require&channel_binding=require";
    expect(withoutChannelBinding(url)).toBe("postgresql://user:pass@ep-example-pooler.aws.neon.tech/neondb?sslmode=require");
  });

  it("leaves a local URL alone", () => {
    const url = "postgres://fatigue:fatigue@localhost:5432/fatigue";
    expect(withoutChannelBinding(url)).toBe(url);
  });
});
