import { and, asc, eq, gt, inArray } from "drizzle-orm";
import type { Database } from "../../db/client";
import * as t from "../../db/schema";
import { InvalidItem, kinds, parseItem, type AnyItem, type Bodies, type BrandSetting, type Item, type ItemExercise, type Kind } from "./sync.items";

/** The most items one push or one page of a pull carries. */
export const pageSize = 100;

/**
 * What happened to one pushed item.
 * - `saved`: the server took it.
 * - `older`: the server already has this edit or a later one. The phone gets the server's copy on its next pull.
 * - `too_old`: a newer build wrote the item last, and this build could lose what it doesn't know about.
 * - `invalid`: the item is malformed. `message` says where.
 *
 * The phone drops `saved` and `older` items from its outbox and keeps the other two.
 */
export type PushResult = { kind: string | null; id: string | null; status: "saved" | "older" | "too_old" | "invalid"; message?: string };

/** The columns every top row carries for sync. */
type Sync = { updatedAt: number; deletedAt: number | null; version: number; schema: number };

const tops = { exercise: t.exercise, brand: t.exerciseBrand, routine: t.routine, workout: t.workout, user_setting: t.userSetting } as const;

/** A kind's top table, typed as the smallest one. They all have `userId`, `id` and the sync columns, which is all this is used for. */
function top(kind: Kind) {
  return tops[kind] as unknown as typeof t.userSetting;
}

/**
 * Takes a phone's changed items. The later `updatedAt` wins for the whole item.
 *
 * Everything runs in one transaction that first locks the account's counter, so two phones pushing at
 * once take turns. Without that, the later version number could commit first, a pull in between would
 * move its cursor past the earlier one, and that item would never be pulled.
 *
 * @param schema The schema of the build that is pushing.
 * @param now The server's time. An `updatedAt` after it is pulled back to it, so a phone with a wrong
 *   clock can't win every conflict from then on.
 */
export async function push(db: Database, userId: string, schema: number, rawItems: unknown[], now = Date.now()): Promise<PushResult[]> {
  return db.transaction(async (tx) => {
    await tx.insert(t.syncAccount).values({ userId }).onConflictDoNothing();
    const [counter] = await tx.select({ version: t.syncAccount.version }).from(t.syncAccount).where(eq(t.syncAccount.userId, userId)).for("update");
    let version = counter!.version;

    const results: PushResult[] = [];
    for (const raw of rawItems) {
      let item: AnyItem;
      try {
        item = parseItem(raw);
      } catch (error) {
        if (!(error instanceof InvalidItem)) throw error;
        results.push({ ...named(raw), status: "invalid", message: error.message });
        continue;
      }
      const name = { kind: item.kind, id: item.id };
      item.updatedAt = Math.min(item.updatedAt, now);
      if (item.deletedAt !== null) item.deletedAt = Math.min(item.deletedAt, now);

      const table = top(item.kind);
      const [existing] = await tx
        .select({ updatedAt: table.updatedAt, schema: table.schema })
        .from(table)
        .where(and(eq(table.userId, userId), eq(table.id, item.id)));
      if (existing && existing.schema > schema) {
        results.push({ ...name, status: "too_old", message: "Update the app to change this." });
        continue;
      }
      // An equal time is the same push arriving twice, which must change nothing.
      if (existing && existing.updatedAt >= item.updatedAt) {
        results.push({ ...name, status: "older" });
        continue;
      }

      try {
        // In a savepoint, so an item the database refuses (two sets with one ID, say) is undone on its own
        // and the items around it still go in.
        await tx.transaction((savepoint) => write(savepoint, userId, item, { updatedAt: item.updatedAt, deletedAt: item.deletedAt, version: version + 1, schema }));
      } catch {
        results.push({ ...name, status: "invalid", message: "The server could not save this item." });
        continue;
      }
      version += 1;
      results.push({ ...name, status: "saved" });
    }

    await tx.update(t.syncAccount).set({ version }).where(eq(t.syncAccount.userId, userId));
    return results;
  });
}

