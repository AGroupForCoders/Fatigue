import { bigint, boolean, doublePrecision, foreignKey, index, integer, pgTable, primaryKey, text } from "drizzle-orm/pg-core";
import { user } from "./auth";

// The synced tables: the same ones the phone has, as the Sync docs page explains.
//
// Sync moves whole items. An item is a top row (exercise, exercise_brand, routine, workout, user_setting)
// and the rows under it. Only top rows carry the sync columns.
//
// Every row has a `user_id`, and every key starts with it. IDs are made on the phone, and an exercise's
// is built from its name, so two accounts that both create "Sissy Squat" send the same ID.
//
// Rows under a top row point at it with a cascade, so deleting the top row, or the account, takes them
// along. Rows don't point across items (a workout exercise has no foreign key to its brand): items are
// accepted one by one, and one refused item must not take the others down with it.

const userId = () =>
  text("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" });

/** Milliseconds since 1970, as the phone stores times. */
const millis = (name: string) => bigint(name, { mode: "number" });

/** What every top row has on top of its own columns. */
const syncColumns = () => ({
  /** Set by the phone on every change. The later one wins when two phones changed the same item. */
  updatedAt: millis("updated_at").notNull(),
  /** Set instead of removing the row, so the deletion reaches the other phones. */
  deletedAt: millis("deleted_at"),
  /** From the account's counter in `sync_account`. A pull asks for everything above its cursor. */
  version: bigint("version", { mode: "number" }).notNull(),
  /** The schema of the build that last wrote the item. An older build can't overwrite it. */
  schema: integer("schema").notNull(),
});

/** One counter per account. A push locks it, so one account's pushes take turns and versions never commit out of order. */
export const syncAccount = pgTable("sync_account", {
  userId: text("user_id")
    .primaryKey()
    .references(() => user.id, { onDelete: "cascade" }),
  version: bigint("version", { mode: "number" }).notNull().default(0),
});

// Exercises and brands

/** A custom exercise. Built-in ones ship with the app under fixed IDs and never sync. */
export const exercise = pgTable(
  "exercise",
  {
    userId: userId(),
    id: text("id").notNull(),
    name: text("name").notNull(),
    equipment: text("equipment").notNull(),
    /** "reps" or "time", and "weight" when loaded. Null for exercises from builds before measures. */
    measures: text("measures").array(),
    ...syncColumns(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.id] }), index("exercise_version_idx").on(t.userId, t.version)],
);

export const exerciseMuscle = pgTable(
  "exercise_muscle",
  {
    userId: text("user_id").notNull(),
    exerciseId: text("exercise_id").notNull(),
    muscle: text("muscle").notNull(),
    share: doublePrecision("share").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.exerciseId, t.muscle] }),
    foreignKey({ columns: [t.userId, t.exerciseId], foreignColumns: [exercise.userId, exercise.id] }).onDelete("cascade"),
  ],
);

/** An exercise on one brand, or on no brand. Its settings travel with it. */
export const exerciseBrand = pgTable(
  "exercise_brand",
  {
    userId: userId(),
    id: text("id").notNull(),
    /** A custom exercise of this account, or a built-in one, which has no row here. */
    exerciseId: text("exercise_id").notNull(),
    brand: text("brand"),
    label: text("label"),
    ...syncColumns(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.id] }), index("exercise_brand_version_idx").on(t.userId, t.version)],
);

export const setting = pgTable(
  "setting",
  {
    userId: text("user_id").notNull(),
    id: text("id").notNull(),
    exerciseBrandId: text("exercise_brand_id").notNull(),
    name: text("name").notNull(),
    kind: text("kind", { enum: ["number", "yes_no", "text"] }).notNull(),
    value: doublePrecision("value"),
    textValue: text("text_value"),
    direction: text("direction", { enum: ["higher", "lower"] }),
    rangeMin: doublePrecision("range_min"),
    rangeMax: doublePrecision("range_max"),
    splitByValue: boolean("split_by_value").notNull().default(false),
    /** Typed on every set as one of the exercise's measures, rather than once per exercise. */
    everySet: boolean("every_set").notNull().default(false),
    factor: doublePrecision("factor"),
    position: doublePrecision("position").notNull(),
    /** A removed setting stays for the workouts that used it. */
    deletedAt: millis("deleted_at"),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({ columns: [t.userId, t.exerciseBrandId], foreignColumns: [exerciseBrand.userId, exerciseBrand.id] }).onDelete("cascade"),
    index("setting_brand_idx").on(t.userId, t.exerciseBrandId),
  ],
);

// Workouts

export const workout = pgTable(
  "workout",
  {
    userId: userId(),
    id: text("id").notNull(),
    title: text("title").notNull(),
    note: text("note"),
    startedAt: millis("started_at").notNull(),
    /** Always set: a running workout stays on the phone. */
    finishedAt: millis("finished_at").notNull(),
    routineId: text("routine_id"),
    importKey: text("import_key"),
    gymName: text("gym_name"),
    gymAddress: text("gym_address"),
    gymLatitude: doublePrecision("gym_latitude"),
    gymLongitude: doublePrecision("gym_longitude"),
    ...syncColumns(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.id] }), index("workout_version_idx").on(t.userId, t.version)],
);

export const workoutExercise = pgTable(
  "workout_exercise",
  {
    userId: text("user_id").notNull(),
    id: text("id").notNull(),
    workoutId: text("workout_id").notNull(),
    exerciseBrandId: text("exercise_brand_id").notNull(),
    position: doublePrecision("position").notNull(),
    restSeconds: integer("rest_seconds").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({ columns: [t.userId, t.workoutId], foreignColumns: [workout.userId, workout.id] }).onDelete("cascade"),
    index("workout_exercise_workout_idx").on(t.userId, t.workoutId),
  ],
);

