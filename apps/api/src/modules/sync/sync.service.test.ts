import { sql } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import * as schema from "../../db/schema";
import { createUser, testDb } from "../../lib/testing";
import { CLOCK_SKEW_MS, pull, push, type SyncRow } from "./sync.service";

let db: Awaited<ReturnType<typeof testDb>>["db"];
let close: () => Promise<void>;

beforeAll(async () => ({ db, close } = await testDb()));
afterAll(() => close());
beforeEach(async () => {
  await db.execute(sql`truncate "user" cascade`);
  await createUser(db, "ana");
  await createUser(db, "ben");
});

const now = 1_800_000_000_000;

function workout(id: string, updatedAt: number, extra: Partial<SyncRow> = {}): SyncRow {
  return { id, updated_at: updatedAt, deleted_at: null, title: "Legs", note: null, started_at: now - 3_600_000, finished_at: now, routine_id: null, ...extra };
}

describe("push", () => {
  it("stores new rows and pulls them back as they were sent", async () => {
    const result = await push(db, "ana", [{ table: "workout", row: workout("w1", now) }], now);
    expect(result).toEqual({ accepted: [{ table: "workout", id: "w1", updated_at: now }], rejected: [] });

    const pulled = await pull(db, "ana", 0);
    expect(pulled.rows).toHaveLength(1);
    expect(pulled.rows[0].table).toBe("workout");
    expect(pulled.rows[0].row).toEqual(workout("w1", now));
    expect(pulled.hasMore).toBe(false);
    expect(pulled.next).toBe(pulled.rows[0].seq);
  });

  it("keeps the later updated_at when the same row arrives twice, whichever order", async () => {
    await push(db, "ana", [{ table: "workout", row: workout("w1", now + 10, { title: "Later" }) }], now + 10);
    await push(db, "ana", [{ table: "workout", row: workout("w1", now, { title: "Earlier" }) }], now + 10);
    let [row] = await db.select().from(schema.workout);
    expect(row.title).toBe("Later");
    expect(row.updatedAt).toBe(now + 10);

    await push(db, "ana", [{ table: "workout", row: workout("w1", now + 20, { title: "Latest" }) }], now + 20);
    [row] = await db.select().from(schema.workout);
    expect(row.title).toBe("Latest");
  });

  it("keeps the server's row on a tie", async () => {
    await push(db, "ana", [{ table: "workout", row: workout("w1", now, { title: "First" }) }], now);
    await push(db, "ana", [{ table: "workout", row: workout("w1", now, { title: "Second" }) }], now);
    const [row] = await db.select().from(schema.workout);
    expect(row.title).toBe("First");
  });

  it("takes the newest copy when one batch has the same row twice", async () => {
    await push(db, "ana", [
      { table: "workout", row: workout("w1", now + 5, { title: "B" }) },
      { table: "workout", row: workout("w1", now, { title: "A" }) },
    ], now + 5);
    const [row] = await db.select().from(schema.workout);
    expect(row.title).toBe("B");
  });

  it("syncs a deletion like any other change", async () => {
    await push(db, "ana", [{ table: "workout", row: workout("w1", now) }], now);
    await push(db, "ana", [{ table: "workout", row: workout("w1", now + 1, { deleted_at: now + 1 }) }], now + 1);
    const pulled = await pull(db, "ana", 0);
    expect(pulled.rows).toHaveLength(1);
    expect(pulled.rows[0].row.deleted_at).toBe(now + 1);
  });

  it("stamps the owner from the session and rejects a row that belongs to someone else", async () => {
    await push(db, "ana", [{ table: "workout", row: workout("w1", now) }], now);
    const result = await push(db, "ben", [
      { table: "workout", row: workout("w1", now + 100, { title: "Stolen" }) },
      { table: "workout", row: workout("w2", now) },
    ], now + 100);
    expect(result.rejected).toEqual([{ table: "workout", id: "w1", reason: "This row belongs to another account." }]);
    expect(result.accepted).toEqual([{ table: "workout", id: "w2", updated_at: now }]);

    const rows = await db.select().from(schema.workout).orderBy(schema.workout.id);
    expect(rows.map((r) => [r.id, r.userId, r.title])).toEqual([["w1", "ana", "Legs"], ["w2", "ben", "Legs"]]);
    expect((await pull(db, "ben", 0)).rows.map((r) => r.row.id)).toEqual(["w2"]);
  });

  it("never lets the body pick user_id or server_seq", async () => {
    const result = await push(db, "ana", [
      { table: "workout", row: { ...workout("w1", now), user_id: "ben" } },
      { table: "workout", row: { ...workout("w2", now), server_seq: 1 } },
    ], now);
    expect(result.rejected.map((r) => r.reason)).toEqual(["Unknown column user_id.", "Unknown column server_seq."]);
    expect(await db.select().from(schema.workout)).toHaveLength(0);
  });

  it("rejects malformed rows one at a time and applies the rest", async () => {
    const result = await push(db, "ana", [
      { table: "workout", row: workout("w1", now) },
      { table: "workout", row: { id: "w2", updated_at: now, deleted_at: null, title: "No start" } },
      { table: "workout", row: { ...workout("w3", now), title: 5 } },
      { table: "workout", row: { ...workout("w4", now), started_at: 1.5 } },
      { table: "workout", row: { ...workout("w5", now), nope: 1 } },
      { table: "workout", row: { updated_at: now } },
      { table: "nope", row: workout("w6", now) },
    ], now);
    expect(result.accepted.map((a) => a.id)).toEqual(["w1"]);
    expect(result.rejected).toEqual([
      { table: "workout", id: null, reason: "id is missing." },
      { table: "nope", id: "w6", reason: "Unknown table." },
      { table: "workout", id: "w2", reason: "started_at is missing." },
      { table: "workout", id: "w3", reason: "title must be text." },
      { table: "workout", id: "w4", reason: "started_at must be a whole number." },
      { table: "workout", id: "w5", reason: "Unknown column nope." },
    ]);
  });

  it("clamps an updated_at from a clock far in the future to server time", async () => {
    await push(db, "ana", [{ table: "workout", row: workout("w1", now + 1000, { title: "Right" }) }], now + 1000);
    const far = now + CLOCK_SKEW_MS + 1;
    const result = await push(db, "ana", [{ table: "workout", row: workout("w1", far, { title: "Wrong clock", deleted_at: far }) }], now);
    expect(result.accepted).toEqual([{ table: "workout", id: "w1", updated_at: now }]);

    // Clamped to `now`, it's older than the row already there, so it loses.
    const [row] = await db.select().from(schema.workout);
    expect(row.title).toBe("Right");

    // A little ahead is allowed: phones are never exactly in step with the server.
    const near = now + CLOCK_SKEW_MS - 1;
    const ok = await push(db, "ana", [{ table: "workout", row: workout("w1", near, { title: "Slightly ahead" }) }], now);
    expect(ok.accepted[0].updated_at).toBe(near);
    expect((await db.select().from(schema.workout))[0].title).toBe("Slightly ahead");
  });

  it("gives every accepted write a new sequence number, so a pull after the cursor sees it", async () => {
    await push(db, "ana", [{ table: "workout", row: workout("w1", now) }], now);
    const first = await pull(db, "ana", 0);
    await push(db, "ana", [{ table: "workout", row: workout("w1", now + 1, { title: "Renamed" }) }], now + 1);
    const second = await pull(db, "ana", first.next);
    expect(second.rows.map((r) => r.row.title)).toEqual(["Renamed"]);
    expect(second.next).toBeGreaterThan(first.next);

    // A losing write changes nothing, so it doesn't move the cursor either.
    await push(db, "ana", [{ table: "workout", row: workout("w1", now, { title: "Old" }) }], now + 1);
    expect((await pull(db, "ana", second.next)).rows).toEqual([]);
  });
});