/** The kind and ID of an item that failed its checks, when it has them, so the phone can tell which one it was. */
function named(raw: unknown): { kind: string | null; id: string | null } {
  const o = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  return { kind: typeof o.kind === "string" ? o.kind : null, id: typeof o.id === "string" ? o.id.toLowerCase() : null };
}

// Writing an item: the top row is added or replaced, then the rows under it are replaced.

function write(db: Database, userId: string, item: AnyItem, sync: Sync) {
  switch (item.kind) {
    case "exercise":
      return writeExercise(db, userId, item, sync);
    case "brand":
      return writeBrand(db, userId, item, sync);
    case "routine":
      return writeRoutine(db, userId, item, sync);
    case "workout":
      return writeWorkout(db, userId, item, sync);
    case "user_setting":
      return writeUserSetting(db, userId, item, sync);
  }
}

async function writeExercise(db: Database, userId: string, item: Item<"exercise">, sync: Sync) {
  const body = item.body!;
  const row = { name: body.name, equipment: body.equipment, ...sync };
  await db
    .insert(t.exercise)
    .values({ userId, id: item.id, ...row })
    .onConflictDoUpdate({ target: [t.exercise.userId, t.exercise.id], set: row });
  await db.delete(t.exerciseMuscle).where(and(eq(t.exerciseMuscle.userId, userId), eq(t.exerciseMuscle.exerciseId, item.id)));
  if (body.muscles.length) await db.insert(t.exerciseMuscle).values(body.muscles.map((m) => ({ userId, exerciseId: item.id, ...m })));
}

async function writeBrand(db: Database, userId: string, item: Item<"brand">, sync: Sync) {
  const body = item.body!;
  const row = { exerciseId: body.exerciseId, brand: body.brand, label: body.label, ...sync };
  await db
    .insert(t.exerciseBrand)
    .values({ userId, id: item.id, ...row })
    .onConflictDoUpdate({ target: [t.exerciseBrand.userId, t.exerciseBrand.id], set: row });
  await db.delete(t.setting).where(and(eq(t.setting.userId, userId), eq(t.setting.exerciseBrandId, item.id)));
  if (!body.settings.length) return;
  // Merging two brands moves a setting from one to the other. If the brand it moved to arrives first,
  // the setting is still under the old one here, so it is taken from wherever it is.
  await db.delete(t.setting).where(and(eq(t.setting.userId, userId), inArray(t.setting.id, body.settings.map((s) => s.id))));
  await db.insert(t.setting).values(body.settings.map((s) => ({ userId, exerciseBrandId: item.id, ...s })));
}

async function writeUserSetting(db: Database, userId: string, item: Item<"user_setting">, sync: Sync) {
  const row = { weightUnit: item.body!.weightUnit, ...sync };
  await db
    .insert(t.userSetting)
    .values({ userId, id: item.id, ...row })
    .onConflictDoUpdate({ target: [t.userSetting.userId, t.userSetting.id], set: row });
}

