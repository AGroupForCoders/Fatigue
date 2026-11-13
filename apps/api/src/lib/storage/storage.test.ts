import { describe, expect, it } from "vitest";
import { parseListing, R2Storage, storageFromEnv } from "./storage";

const config = { accountId: "acct", bucket: "fatigue-media", accessKeyId: "AKID", secretAccessKey: "secret" };
const now = new Date("2026-11-13T08:00:00.000Z");

describe("R2 storage", () => {
  it("is off until all four settings are there", () => {
    expect(storageFromEnv({ R2_BUCKET: "b", R2_ACCOUNT_ID: "a", R2_ACCESS_KEY_ID: "k" })).toBeNull();
    expect(storageFromEnv({ R2_BUCKET: "b", R2_ACCOUNT_ID: "a", R2_ACCESS_KEY_ID: "k", R2_SECRET_ACCESS_KEY: "s" })).toBeInstanceOf(R2Storage);
  });

  it("signs an upload link that pins the type and size", async () => {
    const link = await new R2Storage(config).uploadLink("users/u/posts/p/m.jpg", "image/jpeg", 1234, 900, now);
    const url = new URL(link.url);
    expect(url.host).toBe("acct.r2.cloudflarestorage.com");
    expect(url.pathname).toBe("/fatigue-media/users/u/posts/p/m.jpg");
    expect(url.searchParams.get("X-Amz-Expires")).toBe("900");
    expect(url.searchParams.get("X-Amz-SignedHeaders")).toBe("content-length;content-type;host;if-none-match");
    expect(link.headers).toEqual({ "content-type": "image/jpeg", "content-length": "1234", "if-none-match": "*" });
    expect(link.expiresAt.toISOString()).toBe("2026-11-13T08:15:00.000Z");
  });

  it("signs a download link for an hour", async () => {
    const link = await new R2Storage(config).downloadLink("users/u/profile/x.jpg", 3600, now);
    expect(new URL(link.url).searchParams.get("X-Amz-Expires")).toBe("3600");
    expect(link.url).toContain("X-Amz-Signature=");
  });

  it("reads the size with HEAD, and null when there's nothing", async () => {
    const answers = [new Response(null, { status: 200, headers: { "content-length": "42" } }), new Response(null, { status: 404 })];
    const storage = new R2Storage(config, async () => answers.shift()!);
    expect(await storage.size("a")).toBe(42);
    expect(await storage.size("b")).toBeNull();
  });

  it("deletes a prefix page by page", async () => {
    const calls: string[] = [];
    const pages = [
      `<ListBucketResult><Contents><Key>users/u/a.jpg</Key></Contents><IsTruncated>true</IsTruncated><NextContinuationToken>t1</NextContinuationToken></ListBucketResult>`,
      `<ListBucketResult><Contents><Key>users/u/b&amp;c.mp4</Key></Contents><IsTruncated>false</IsTruncated></ListBucketResult>`,
    ];
    const storage = new R2Storage(config, async (input) => {
      const request = input as Request;
      calls.push(`${request.method} ${decodeURIComponent(new URL(request.url).pathname)}${new URL(request.url).searchParams.get("continuation-token") ?? ""}`);
      return request.method === "GET" ? new Response(pages.shift()) : new Response(null, { status: 204 });
    });
    await storage.deletePrefix("users/u/");
    expect(calls).toEqual([
      "GET /fatigue-media",
      "DELETE /fatigue-media/users/u/a.jpg",
      "GET /fatigue-mediat1",
      "DELETE /fatigue-media/users/u/b&c.mp4",
    ]);
  });

  it("reads keys and the next token from a listing", () => {
    expect(parseListing("<ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>")).toEqual({ keys: [], next: undefined });
  });
});