describe("pull", () => {
  it("pages in sequence order across tables and says when there's more", async () => {
    const changes = [];
    for (let i = 0; i < 7; i++) {
      changes.push({ table: "workout", row: workout(`w${i}`, now + i) });
      changes.push({ table: "routine", row: { id: `r${i}`, updated_at: now + i, deleted_at: null, name: `Day ${i}`, position: i } });
    }
    await push(db, "ana", changes, now + 10);

    const seen: string[] = [];
    let since = 0;
    let pages = 0;
    for (;;) {
      const page = await pull(db, "ana", since, 5);
      pages++;
      expect(page.rows.length).toBeLessThanOrEqual(5);
      for (let i = 1; i < page.rows.length; i++) expect(page.rows[i].seq).toBeGreaterThan(page.rows[i - 1].seq);
      seen.push(...page.rows.map((r) => r.row.id));
      since = page.next;
      if (!page.hasMore) break;
    }
    expect(pages).toBe(3);
    expect(seen).toHaveLength(14);
    expect(new Set(seen).size).toBe(14);
    // Parents (every workout) were written before children (every routine) within the push.
    expect(seen.slice(0, 7).every((id) => id.startsWith("w"))).toBe(true);
  });

  it("only returns the caller's rows", async () => {
    await push(db, "ana", [{ table: "workout", row: workout("w1", now) }], now);
    await push(db, "ben", [{ table: "workout", row: workout("w2", now) }], now);
    expect((await pull(db, "ana", 0)).rows.map((r) => r.row.id)).toEqual(["w1"]);
    expect((await pull(db, "ben", 0)).rows.map((r) => r.row.id)).toEqual(["w2"]);
  });

  it("returns nothing and keeps the cursor when there's nothing new", async () => {
    expect(await pull(db, "ana", 42)).toEqual({ rows: [], next: 42, hasMore: false });
  });
});

describe("account deletion", () => {
  it("removes every synced row with the user", async () => {
    await push(db, "ana", [
      { table: "workout", row: workout("w1", now) },
      { table: "workout_exercise", row: { id: "we1", updated_at: now, deleted_at: null, workout_id: "w1", exercise_brand_id: "eb1", position: 0, rest_seconds: 90 } },
      { table: "routine", row: { id: "r1", updated_at: now, deleted_at: null, name: "Push", position: 0 } },
    ], now);
    await push(db, "ben", [{ table: "workout", row: workout("w2", now) }], now);

    await db.delete(schema.user).where(sql`${schema.user.id} = 'ana'`);

    expect(await db.select().from(schema.workout)).toHaveLength(1);
    expect(await db.select().from(schema.workoutExercise)).toHaveLength(0);
    expect(await db.select().from(schema.routine)).toHaveLength(0);
    expect((await pull(db, "ben", 0)).rows.map((r) => r.row.id)).toEqual(["w2"]);
  });
});