async function writeRoutine(db: Database, userId: string, item: Item<"routine">, sync: Sync) {
  await db.delete(t.routineExercise).where(and(eq(t.routineExercise.userId, userId), eq(t.routineExercise.routineId, item.id)));
  const body = item.body;
  if (!body) {
    // Deleted. The row stays so other phones learn of it. One that was never pushed alive gets an empty row.
    await db
      .insert(t.routine)
      .values({ userId, id: item.id, name: "", position: 0, ...sync })
      .onConflictDoUpdate({ target: [t.routine.userId, t.routine.id], set: sync });
    return;
  }
  const row = { name: body.name, position: body.position, ...sync };
  await db
    .insert(t.routine)
    .values({ userId, id: item.id, ...row })
    .onConflictDoUpdate({ target: [t.routine.userId, t.routine.id], set: row });

  const exercises = body.exercises;
  if (!exercises.length) return;
  await db.delete(t.routineExercise).where(and(eq(t.routineExercise.userId, userId), inArray(t.routineExercise.id, exercises.map((e) => e.id))));
  await db.insert(t.routineExercise).values(
    exercises.map((e, position) => ({ userId, id: e.id, routineId: item.id, exerciseBrandId: e.brandId, position, restSeconds: e.restSeconds })),
  );
  const values = exercises.flatMap((e) => e.settings.map((s) => ({ userId, routineExerciseId: e.id, ...s })));
  if (values.length) await db.insert(t.routineExerciseSetting).values(values);
  const sets = exercises.flatMap((e) => e.sets.map((s, position) => ({ exercise: e.id, position, set: s })));
  if (!sets.length) return;
  await db.delete(t.routineSet).where(and(eq(t.routineSet.userId, userId), inArray(t.routineSet.id, sets.map((s) => s.set.id))));
  await db.insert(t.routineSet).values(
    sets.map(({ exercise, position, set }) => ({
      userId,
      id: set.id,
      routineExerciseId: exercise,
      position,
      kind: set.kind,
      setType: set.setType,
      weightKg: set.weightKg,
      reps: set.reps,
      durationSeconds: set.durationSeconds,
    })),
  );
  const overrides = sets.flatMap(({ set }) => set.overrides.map((o) => ({ userId, routineSetId: set.id, ...o })));
  if (overrides.length) await db.insert(t.routineSetOverride).values(overrides);
}

async function writeWorkout(db: Database, userId: string, item: Item<"workout">, sync: Sync) {
  await db.delete(t.workoutExercise).where(and(eq(t.workoutExercise.userId, userId), eq(t.workoutExercise.workoutId, item.id)));
  const body = item.body;
  if (!body) {
    // Deleted. The row stays so other phones learn of it. One that was never pushed alive gets an empty row.
    await db
      .insert(t.workout)
      .values({ userId, id: item.id, title: "", startedAt: 0, finishedAt: 0, ...sync })
      .onConflictDoUpdate({ target: [t.workout.userId, t.workout.id], set: sync });
    return;
  }
  const { exercises, ...columns } = body;
  const row = { ...columns, ...sync };
  await db
    .insert(t.workout)
    .values({ userId, id: item.id, ...row })
    .onConflictDoUpdate({ target: [t.workout.userId, t.workout.id], set: row });

  if (!exercises.length) return;
  await db.delete(t.workoutExercise).where(and(eq(t.workoutExercise.userId, userId), inArray(t.workoutExercise.id, exercises.map((e) => e.id))));
  await db.insert(t.workoutExercise).values(
    exercises.map((e, position) => ({ userId, id: e.id, workoutId: item.id, exerciseBrandId: e.brandId, position, restSeconds: e.restSeconds })),
  );
  const notes = exercises.flatMap((e) => e.notes.map((n, position) => ({ userId, id: n.id, workoutExerciseId: e.id, position, text: n.text })));
  if (notes.length) {
    await db.delete(t.workoutExerciseNote).where(and(eq(t.workoutExerciseNote.userId, userId), inArray(t.workoutExerciseNote.id, notes.map((n) => n.id))));
    await db.insert(t.workoutExerciseNote).values(notes);
  }
  const values = exercises.flatMap((e) => e.settings.map((s) => ({ userId, workoutExerciseId: e.id, ...s })));
  if (values.length) await db.insert(t.workoutExerciseSetting).values(values);
  const sets = exercises.flatMap((e) => e.sets.map((s, position) => ({ exercise: e.id, position, set: s })));
  if (!sets.length) return;
  await db.delete(t.workoutSet).where(and(eq(t.workoutSet.userId, userId), inArray(t.workoutSet.id, sets.map((s) => s.set.id))));
  await db.insert(t.workoutSet).values(
    sets.map(({ exercise, position, set }) => ({
      userId,
      id: set.id,
      workoutExerciseId: exercise,
      position,
      kind: set.kind,
      setType: set.setType,
      weightKg: set.weightKg,
      reps: set.reps,
      durationSeconds: set.durationSeconds,
      rpe: set.rpe,
      completedAt: set.completedAt,
    })),
  );
  const overrides = sets.flatMap(({ set }) => set.overrides.map((o) => ({ userId, workoutSetId: set.id, ...o })));
  if (overrides.length) await db.insert(t.workoutSetOverride).values(overrides);
}

