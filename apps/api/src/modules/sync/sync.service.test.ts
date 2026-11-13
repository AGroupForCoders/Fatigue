import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import type { Database } from "../../db/client";
import { setting, user, workout, workoutExercise, workoutSet } from "../../db/schema";
import { addUser, testDb } from "../../db/test-db";
import type { AnyItem, Item } from "./sync.items";
import { pull, push } from "./sync.service";

/** A UUID that is easy to read in a failure: `id(7)` ends in 7. */
function id(n: number) {
  return `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
}

const benchBrand = id(100);
const seat = id(200);

function aWorkout(n: number, updatedAt: number, change: Partial<NonNullable<Item<"workout">["body"]>> = {}): Item<"workout"> {
  return {
    kind: "workout",
    id: id(n),
    updatedAt,
    deletedAt: null,
    body: {
      title: "Push",
      note: null,
      startedAt: 1_700_000_000_000,
      finishedAt: 1_700_003_600_000,
      routineId: null,
      importKey: null,
      gymName: "City Gym",
      gymAddress: null,
      gymLatitude: null,
      gymLongitude: null,
      exercises: [
        {
          id: id(n * 10 + 1),
          brandId: benchBrand,
          restSeconds: 120,
          notes: [{ id: id(n * 10 + 2), text: "Felt heavy" }],
          settings: [{ settingId: seat, value: 4, textValue: null }],
          sets: [
            { id: id(n * 10 + 3), kind: "reps", setType: "warmup", weightKg: 40, reps: 10, durationSeconds: null, rpe: null, completedAt: 1_700_000_100_000, overrides: [] },
            { id: id(n * 10 + 4), kind: "reps", setType: "normal", weightKg: 80, reps: 8, durationSeconds: null, rpe: 8.5, completedAt: 1_700_000_300_000, overrides: [{ settingId: seat, value: 5 }] },
          ],
        },
      ],
      ...change,
    },
  };
}

function aBrand(n: number, updatedAt: number, settingIds: number[] = []): Item<"brand"> {
  return {
    kind: "brand",
    id: id(n),
    updatedAt,
    deletedAt: null,
    body: {
      exerciseId: id(1),
      brand: "Technogym",
      label: null,
      settings: settingIds.map((s, position) => ({
        id: id(s),
        name: `Setting ${s}`,
        kind: "number",
        value: 4,
        textValue: null,
        direction: null,
        rangeMin: null,
        rangeMax: null,
        splitByValue: false,
        everySet: position === 0,
        factor: null,
        position,
        deletedAt: null,
      })),
    },
  };
}

const now = 2_000_000_000_000;

async function signedUp(...ids: string[]) {
  const db = await testDb();
  for (const one of ids) await addUser(db, one);
  return db;
}

async function everything(db: Database, userId: string) {
  return (await pull(db, userId, 0, 1000)).items;
}

describe("sync push and pull", () => {
  it("gives a pushed workout back exactly", async () => {
    const db = await signedUp("anton");
    const item = aWorkout(1, 1000);

    expect(await push(db, "anton", 1, [item], now)).toEqual([{ kind: "workout", id: item.id, status: "saved" }]);
    const page = await pull(db, "anton", 0);
    expect(page.items).toEqual([item]);
    expect(page.cursor).toBe(1);
    expect(page.more).toBe(false);
  });

  it("gives every kind of item back exactly", async () => {
    const db = await signedUp("anton");
    const items: AnyItem[] = [
      { kind: "exercise", id: id(1), updatedAt: 1000, deletedAt: null, body: { name: "Sissy Squat", equipment: "bodyweight", muscles: [{ muscle: "glutes", share: 0.5 }, { muscle: "quadriceps", share: 1 }], measures: ["weight", "reps"] } },
      aBrand(2, 1000, [200, 201]),
      {
        kind: "routine",
        id: id(3),
        updatedAt: 1000,
        deletedAt: null,
        body: {
          name: "Leg day",
          position: 0,
          exercises: [
            {
              id: id(31),
              brandId: id(2),
              restSeconds: 90,
              notes: [],
              settings: [{ settingId: id(200), value: 4, textValue: null }],
              sets: [{ id: id(32), kind: "hold", setType: "normal", weightKg: null, reps: null, durationSeconds: 30, rpe: null, completedAt: null, overrides: [{ settingId: id(200), value: 8 }] }],
            },
          ],
        },
      },
      aWorkout(4, 1000),
      { kind: "user_setting", id: id(5), updatedAt: 1000, deletedAt: null, body: { weightUnit: "lb" } },
    ];

    expect((await push(db, "anton", 1, items, now)).map((r) => r.status)).toEqual(["saved", "saved", "saved", "saved", "saved"]);
    expect(await everything(db, "anton")).toEqual(items);
  });

  it("takes an exercise from a build before measures, and refuses measures that can't be", async () => {
    const db = await signedUp("anton");
    const exercise = (n: number, measures: unknown) => ({ kind: "exercise", id: id(n), updatedAt: 1000, deletedAt: null, body: { name: `Plank ${n}`, equipment: "bodyweight", muscles: [], measures } });
    const results = await push(db, "anton", 1, [
      exercise(1, undefined),
      exercise(2, ["time"]),
      exercise(3, ["reps", "time"]),
      exercise(4, ["weight"]),
      exercise(5, ["weight", "weight", "reps"]),
      exercise(6, ["speed"]),
    ]);
    expect(results.map((r) => r.status)).toEqual(["saved", "saved", "invalid", "invalid", "invalid", "invalid"]);
    const pulled = await pull(db, "anton", 0);
    expect(pulled.items.map((i) => (i.body as { measures: unknown }).measures)).toEqual([null, ["time"]]);
  });

  it("keeps the later edit when two phones changed the same workout", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [aWorkout(1, 2000, { title: "Edited on phone B" })], now);

    // Phone A was offline with an older edit and pushes it afterwards.
    const late = await push(db, "anton", 1, [aWorkout(1, 1500, { title: "Edited on phone A", exercises: [] })], now);

    expect(late[0]!.status).toBe("older");
    const [kept] = await everything(db, "anton");
    expect(kept!.kind === "workout" && kept!.body!.title).toBe("Edited on phone B");
    expect(kept!.kind === "workout" && kept!.body!.exercises).toHaveLength(1);
  });

  it("replaces the whole workout with a later edit, sets that were removed included", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [aWorkout(1, 1000)], now);
    const edited = aWorkout(1, 2000);
    edited.body!.exercises[0]!.sets.pop();
    edited.body!.exercises[0]!.notes = [];

    expect((await push(db, "anton", 1, [edited], now))[0]!.status).toBe("saved");
    expect(await everything(db, "anton")).toEqual([edited]);
    expect(await db.select().from(workoutSet)).toHaveLength(1);
  });

  it("changes nothing when the same push arrives twice", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [aWorkout(1, 1000)], now);

    expect((await push(db, "anton", 1, [aWorkout(1, 1000)], now))[0]!.status).toBe("older");
    expect((await pull(db, "anton", 0)).cursor).toBe(1);
  });

  it("pulls a time in the future back to the server's, so a wrong clock can't win forever", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [aWorkout(1, now + 86_400_000, { title: "From a phone a day ahead" })], now);

    const fixed = await push(db, "anton", 1, [aWorkout(1, now + 60_000, { title: "A minute later, right clock" })], now + 60_000);

    expect(fixed[0]!.status).toBe("saved");
    const [kept] = await everything(db, "anton");
    expect(kept!.updatedAt).toBe(now + 60_000);
    expect(kept!.kind === "workout" && kept!.body!.title).toBe("A minute later, right clock");
  });

  it("refuses an item from a build older than the one that last wrote it", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 2, [aWorkout(1, 1000, { title: "Written by the new build" })], now);

    const refused = await push(db, "anton", 1, [aWorkout(1, 2000, { title: "From the old build" }), aWorkout(2, 2000)], now);

    expect(refused.map((r) => r.status)).toEqual(["too_old", "saved"]);
    const items = await everything(db, "anton");
    expect(items.map((i) => i.kind === "workout" && i.body!.title)).toEqual(["Written by the new build", "Push"]);
  });

  it("saves the items around one that is malformed", async () => {
    const db = await signedUp("anton");
    const broken = { ...aWorkout(2, 1000), body: { ...aWorkout(2, 1000).body, exercises: [{ id: "not-a-uuid" }] } };
    const running = { ...aWorkout(3, 1000), body: { ...aWorkout(3, 1000).body, finishedAt: null } };
    const twins = aWorkout(4, 1000);
    twins.body!.exercises[0]!.sets[1]!.id = twins.body!.exercises[0]!.sets[0]!.id;

    const results = await push(db, "anton", 1, [aWorkout(1, 1000), broken, running, twins, "nonsense", aWorkout(5, 1000)], now);

    expect(results.map((r) => r.status)).toEqual(["saved", "invalid", "invalid", "invalid", "invalid", "saved"]);
    expect(results[1]).toMatchObject({ kind: "workout", id: id(2), message: "body.exercises[0].id must be a UUID" });
    expect(results[2]!.message).toMatch(/finished/);
    expect((await everything(db, "anton")).map((i) => i.id)).toEqual([id(1), id(5)]);
    // The item the database refused left nothing behind, and took no version.
    expect(await db.select().from(workout).where(eq(workout.id, id(4)))).toHaveLength(0);
    expect((await pull(db, "anton", 0)).cursor).toBe(2);
  });

  it("keeps two accounts apart, even with the same ID", async () => {
    const db = await signedUp("anton", "jos");
    await push(db, "anton", 1, [aWorkout(1, 1000, { title: "Anton's" })], now);
    await push(db, "jos", 1, [aWorkout(1, 5000, { title: "Jos's" })], now);

    const antons = await everything(db, "anton");
    const joss = await everything(db, "jos");
    expect(antons.map((i) => i.kind === "workout" && i.body!.title)).toEqual(["Anton's"]);
    expect(joss.map((i) => i.kind === "workout" && i.body!.title)).toEqual(["Jos's"]);
    expect(await db.select().from(workoutExercise)).toHaveLength(2);
  });

  it("stores IDs in lower case whatever case they arrive in", async () => {
    const db = await signedUp("anton");
    const shouting = JSON.parse(JSON.stringify(aWorkout(1, 1000)).replaceAll("00000000-0000-4000-8000", "ABCDEF00-0000-4000-8000"));

    await push(db, "anton", 1, [shouting], now);

    const [stored] = await everything(db, "anton");
    expect(stored!.id).toBe("abcdef00-0000-4000-8000-000000000001");
    expect(stored!.kind === "workout" && stored!.body!.exercises[0]!.brandId).toBe("abcdef00-0000-4000-8000-000000000100");
  });

  it("keeps a deleted workout's row and removes what was under it", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [aWorkout(1, 1000)], now);

    const gone = await push(db, "anton", 1, [{ kind: "workout", id: id(1), updatedAt: 2000, deletedAt: 2000, body: null }], now);

    expect(gone[0]!.status).toBe("saved");
    expect(await everything(db, "anton")).toEqual([{ kind: "workout", id: id(1), updatedAt: 2000, deletedAt: 2000, body: null }]);
    expect(await db.select().from(workoutExercise)).toHaveLength(0);
    expect(await db.select().from(workoutSet)).toHaveLength(0);
  });

  it("brings a deleted workout back when it was edited later on another phone", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [{ kind: "workout", id: id(1), updatedAt: 2000, deletedAt: 2000, body: null }], now);

    await push(db, "anton", 1, [aWorkout(1, 3000)], now);

    expect(await everything(db, "anton")).toEqual([aWorkout(1, 3000)]);
  });

  it("keeps a deleted brand's settings, because finished workouts still show them", async () => {
    const db = await signedUp("anton");
    const deleted = { ...aBrand(2, 2000, [200]), deletedAt: 2000 };

    await push(db, "anton", 1, [aBrand(2, 1000, [200]), deleted], now);

    expect(await everything(db, "anton")).toEqual([deleted]);
    expect(await db.select().from(setting)).toHaveLength(1);
  });

  it("moves a setting to the brand it was merged into, whichever brand arrives first", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [aBrand(2, 1000, [200, 201]), aBrand(3, 1000, [])], now);

    // Brand 2 was merged into brand 3. Brand 3 arrives first, while setting 201 is still under brand 2 here.
    const merged = await push(db, "anton", 1, [aBrand(3, 2000, [201]), { ...aBrand(2, 2000, [200]), deletedAt: 2000 }], now);

    expect(merged.map((r) => r.status)).toEqual(["saved", "saved"]);
    const rows = await db.select({ id: setting.id, brand: setting.exerciseBrandId }).from(setting).orderBy(setting.id);
    expect(rows).toEqual([
      { id: id(200), brand: id(2) },
      { id: id(201), brand: id(3) },
    ]);
  });

  it("pages through everything in the order it changed, without skipping", async () => {
    const db = await signedUp("anton");
    await push(db, "anton", 1, [aWorkout(1, 1000), aBrand(2, 1000), aWorkout(3, 1000), aBrand(4, 1000), aWorkout(5, 1000)], now);
    // An edit moves an item to the end.
    await push(db, "anton", 1, [aWorkout(1, 2000)], now);

    const seen: string[] = [];
    let cursor = 0;
    for (;;) {
      const page = await pull(db, "anton", cursor, 2);
      seen.push(...page.items.map((i) => i.id));
      cursor = page.cursor;
      if (!page.more) break;
      expect(page.items).toHaveLength(2);
    }

    expect(seen).toEqual([id(2), id(3), id(4), id(5), id(1)]);
    expect(cursor).toBe(6);
    expect(await pull(db, "anton", cursor)).toEqual({ items: [], cursor: 6, more: false });
  });

  it("removes everything when the account is deleted", async () => {
    const db = await signedUp("anton", "jos");
    await push(db, "anton", 1, [aBrand(2, 1000, [200]), aWorkout(1, 1000)], now);
    await push(db, "jos", 1, [aWorkout(1, 1000)], now);

    await db.delete(user).where(eq(user.id, "anton"));

    for (const table of ["sync_account", "exercise_brand", "setting", "workout", "workout_exercise", "workout_exercise_note", "workout_exercise_setting", "workout_set", "workout_set_override"]) {
      const left = (await db.execute(sql`select user_id from ${sql.identifier(table)}`)) as unknown as { rows: { user_id: string }[] };
      expect(left.rows.map((row) => row.user_id), table).toEqual(table === "exercise_brand" || table === "setting" ? [] : table === "workout_set" ? ["jos", "jos"] : ["jos"]);
    }
  });
});
