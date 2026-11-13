// What travels between a phone and the server: whole items, as the Sync docs page explains.
// This file says what an item looks like and checks one that came in.

/** In the order they have to arrive: a brand points at an exercise, and routines and workouts point at brands. */
export const kinds = ["exercise", "brand", "routine", "workout", "user_setting"] as const;
export type Kind = (typeof kinds)[number];

export type SettingValue = { settingId: string; value: number | null; textValue: string | null };
export type Override = { settingId: string; value: number };

export const measureNames = ["weight", "reps", "time"] as const;
export type Measure = (typeof measureNames)[number];

export type ItemSet = {
  id: string;
  kind: "reps" | "hold";
  setType: "normal" | "warmup" | "drop" | "failure";
  weightKg: number | null;
  reps: number | null;
  durationSeconds: number | null;
  /** Workouts only. Always null in a routine. */
  rpe: number | null;
  completedAt: number | null;
  overrides: Override[];
};

/** An exercise in a workout or a routine. The order of `exercises`, `notes` and `sets` is their position. */
export type ItemExercise = {
  id: string;
  brandId: string;
  restSeconds: number;
  /** Workouts only. Always empty in a routine. */
  notes: { id: string; text: string }[];
  settings: SettingValue[];
  sets: ItemSet[];
};

export type BrandSetting = {
  id: string;
  name: string;
  kind: "number" | "yes_no" | "text";
  value: number | null;
  textValue: string | null;
  direction: "higher" | "lower" | null;
  rangeMin: number | null;
  rangeMax: number | null;
  splitByValue: boolean;
  /** A tracked setting typed on every set, as one of the exercise's measures, rather than once per exercise. */
  everySet: boolean;
  factor: number | null;
  position: number;
  deletedAt: number | null;
};

export type Bodies = {
  exercise: {
    name: string;
    equipment: string;
    muscles: { muscle: string; share: number }[];
    /** What every set of it records: "reps" or "time", and "weight" when loaded. Null from builds before measures. */
    measures: Measure[] | null;
  };
  brand: { exerciseId: string; brand: string | null; label: string | null; settings: BrandSetting[] };
  routine: { name: string; position: number; exercises: ItemExercise[] };
  workout: {
    title: string;
    note: string | null;
    startedAt: number;
    finishedAt: number;
    routineId: string | null;
    importKey: string | null;
    gymName: string | null;
    gymAddress: string | null;
    gymLatitude: number | null;
    gymLongitude: number | null;
    exercises: ItemExercise[];
  };
  user_setting: { weightUnit: "kg" | "lb" };
};

/**
 * One item. `body` is null only for a deleted routine or workout, whose rows are gone. A deleted
 * exercise or brand keeps its body, because finished workouts still show it.
 */
export type Item<K extends Kind = Kind> = {
  kind: K;
  id: string;
  updatedAt: number;
  deletedAt: number | null;
  body: Bodies[K] | null;
};

export type AnyItem = { [K in Kind]: Item<K> }[Kind];

/** Thrown for an item the server can't take, with where it went wrong, such as `body.exercises[2].sets[0].reps`. */
export class InvalidItem extends Error {}

// Limits, so one request can't fill the database.
const maxText = 4000;
const maxName = 200;
const maxExercises = 100;
const maxSets = 200;
const maxSettings = 50;

type Json = Record<string, unknown>;

function object(value: unknown, at: string): Json {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new InvalidItem(`${at} must be an object`);
  return value as Json;
}

function list(value: unknown, at: string, max: number): unknown[] {
  if (!Array.isArray(value)) throw new InvalidItem(`${at} must be a list`);
  if (value.length > max) throw new InvalidItem(`${at} has more than ${max} entries`);
  return value;
}

function text(value: unknown, at: string, max = maxName): string {
  if (typeof value !== "string") throw new InvalidItem(`${at} must be text`);
  if (value.length > max) throw new InvalidItem(`${at} is longer than ${max} characters`);
  return value;
}

function number(value: unknown, at: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new InvalidItem(`${at} must be a number`);
  return value;
}

function whole(value: unknown, at: string): number {
  const n = number(value, at);
  if (!Number.isSafeInteger(n)) throw new InvalidItem(`${at} must be a whole number`);
  return n;
}