// Reading items back.

export type Page = {
  items: AnyItem[];
  /** What to send as `cursor` next time. */
  cursor: number;
  /** Whether there is more above this page. */
  more: boolean;
};

/**
 * The account's items changed since `cursor`, oldest change first.
 *
 * It reads from one snapshot of the database. Read query by query, a push landing in between could show
 * its later item and hide its earlier one, and the cursor would move past the hidden one for good.
 */
export async function pull(db: Database, userId: string, cursor: number, limit = pageSize): Promise<Page> {
  return db.transaction(
    async (tx) => {
      const changed: { kind: Kind; id: string; version: number; updatedAt: number; deletedAt: number | null }[] = [];
      for (const kind of kinds) {
        const table = top(kind);
        const rows = await tx
          .select({ id: table.id, version: table.version, updatedAt: table.updatedAt, deletedAt: table.deletedAt })
          .from(table)
          .where(and(eq(table.userId, userId), gt(table.version, cursor)))
          .orderBy(asc(table.version))
          .limit(limit + 1);
        changed.push(...rows.map((row) => ({ kind, ...row })));
      }
      // Versions come from one counter for the account, so they order items of every kind together.
      changed.sort((a, b) => a.version - b.version);
      const page = changed.slice(0, limit);

      const bodies = new Map<string, unknown>();
      for (const kind of kinds) {
        const ids = page.filter((row) => row.kind === kind).map((row) => row.id);
        if (!ids.length) continue;
        for (const [id, body] of await readers[kind](tx, userId, ids)) bodies.set(`${kind}:${id}`, body);
      }
      const items = page.map((row) => {
        const bodiless = row.deletedAt !== null && (row.kind === "routine" || row.kind === "workout");
        return { kind: row.kind, id: row.id, updatedAt: row.updatedAt, deletedAt: row.deletedAt, body: bodiless ? null : bodies.get(`${row.kind}:${row.id}`) } as AnyItem;
      });
      return { items, cursor: page.at(-1)?.version ?? cursor, more: changed.length > limit };
    },
    { isolationLevel: "repeatable read", accessMode: "read only" },
  );
}

function grouped<T>(rows: T[], key: (row: T) => string): Map<string, T[]> {
  const groups = new Map<string, T[]>();
  for (const row of rows) {
    const group = groups.get(key(row));
    if (group) group.push(row);
    else groups.set(key(row), [row]);
  }
  return groups;
}