export const workoutExerciseNote = pgTable(
  "workout_exercise_note",
  {
    userId: text("user_id").notNull(),
    id: text("id").notNull(),
    workoutExerciseId: text("workout_exercise_id").notNull(),
    position: doublePrecision("position").notNull(),
    text: text("text").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({ columns: [t.userId, t.workoutExerciseId], foreignColumns: [workoutExercise.userId, workoutExercise.id] }).onDelete("cascade"),
    index("workout_exercise_note_exercise_idx").on(t.userId, t.workoutExerciseId),
  ],
);

export const workoutExerciseSetting = pgTable(
  "workout_exercise_setting",
  {
    userId: text("user_id").notNull(),
    workoutExerciseId: text("workout_exercise_id").notNull(),
    settingId: text("setting_id").notNull(),
    value: doublePrecision("value"),
    textValue: text("text_value"),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.workoutExerciseId, t.settingId] }),
    foreignKey({ columns: [t.userId, t.workoutExerciseId], foreignColumns: [workoutExercise.userId, workoutExercise.id] }).onDelete("cascade"),
  ],
);

export const workoutSet = pgTable(
  "workout_set",
  {
    userId: text("user_id").notNull(),
    id: text("id").notNull(),
    workoutExerciseId: text("workout_exercise_id").notNull(),
    position: doublePrecision("position").notNull(),
    kind: text("kind", { enum: ["reps", "hold"] }).notNull(),
    setType: text("set_type", { enum: ["normal", "warmup", "drop", "failure"] }).notNull().default("normal"),
    weightKg: doublePrecision("weight_kg"),
    reps: integer("reps"),
    durationSeconds: integer("duration_seconds"),
    rpe: doublePrecision("rpe"),
    completedAt: millis("completed_at"),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({ columns: [t.userId, t.workoutExerciseId], foreignColumns: [workoutExercise.userId, workoutExercise.id] }).onDelete("cascade"),
    index("workout_set_exercise_idx").on(t.userId, t.workoutExerciseId),
  ],
);

export const workoutSetOverride = pgTable(
  "workout_set_override",
  {
    userId: text("user_id").notNull(),
    workoutSetId: text("workout_set_id").notNull(),
    settingId: text("setting_id").notNull(),
    value: doublePrecision("value").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.workoutSetId, t.settingId] }),
    foreignKey({ columns: [t.userId, t.workoutSetId], foreignColumns: [workoutSet.userId, workoutSet.id] }).onDelete("cascade"),
  ],
);

// Routines

export const routine = pgTable(
  "routine",
  {
    userId: userId(),
    id: text("id").notNull(),
    name: text("name").notNull(),
    position: doublePrecision("position").notNull(),
    ...syncColumns(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.id] }), index("routine_version_idx").on(t.userId, t.version)],
);

export const routineExercise = pgTable(
  "routine_exercise",
  {
    userId: text("user_id").notNull(),
    id: text("id").notNull(),
    routineId: text("routine_id").notNull(),
    exerciseBrandId: text("exercise_brand_id").notNull(),
    position: doublePrecision("position").notNull(),
    restSeconds: integer("rest_seconds").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({ columns: [t.userId, t.routineId], foreignColumns: [routine.userId, routine.id] }).onDelete("cascade"),
    index("routine_exercise_routine_idx").on(t.userId, t.routineId),
  ],
);

export const routineExerciseSetting = pgTable(
  "routine_exercise_setting",
  {
    userId: text("user_id").notNull(),
    routineExerciseId: text("routine_exercise_id").notNull(),
    settingId: text("setting_id").notNull(),
    value: doublePrecision("value"),
    textValue: text("text_value"),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.routineExerciseId, t.settingId] }),
    foreignKey({ columns: [t.userId, t.routineExerciseId], foreignColumns: [routineExercise.userId, routineExercise.id] }).onDelete("cascade"),
  ],
);

export const routineSet = pgTable(
  "routine_set",
  {
    userId: text("user_id").notNull(),
    id: text("id").notNull(),
    routineExerciseId: text("routine_exercise_id").notNull(),
    position: doublePrecision("position").notNull(),
    kind: text("kind", { enum: ["reps", "hold"] }).notNull(),
    setType: text("set_type", { enum: ["normal", "warmup", "drop", "failure"] }).notNull().default("normal"),
    weightKg: doublePrecision("weight_kg"),
    reps: integer("reps"),
    durationSeconds: integer("duration_seconds"),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.id] }),
    foreignKey({ columns: [t.userId, t.routineExerciseId], foreignColumns: [routineExercise.userId, routineExercise.id] }).onDelete("cascade"),
    index("routine_set_exercise_idx").on(t.userId, t.routineExerciseId),
  ],
);

export const routineSetOverride = pgTable(
  "routine_set_override",
  {
    userId: text("user_id").notNull(),
    routineSetId: text("routine_set_id").notNull(),
    settingId: text("setting_id").notNull(),
    value: doublePrecision("value").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.routineSetId, t.settingId] }),
    foreignKey({ columns: [t.userId, t.routineSetId], foreignColumns: [routineSet.userId, routineSet.id] }).onDelete("cascade"),
  ],
);

// Settings

/** One row per account. Its ID is built from the account's. */
export const userSetting = pgTable(
  "user_setting",
  {
    userId: userId(),
    id: text("id").notNull(),
    weightUnit: text("weight_unit", { enum: ["kg", "lb"] }).notNull(),
    ...syncColumns(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.id] }), index("user_setting_version_idx").on(t.userId, t.version)],
);
