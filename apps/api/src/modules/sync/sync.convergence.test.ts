import { sql } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createUser, testApp, testDb, type TestDb } from "../../lib/testing";
import { syncRoutes } from "./sync.routes";
import { SYNC_SCHEMA_VERSION, type SyncRow } from "./sync.service";

/**
 * Two phones on one account, each following the client's rules, with a seeded random mix of edits,
 * deletions, time offline and syncs, against the real push and pull handlers. Whatever the
 * interleaving, both must end up with the same rows as each other and as the server.
 *
 * The client rules mirrored here are the ones the iOS SyncEngine implements:
 * - every local write bumps `updated_at` past the row's previous value and marks the row in the outbox;
 * - push sends the outbox rows, and an acknowledged row leaves the outbox only if its `updated_at`
 *   is still the one that was sent;
 * - pull applies a row unless the local copy is dirty and newer; a tie goes to the server;
 * - an applied row leaves the outbox.
 */

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

/** mulberry32: a small seeded generator, so a failing run can be replayed. */
function random(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

type Key = `${string}/${string}`;

class Device {
  rows = new Map<Key, SyncRow>();
  /** Dirty rows, with the updated_at they had when they were last marked. */
  outbox = new Map<Key, number>();
  cursor = 0;
  syncs = 0;

  constructor(
    readonly name: string,
    private readonly clock: () => number,
  ) {}

  private key(table: string, id: string): Key {
    return `${table}/${id}`;
  }

  write(table: string, row: Omit<SyncRow, "updated_at">) {
    // Strictly later than the last version of this row, even if the clock hasn't moved: a second save
    // in the same millisecond would otherwise tie with the server's copy and be dropped.
    const previous = this.rows.get(this.key(table, row.id as string))?.updated_at ?? 0;
    const stamped = { ...row, updated_at: Math.max(this.clock(), previous + 1) } as SyncRow;
    this.rows.set(this.key(table, stamped.id), stamped);
    this.outbox.set(this.key(table, stamped.id), stamped.updated_at);
  }

  delete(table: string, id: string) {
    const row = this.rows.get(this.key(table, id));
    if (!row || row.deleted_at !== null) return;
    this.write(table, { ...row, deleted_at: this.clock() });
  }

  live(table: string) {
    return [...this.rows.entries()].filter(([k, r]) => k.startsWith(`${table}/`) && r.deleted_at === null).map(([, r]) => r);
  }

  async sync() {
    this.syncs++;
    // Push what changed, remembering exactly what was sent.
    const sent = [...this.outbox.keys()].map((key) => ({ key, row: { ...this.rows.get(key)! } }));
    if (sent.length > 0) {
      const res = await app.request("/api/sync/push", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Test-User": "ana" },
        body: JSON.stringify({
          schemaVersion: SYNC_SCHEMA_VERSION,
          changes: sent.map(({ key, row }) => ({ table: key.split("/")[0], row })),
        }),
      });
      expect(res.status).toBe(200);
      const body = (await res.json()) as { accepted: { table: string; id: string; updated_at: number }[]; rejected: unknown[] };
      expect(body.rejected).toEqual([]);
      for (const { key, row } of sent) {
        const ack = body.accepted.find((a) => this.key(a.table, a.id) === key);
        expect(ack).toBeDefined();
        const local = this.rows.get(key)!;
        // Edited again while the push was in flight? Then it stays dirty.
        if (local.updated_at !== row.updated_at) continue;
        if (ack!.updated_at !== row.updated_at) this.rows.set(key, { ...local, updated_at: ack!.updated_at });
        this.outbox.delete(key);
      }
    }
    // Pull everything since the cursor, a page at a time.
    for (;;) {
      const res = await app.request(`/api/sync/pull?since=${this.cursor}&limit=7&schemaVersion=${SYNC_SCHEMA_VERSION}`, {
        headers: { "X-Test-User": "ana" },
      });
      expect(res.status).toBe(200);
      const page = (await res.json()) as { rows: { table: string; row: SyncRow }[]; next: number; hasMore: boolean };
      for (const { table, row } of page.rows) {
        const key = this.key(table, row.id);
        const local = this.rows.get(key);
        if (local && this.outbox.has(key) && local.updated_at > row.updated_at) continue;
        this.rows.set(key, row);
        this.outbox.delete(key);
      }
      this.cursor = page.next;
      if (!page.hasMore) break;
    }
  }
}