function oneOf<const T extends readonly string[]>(value: unknown, options: T, at: string): T[number] {
  if (typeof value !== "string" || !options.includes(value)) throw new InvalidItem(`${at} must be one of ${options.join(", ")}`);
  return value;
}

/** Null or missing gives null. */
function optional<T>(value: unknown, read: (value: unknown) => T): T | null {
  return value === null || value === undefined ? null : read(value);
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** IDs are UUIDs made on the phone. They are lowercase on the server whatever case they arrive in. */
function id(value: unknown, at: string): string {
  if (typeof value !== "string" || !uuid.test(value)) throw new InvalidItem(`${at} must be a UUID`);
  return value.toLowerCase();
}

function settingValues(value: unknown, at: string): SettingValue[] {
  return list(value, at, maxSettings).map((raw, i) => {
    const o = object(raw, `${at}[${i}]`);
    return {
      settingId: id(o.settingId, `${at}[${i}].settingId`),
      value: optional(o.value, (v) => number(v, `${at}[${i}].value`)),
      textValue: optional(o.textValue, (v) => text(v, `${at}[${i}].textValue`, maxText)),
    };
  });
}

function sets(value: unknown, at: string, inWorkout: boolean): ItemSet[] {
  return list(value, at, maxSets).map((raw, i) => {
    const here = `${at}[${i}]`;
    const o = object(raw, here);
    return {
      id: id(o.id, `${here}.id`),
      kind: oneOf(o.kind, ["reps", "hold"] as const, `${here}.kind`),
      setType: oneOf(o.setType ?? "normal", ["normal", "warmup", "drop", "failure"] as const, `${here}.setType`),
      weightKg: optional(o.weightKg, (v) => number(v, `${here}.weightKg`)),
      reps: optional(o.reps, (v) => whole(v, `${here}.reps`)),
      durationSeconds: optional(o.durationSeconds, (v) => whole(v, `${here}.durationSeconds`)),
      rpe: inWorkout ? optional(o.rpe, (v) => number(v, `${here}.rpe`)) : null,
      completedAt: inWorkout ? optional(o.completedAt, (v) => whole(v, `${here}.completedAt`)) : null,
      overrides: list(o.overrides ?? [], `${here}.overrides`, maxSettings).map((rawOverride, j) => {
        const override = object(rawOverride, `${here}.overrides[${j}]`);
        return {
          settingId: id(override.settingId, `${here}.overrides[${j}].settingId`),
          value: number(override.value, `${here}.overrides[${j}].value`),
        };
      }),
    };
  });
}

function exercises(value: unknown, at: string, inWorkout: boolean): ItemExercise[] {
  return list(value, at, maxExercises).map((raw, i) => {
    const here = `${at}[${i}]`;
    const o = object(raw, here);
    return {
      id: id(o.id, `${here}.id`),
      brandId: id(o.brandId, `${here}.brandId`),
      restSeconds: whole(o.restSeconds, `${here}.restSeconds`),
      notes: inWorkout
        ? list(o.notes ?? [], `${here}.notes`, maxSettings).map((rawNote, j) => {
            const note = object(rawNote, `${here}.notes[${j}]`);
            return { id: id(note.id, `${here}.notes[${j}].id`), text: text(note.text, `${here}.notes[${j}].text`, maxText) };
          })
        : [],
      settings: settingValues(o.settings ?? [], `${here}.settings`),
      sets: sets(o.sets ?? [], `${here}.sets`, inWorkout),
    };
  });
}

/** An exercise's measures: reps or time, exactly one, and weight if it's loaded. */
function measures(value: unknown, at: string): Measure[] {
  const names = list(value, at, measureNames.length).map((raw, i) => oneOf(raw, measureNames, `${at}[${i}]`));
  if (new Set(names).size !== names.length) throw new InvalidItem(`${at} lists a measure twice`);
  if (names.filter((n) => n !== "weight").length !== 1) throw new InvalidItem(`${at} needs reps or time, not both`);
  return names;
}

const bodies: { [K in Kind]: (o: Json) => Bodies[K] } = {
  exercise: (o) => ({
    name: text(o.name, "body.name"),
    equipment: text(o.equipment, "body.equipment"),
    muscles: list(o.muscles ?? [], "body.muscles", maxSettings).map((raw, i) => {
      const muscle = object(raw, `body.muscles[${i}]`);
      return { muscle: text(muscle.muscle, `body.muscles[${i}].muscle`), share: number(muscle.share, `body.muscles[${i}].share`) };
    }),
    measures: optional(o.measures, (v) => measures(v, "body.measures")),
  }),
  brand: (o) => ({
    exerciseId: id(o.exerciseId, "body.exerciseId"),
    brand: optional(o.brand, (v) => text(v, "body.brand")),
    label: optional(o.label, (v) => text(v, "body.label")),
    settings: list(o.settings ?? [], "body.settings", maxSettings).map((raw, i) => {
      const here = `body.settings[${i}]`;
      const s = object(raw, here);
      return {
        id: id(s.id, `${here}.id`),
        name: text(s.name, `${here}.name`),
        kind: oneOf(s.kind, ["number", "yes_no", "text"] as const, `${here}.kind`),
        value: optional(s.value, (v) => number(v, `${here}.value`)),
        textValue: optional(s.textValue, (v) => text(v, `${here}.textValue`, maxText)),
        direction: optional(s.direction, (v) => oneOf(v, ["higher", "lower"] as const, `${here}.direction`)),
        rangeMin: optional(s.rangeMin, (v) => number(v, `${here}.rangeMin`)),
        rangeMax: optional(s.rangeMax, (v) => number(v, `${here}.rangeMax`)),
        splitByValue: s.splitByValue === true,
        everySet: s.everySet === true,
        factor: optional(s.factor, (v) => number(v, `${here}.factor`)),
        position: number(s.position ?? i, `${here}.position`),
        deletedAt: optional(s.deletedAt, (v) => whole(v, `${here}.deletedAt`)),
      };
    }),
  }),
  routine: (o) => ({
    name: text(o.name, "body.name"),
    position: number(o.position, "body.position"),
    exercises: exercises(o.exercises ?? [], "body.exercises", false),
  }),
  workout: (o) => {
    // A running workout stays on the phone, so one without an end is a mistake.
    if (o.finishedAt === null || o.finishedAt === undefined) throw new InvalidItem("body.finishedAt is missing: a workout syncs once it is finished");
    return {
      title: text(o.title, "body.title"),
      note: optional(o.note, (v) => text(v, "body.note", maxText)),
      startedAt: whole(o.startedAt, "body.startedAt"),
      finishedAt: whole(o.finishedAt, "body.finishedAt"),
      routineId: optional(o.routineId, (v) => id(v, "body.routineId")),
      importKey: optional(o.importKey, (v) => text(v, "body.importKey", maxText)),
      gymName: optional(o.gymName, (v) => text(v, "body.gymName")),
      gymAddress: optional(o.gymAddress, (v) => text(v, "body.gymAddress", maxText)),
      gymLatitude: optional(o.gymLatitude, (v) => number(v, "body.gymLatitude")),
      gymLongitude: optional(o.gymLongitude, (v) => number(v, "body.gymLongitude")),
      exercises: exercises(o.exercises ?? [], "body.exercises", true),
    };
  },
  user_setting: (o) => ({ weightUnit: oneOf(o.weightUnit, ["kg", "lb"] as const, "body.weightUnit") }),
};

/** Checks one item from a push and returns it with lowercase IDs. Throws `InvalidItem` saying what is wrong. */
export function parseItem(raw: unknown): AnyItem {
  const o = object(raw, "item");
  const kind = oneOf(o.kind, kinds, "kind");
  const deletedAt = optional(o.deletedAt, (v) => whole(v, "deletedAt"));
  // A deleted routine or workout has no rows left, so whatever body it came with is dropped.
  const bodiless = deletedAt !== null && (kind === "routine" || kind === "workout");
  return {
    kind,
    id: id(o.id, "id"),
    updatedAt: whole(o.updatedAt, "updatedAt"),
    deletedAt,
    body: bodiless ? null : bodies[kind](object(o.body, "body")),
  } as AnyItem;
}
