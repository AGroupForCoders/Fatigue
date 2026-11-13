import { describe, expect, it } from "vitest";
import { productionConfig } from "./production-config.mjs";

const core = {
  DATABASE_URL: "postgres://u:p@ep-x-pooler.ap-southeast-2.aws.neon.tech/neondb?sslmode=require",
  BETTER_AUTH_SECRET: "secret",
  BETTER_AUTH_URL: "https://fatigue-api.example.workers.dev",
};
const r2 = { R2_ACCESS_KEY_ID: "id", R2_SECRET_ACCESS_KEY: "key", R2_BUCKET: "fatigue-media", R2_ACCOUNT_ID: "acct" };
const resend = { RESEND_API_KEY: "re_x", EMAIL_FROM: "Fatigue <no-reply@mail.example.com>" };

describe("productionConfig", () => {
  it("splits a full setup into secrets and plain vars", () => {
    const config = productionConfig({ ...core, ...r2, ...resend });
    expect(config.problems).toEqual([]);
    expect(Object.keys(config.secrets).sort()).toEqual(
      ["BETTER_AUTH_SECRET", "DATABASE_URL", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "RESEND_API_KEY"].sort(),
    );
    expect(config.vars).toEqual({
      BETTER_AUTH_URL: core.BETTER_AUTH_URL,
      R2_BUCKET: "fatigue-media",
      R2_ACCOUNT_ID: "acct",
      EMAIL_FROM: resend.EMAIL_FROM,
    });
  });

  it("deploys without a provider that is wholly unset", () => {
    const config = productionConfig(core);
    expect(config.problems).toEqual([]);
    expect(config.skipped).toEqual(["R2", "Resend"]);
  });

  it("refuses a provider that is half set up", () => {
    const config = productionConfig({ ...core, RESEND_API_KEY: "re_x" });
    expect(config.problems).toEqual(["Resend is half set up: EMAIL_FROM missing"]);
  });

  it("refuses a missing core value", () => {
    expect(productionConfig({ ...core, BETTER_AUTH_SECRET: " " }).problems).toEqual(["BETTER_AUTH_SECRET is not set"]);
  });

  it("refuses an auth URL with a trailing slash", () => {
    const config = productionConfig({ ...core, BETTER_AUTH_URL: "https://fatigue-api.example.workers.dev/" });
    expect(config.problems).toHaveLength(1);
  });

  it("refuses Neon's direct URL for the Worker", () => {
    const config = productionConfig({ ...core, DATABASE_URL: "postgres://u:p@ep-x.neon.tech/neondb" });
    expect(config.problems).toHaveLength(1);
  });
});