function snapshot(device: Device) {
  return [...device.rows.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([key, row]) => [key, row.updated_at, row.deleted_at, row.title ?? row.name, row.position ?? null]);
}

async function serverSnapshot() {
  const fresh = new Device("server", () => 0);
  await fresh.sync();
  return snapshot(fresh);
}

async function run(seed: number, steps: number) {
  const rng = random(seed);
  // A coarse shared clock, so two phones often stamp the same millisecond and ties get exercised.
  let time = 1_000;
  const clock = () => (time += Math.floor(rng() * 3));
  const devices = [new Device("A", clock), new Device("B", clock)];
  let nextId = 0;

  for (let step = 0; step < steps; step++) {
    const device = devices[Math.floor(rng() * 2)];
    const roll = rng();
    if (roll < 0.25) {
      const id = `w${nextId++}`;
      device.write("workout", { id, deleted_at: null, title: `${device.name} ${step}`, note: null, started_at: 1, finished_at: 2, routine_id: null });
      device.write("workout_exercise", { id: `${id}e`, deleted_at: null, workout_id: id, exercise_brand_id: "eb", position: 0, rest_seconds: 90 });
    } else if (roll < 0.55) {
      const live = device.live("workout");
      if (live.length > 0) {
        const row = live[Math.floor(rng() * live.length)];
        device.write("workout", { ...row, title: `${device.name} edit ${step}` });
      }
    } else if (roll < 0.65) {
      const live = device.live("workout");
      if (live.length > 0) device.delete("workout", live[Math.floor(rng() * live.length)].id);
    } else if (roll < 0.75) {
      device.write("routine", { id: `r${nextId++}`, deleted_at: null, name: `Day ${step}`, position: step });
    } else {
      // The other cases are time offline: this device just doesn't sync.
      await device.sync();
    }
  }

  // Back online: twice each, so a change pushed by the second phone reaches the first.
  for (const device of [...devices, ...devices]) await device.sync();

  const [a, b] = devices.map(snapshot);
  expect(a, `seed ${seed}: devices differ`).toEqual(b);
  expect(a, `seed ${seed}: devices differ from the server`).toEqual(await serverSnapshot());
  expect(devices.every((d) => d.outbox.size === 0), `seed ${seed}: outbox not drained`).toBe(true);
  return a;
}

describe("two devices converge", () => {
  it("after a random mix of edits, deletes, time offline and syncs", async () => {
    for (let seed = 1; seed <= 30; seed++) {
      const final = await run(seed, 80);
      expect(final.length).toBeGreaterThan(0);
      await db.execute(sql`truncate "user" cascade`);
      await createUser(db, "ana");
    }
  }, 60_000);

  it("keeps the later edit when both phones changed the same workout offline", async () => {
    let time = 1_000;
    const clock = () => ++time;
    const a = new Device("A", clock);
    const b = new Device("B", clock);
    a.write("workout", { id: "w", deleted_at: null, title: "Legs", note: null, started_at: 1, finished_at: 2, routine_id: null });
    await a.sync();
    await b.sync();

    b.write("workout", { ...b.rows.get("workout/w")!, title: "B's edit" });
    a.write("workout", { ...a.rows.get("workout/w")!, title: "A's later edit" });
    await b.sync();
    await a.sync();
    await b.sync();

    expect(a.rows.get("workout/w")!.title).toBe("A's later edit");
    expect(b.rows.get("workout/w")!.title).toBe("A's later edit");
    expect(snapshot(a)).toEqual(await serverSnapshot());
  });

  it("a row edited while its push was in flight stays in the outbox", async () => {
    let time = 1_000;
    const a = new Device("A", () => ++time);
    a.write("routine", { id: "r", deleted_at: null, name: "Push", position: 0 });
    // Simulate the edit landing between sending and acknowledging: bump it before the ack is processed.
    const sentAt = a.rows.get("routine/r")!.updated_at;
    const pushing = a.sync();
    a.write("routine", { ...a.rows.get("routine/r")!, name: "Push, edited" });
    await pushing;
    expect(a.rows.get("routine/r")!.updated_at).toBeGreaterThan(sentAt);
    expect(a.outbox.has("routine/r")).toBe(true);
    await a.sync();
    expect(a.outbox.size).toBe(0);
    expect((await serverSnapshot()).find(([key]) => key === "routine/r")![3]).toBe("Push, edited");
  });
});