const readers: { [K in Kind]: (db: Database, userId: string, ids: string[]) => Promise<Map<string, Bodies[K]>> } = {
  async exercise(db, userId, ids) {
    const rows = await db.select().from(t.exercise).where(and(eq(t.exercise.userId, userId), inArray(t.exercise.id, ids)));
    const muscles = grouped(
      await db
        .select()
        .from(t.exerciseMuscle)
        .where(and(eq(t.exerciseMuscle.userId, userId), inArray(t.exerciseMuscle.exerciseId, ids)))
        .orderBy(asc(t.exerciseMuscle.muscle)),
      (m) => m.exerciseId,
    );
    return new Map(
      rows.map((row) => [row.id, { name: row.name, equipment: row.equipment, muscles: (muscles.get(row.id) ?? []).map((m) => ({ muscle: m.muscle, share: m.share })) }]),
    );
  },

  async brand(db, userId, ids) {
    const rows = await db.select().from(t.exerciseBrand).where(and(eq(t.exerciseBrand.userId, userId), inArray(t.exerciseBrand.id, ids)));
    const settings = grouped(
      await db
        .select()
        .from(t.setting)
        .where(and(eq(t.setting.userId, userId), inArray(t.setting.exerciseBrandId, ids)))
        .orderBy(asc(t.setting.position), asc(t.setting.id)),
      (s) => s.exerciseBrandId,
    );
    return new Map(
      rows.map((row) => [
        row.id,
        {
          exerciseId: row.exerciseId,
          brand: row.brand,
          label: row.label,
          settings: (settings.get(row.id) ?? []).map(({ userId: _user, exerciseBrandId: _brand, ...setting }): BrandSetting => setting),
        },
      ]),
    );
  },

  async user_setting(db, userId, ids) {
    const rows = await db.select().from(t.userSetting).where(and(eq(t.userSetting.userId, userId), inArray(t.userSetting.id, ids)));
    return new Map(rows.map((row) => [row.id, { weightUnit: row.weightUnit }]));
  },

  async routine(db, userId, ids) {
    const rows = await db.select().from(t.routine).where(and(eq(t.routine.userId, userId), inArray(t.routine.id, ids)));
    const exercises = await db
      .select()
      .from(t.routineExercise)
      .where(and(eq(t.routineExercise.userId, userId), inArray(t.routineExercise.routineId, ids)))
      .orderBy(asc(t.routineExercise.position));
    const exerciseIds = exercises.map((e) => e.id);
    const values = exerciseIds.length
      ? await db
          .select()
          .from(t.routineExerciseSetting)
          .where(and(eq(t.routineExerciseSetting.userId, userId), inArray(t.routineExerciseSetting.routineExerciseId, exerciseIds)))
          .orderBy(asc(t.routineExerciseSetting.settingId))
      : [];
    const sets = exerciseIds.length
      ? await db
          .select()
          .from(t.routineSet)
          .where(and(eq(t.routineSet.userId, userId), inArray(t.routineSet.routineExerciseId, exerciseIds)))
          .orderBy(asc(t.routineSet.position))
      : [];
    const overrides = sets.length
      ? await db
          .select()
          .from(t.routineSetOverride)
          .where(and(eq(t.routineSetOverride.userId, userId), inArray(t.routineSetOverride.routineSetId, sets.map((s) => s.id))))
          .orderBy(asc(t.routineSetOverride.settingId))
      : [];
    const tree = exerciseTree(
      exercises.map((e) => ({ ...e, parentId: e.routineId })),
      [],
      values.map((v) => ({ ...v, exerciseId: v.routineExerciseId })),
      sets.map((s) => ({ ...s, exerciseId: s.routineExerciseId, rpe: null, completedAt: null })),
      overrides.map((o) => ({ ...o, setId: o.routineSetId })),
    );
    return new Map(rows.map((row) => [row.id, { name: row.name, position: row.position, exercises: tree.get(row.id) ?? [] }]));
  },

  async workout(db, userId, ids) {
    const rows = await db.select().from(t.workout).where(and(eq(t.workout.userId, userId), inArray(t.workout.id, ids)));
    const exercises = await db
      .select()
      .from(t.workoutExercise)
      .where(and(eq(t.workoutExercise.userId, userId), inArray(t.workoutExercise.workoutId, ids)))
      .orderBy(asc(t.workoutExercise.position));
    const exerciseIds = exercises.map((e) => e.id);
    const notes = exerciseIds.length
      ? await db
          .select()
          .from(t.workoutExerciseNote)
          .where(and(eq(t.workoutExerciseNote.userId, userId), inArray(t.workoutExerciseNote.workoutExerciseId, exerciseIds)))
          .orderBy(asc(t.workoutExerciseNote.position))
      : [];
    const values = exerciseIds.length
      ? await db
          .select()
          .from(t.workoutExerciseSetting)
          .where(and(eq(t.workoutExerciseSetting.userId, userId), inArray(t.workoutExerciseSetting.workoutExerciseId, exerciseIds)))
          .orderBy(asc(t.workoutExerciseSetting.settingId))
      : [];
    const sets = exerciseIds.length
      ? await db
          .select()
          .from(t.workoutSet)
          .where(and(eq(t.workoutSet.userId, userId), inArray(t.workoutSet.workoutExerciseId, exerciseIds)))
          .orderBy(asc(t.workoutSet.position))
      : [];
    const overrides = sets.length
      ? await db
          .select()
          .from(t.workoutSetOverride)
          .where(and(eq(t.workoutSetOverride.userId, userId), inArray(t.workoutSetOverride.workoutSetId, sets.map((s) => s.id))))
          .orderBy(asc(t.workoutSetOverride.settingId))
      : [];
    const tree = exerciseTree(
      exercises.map((e) => ({ ...e, parentId: e.workoutId })),
      notes.map((n) => ({ ...n, exerciseId: n.workoutExerciseId })),
      values.map((v) => ({ ...v, exerciseId: v.workoutExerciseId })),
      sets.map((s) => ({ ...s, exerciseId: s.workoutExerciseId })),
      overrides.map((o) => ({ ...o, setId: o.workoutSetId })),
    );
    return new Map(
      rows.map((row) => [
        row.id,
        {
          title: row.title,
          note: row.note,
          startedAt: row.startedAt,
          finishedAt: row.finishedAt,
          routineId: row.routineId,
          importKey: row.importKey,
          gymName: row.gymName,
          gymAddress: row.gymAddress,
          gymLatitude: row.gymLatitude,
          gymLongitude: row.gymLongitude,
          exercises: tree.get(row.id) ?? [],
        },
      ]),
    );
  },
};

