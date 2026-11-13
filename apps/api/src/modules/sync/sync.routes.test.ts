import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { sql } from "drizzle-orm";
import { createUser, testApp, testDb, type TestDb } from "../../lib/testing";
import { syncRoutes } from "./sync.routes";
import { SYNC_SCHEMA_VERSION } from "./sync.service";

let db: TestDb;
let close: () => Promise<void>;
let app: ReturnType<typeof testApp>;

beforeAll(async () => {
  ({ db, close } = await testDb());
  app = testApp(db, "/api/sync", syncRoutes);
});
afterAll(() => close());
beforeEach(async () => {
  await db.execute(sql`truncate "user" cascade`);
  await createUser(db, "ana");
});

// In the past, so the server never clamps it as a clock error.
const now = 1_700_000_000_000;
const headers = { "Content-Type": "application/json", "X-Test-User": "ana" };
const routine = { id: "r1", updated_at: now, deleted_at: null, name: "Push", position: 0 };

function pushRequest(body: unknown, user = "ana") {
  return app.request("/api/sync/push", { method: "POST", headers: { ...headers, "X-Test-User": user }, body: JSON.stringify(body) });
}

describe("sync routes", () => {
  it("pushes, then pulls the same rows back with a cursor", async () => {
    const pushed = await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION, changes: [{ table: "routine", row: routine }] });
    expect(pushed.status).toBe(200);
    expect(await pushed.json()).toEqual({ accepted: [{ table: "routine", id: "r1", updated_at: now }], rejected: [] });

    const pulled = await app.request(`/api/sync/pull?since=0&schemaVersion=${SYNC_SCHEMA_VERSION}`, { headers });
    expect(pulled.status).toBe(200);
    const body = (await pulled.json()) as { rows: unknown[]; next: number; hasMore: boolean };
    expect(body.rows).toEqual([{ table: "routine", seq: body.next, row: routine }]);
    expect(body.hasMore).toBe(false);

    const again = await app.request(`/api/sync/pull?since=${body.next}&schemaVersion=${SYNC_SCHEMA_VERSION}`, { headers });
    expect(await again.json()).toEqual({ rows: [], next: body.next, hasMore: false });
  });

  it("needs a session", async () => {
    const res = await app.request("/api/sync/pull?since=0&schemaVersion=1");
    expect(res.status).toBe(401);
  });

  it("tells an older app to update", async () => {
    const pushed = await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION - 1, changes: [] });
    expect(pushed.status).toBe(426);
    expect(await pushed.json()).toEqual({ error: "Update the app to sync." });

    const pulled = await app.request(`/api/sync/pull?since=0&schemaVersion=${SYNC_SCHEMA_VERSION - 1}`, { headers });
    expect(pulled.status).toBe(426);
  });

  it("refuses a newer app and a missing version", async () => {
    expect((await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION + 1, changes: [] })).status).toBe(400);
    expect((await pushRequest({ changes: [] })).status).toBe(400);
    expect((await app.request("/api/sync/pull?since=0", { headers })).status).toBe(400);
  });

  it("rejects a body that isn't a list of changes", async () => {
    expect((await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION })).status).toBe(400);
    expect((await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION, changes: [{ row: routine }] })).status).toBe(400);
    expect((await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION, changes: [{ table: "routine" }] })).status).toBe(400);
    const res = await app.request("/api/sync/push", { method: "POST", headers, body: "not json" });
    expect(res.status).toBe(400);
  });

  it("checks the cursor and page size", async () => {
    expect((await app.request(`/api/sync/pull?since=-1&schemaVersion=${SYNC_SCHEMA_VERSION}`, { headers })).status).toBe(400);
    expect((await app.request(`/api/sync/pull?since=abc&schemaVersion=${SYNC_SCHEMA_VERSION}`, { headers })).status).toBe(400);
    expect((await app.request(`/api/sync/pull?since=0&limit=0&schemaVersion=${SYNC_SCHEMA_VERSION}`, { headers })).status).toBe(400);
  });

  it("reports rows owned by another account in the response, not as a failed request", async () => {
    await createUser(db, "ben");
    await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION, changes: [{ table: "routine", row: routine }] });
    const res = await pushRequest({ schemaVersion: SYNC_SCHEMA_VERSION, changes: [{ table: "routine", row: routine }] }, "ben");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ accepted: [], rejected: [{ table: "routine", id: "r1", reason: "This row belongs to another account." }] });
  });
});
