import { sql } from "drizzle-orm";
import { bigint, doublePrecision, index, integer, pgSequence, pgTable, text, uniqueIndex } from "drizzle-orm/pg-core";
import type { PgColumnBuilderBase } from "drizzle-orm/pg-core";
import { user } from "./auth";

/**
 * The server's copy of every table the phone syncs. Columns mirror the SQLite tables in the iOS app
 * (apps/ios/Fatigue/Persistence/AppDatabase.swift), so a row can be pushed and pulled as it is.
 *
 * On top of the phone's columns every row has:
 * - `user_id`: who owns it, stamped from the session. Deleting the user cascades to every row.
 * - `server_seq`: the sync cursor. Taken from one sequence on every accepted write, so a device asking
 *   for "everything after N" gets each change exactly once, in the order the server accepted them.
 *
 * There are no foreign keys between synced tables. The phone enforces integrity; the server keeps rows
 * as they arrive, so a push that spans pages or arrives out of order never fails on a missing parent.
 */
export const syncSeq = pgSequence("sync_seq", { startWith: 1 });

function synced<T extends Record<string, PgColumnBuilderBase>>(name: string, columns: T) {
  return pgTable(
    name,
    {
      id: text("id").primaryKey(),
      userId: text("user_id")
        .notNull()
        .references(() => user.id, { onDelete: "cascade" }),
      updatedAt: bigint("updated_at", { mode: "number" }).notNull(),
      deletedAt: bigint("deleted_at", { mode: "number" }),
      serverSeq: bigint("server_seq", { mode: "number" })
        .notNull()
        .default(sql`nextval('sync_seq')`),
      ...columns,
    },
    (table) => [
      index(`${name}_user_seq_idx`).on(table.userId, table.serverSeq),
      uniqueIndex(`${name}_seq_idx`).on(table.serverSeq),
    ],
  );
}

export const exercise = synced("exercise", {
  name: text("name").notNull(),
  equipment: text("equipment").notNull(),
  isBuiltin: integer("is_builtin").notNull(),
});

export const exerciseMuscle = synced("exercise_muscle", {
  exerciseId: text("exercise_id").notNull(),
  muscle: text("muscle").notNull(),
  share: doublePrecision("share").notNull(),
});

export const exerciseBrand = synced("exercise_brand", {
  exerciseId: text("exercise_id").notNull(),
  brand: text("brand"),
  label: text("label"),
});

export const setting = synced("setting", {
  exerciseBrandId: text("exercise_brand_id").notNull(),
  name: text("name").notNull(),
  kind: text("kind").notNull(),
  value: doublePrecision("value"),
  textValue: text("text_value"),
  direction: text("direction"),
  rangeMin: doublePrecision("range_min"),
  rangeMax: doublePrecision("range_max"),
  splitByValue: integer("split_by_value").notNull(),
  factor: doublePrecision("factor"),
  position: doublePrecision("position").notNull(),
});

export const workout = synced("workout", {
  title: text("title").notNull(),
  note: text("note"),
  startedAt: bigint("started_at", { mode: "number" }).notNull(),
  finishedAt: bigint("finished_at", { mode: "number" }),
  routineId: text("routine_id"),
});

export const workoutExercise = synced("workout_exercise", {
  workoutId: text("workout_id").notNull(),
  exerciseBrandId: text("exercise_brand_id").notNull(),
  position: doublePrecision("position").notNull(),
  restSeconds: integer("rest_seconds").notNull(),
});

export const workoutExerciseNote = synced("workout_exercise_note", {
  workoutExerciseId: text("workout_exercise_id").notNull(),
  position: doublePrecision("position").notNull(),
  text: text("text").notNull(),
});

export const workoutExerciseSetting = synced("workout_exercise_setting", {
  workoutExerciseId: text("workout_exercise_id").notNull(),
  settingId: text("setting_id").notNull(),
  value: doublePrecision("value"),
  textValue: text("text_value"),
});

export const workoutSet = synced("workout_set", {
  workoutExerciseId: text("workout_exercise_id").notNull(),
  position: doublePrecision("position").notNull(),
  kind: text("kind").notNull(),
  setType: text("set_type").notNull(),
  weightKg: doublePrecision("weight_kg"),
  reps: integer("reps"),
  durationSeconds: integer("duration_seconds"),
  rpe: doublePrecision("rpe"),
  completedAt: bigint("completed_at", { mode: "number" }),
});

export const workoutSetOverride = synced("workout_set_override", {
  workoutSetId: text("workout_set_id").notNull(),
  settingId: text("setting_id").notNull(),
  value: doublePrecision("value").notNull(),
});

export const routine = synced("routine", {
  name: text("name").notNull(),
  position: doublePrecision("position").notNull(),
});

export const routineExercise = synced("routine_exercise", {
  routineId: text("routine_id").notNull(),
  exerciseBrandId: text("exercise_brand_id").notNull(),
  position: doublePrecision("position").notNull(),
  restSeconds: integer("rest_seconds").notNull(),
});

export const routineExerciseSetting = synced("routine_exercise_setting", {
  routineExerciseId: text("routine_exercise_id").notNull(),
  settingId: text("setting_id").notNull(),
  value: doublePrecision("value"),
  textValue: text("text_value"),
});

export const routineSet = synced("routine_set", {
  routineExerciseId: text("routine_exercise_id").notNull(),
  position: doublePrecision("position").notNull(),
  kind: text("kind").notNull(),
  setType: text("set_type").notNull(),
  weightKg: doublePrecision("weight_kg"),
  reps: integer("reps"),
  durationSeconds: integer("duration_seconds"),
});

export const routineSetOverride = synced("routine_set_override", {
  routineSetId: text("routine_set_id").notNull(),
  settingId: text("setting_id").notNull(),
  value: doublePrecision("value").notNull(),
});

/**
 * Every synced table by its SQLite name, parents before children. Pushes and pulls keep this order so
 * a phone applying a page never meets a child before its parent.
 */
export const syncTables = {
  exercise,
  exercise_muscle: exerciseMuscle,
  exercise_brand: exerciseBrand,
  setting,
  workout,
  workout_exercise: workoutExercise,
  workout_exercise_note: workoutExerciseNote,
  workout_exercise_setting: workoutExerciseSetting,
  workout_set: workoutSet,
  workout_set_override: workoutSetOverride,
  routine,
  routine_exercise: routineExercise,
  routine_exercise_setting: routineExerciseSetting,
  routine_set: routineSet,
  routine_set_override: routineSetOverride,
} as const;

export type SyncTableName = keyof typeof syncTables;
export const syncTableNames = Object.keys(syncTables) as SyncTableName[];