type SetRow = Omit<ItemExercise["sets"][number], "overrides"> & { exerciseId: string };

/** Puts the rows of a routine or a workout back into exercises, keyed by the routine or workout they belong to. Rows arrive in position order. */
function exerciseTree(
  exercises: { id: string; parentId: string; exerciseBrandId: string; restSeconds: number }[],
  notes: { id: string; exerciseId: string; text: string }[],
  values: { exerciseId: string; settingId: string; value: number | null; textValue: string | null }[],
  sets: SetRow[],
  overrides: { setId: string; settingId: string; value: number }[],
): Map<string, ItemExercise[]> {
  const notesBy = grouped(notes, (n) => n.exerciseId);
  const valuesBy = grouped(values, (v) => v.exerciseId);
  const setsBy = grouped(sets, (s) => s.exerciseId);
  const overridesBy = grouped(overrides, (o) => o.setId);
  const tree = new Map<string, ItemExercise[]>();
  for (const exercise of exercises) {
    const built: ItemExercise = {
      id: exercise.id,
      brandId: exercise.exerciseBrandId,
      restSeconds: exercise.restSeconds,
      notes: (notesBy.get(exercise.id) ?? []).map((n) => ({ id: n.id, text: n.text })),
      settings: (valuesBy.get(exercise.id) ?? []).map((v) => ({ settingId: v.settingId, value: v.value, textValue: v.textValue })),
      sets: (setsBy.get(exercise.id) ?? []).map((s) => ({
        id: s.id,
        kind: s.kind,
        setType: s.setType,
        weightKg: s.weightKg,
        reps: s.reps,
        durationSeconds: s.durationSeconds,
        rpe: s.rpe,
        completedAt: s.completedAt,
        overrides: (overridesBy.get(s.id) ?? []).map((o) => ({ settingId: o.settingId, value: o.value })),
      })),
    };
    const siblings = tree.get(exercise.parentId);
    if (siblings) siblings.push(built);
    else tree.set(exercise.parentId, [built]);
  }
  return tree;
}
