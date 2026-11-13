import { and, asc, eq, like, ne, or } from "drizzle-orm";
import type { Database } from "../../db/client";
import { friendship, profile, user, visibilities, type Visibility } from "../../db/schema";
import { friendshipBetween, relationFrom, type Relation } from "../../lib/friendship";

/** Someone as other people see them: enough for a search row or the top of a profile. */
export type Person = {
  userId: string;
  handle: string;
  name: string;
  bio: string | null;
  relation: Relation;
};

/** Your own profile, with the settings only you see. */
export type MyProfile = Person & { defaultVisibility: Visibility };

export type ProfileInput = { handle?: unknown; bio?: unknown; defaultVisibility?: unknown };

export class ProfileError extends Error {
  constructor(
    readonly code: "invalid_handle" | "handle_taken" | "invalid_bio" | "invalid_visibility" | "no_handle",
    message: string,
  ) {
    super(message);
  }
}

const handlePattern = /^[a-z0-9_.]{3,20}$/;

/** Lowercases a handle and drops a leading @, so "@Anton" and "anton" are the same. */
export function normaliseHandle(text: string) {
  return text.trim().replace(/^@/, "").toLowerCase();
}

export async function getMine(db: Database, userId: string): Promise<MyProfile | null> {
  const [row] = await db
    .select({ userId: profile.userId, handle: profile.handle, bio: profile.bio, defaultVisibility: profile.defaultVisibility, name: user.name })
    .from(profile)
    .innerJoin(user, eq(user.id, profile.userId))
    .where(eq(profile.userId, userId));
  return row ? { ...row, relation: "self" } : null;
}

/**
 * Creates your profile, or changes it. A handle is needed the first time; after that each field is
 * optional and only the ones sent change. A bio of `null` or "" clears it.
 */
export async function saveMine(db: Database, userId: string, input: ProfileInput): Promise<MyProfile> {
  const existing = await getMine(db, userId);
  const changes: { handle?: string; bio?: string | null; defaultVisibility?: Visibility } = {};

  if (input.handle !== undefined) {
    if (typeof input.handle !== "string" || !handlePattern.test(normaliseHandle(input.handle))) {
      throw new ProfileError("invalid_handle", "Handles are 3 to 20 letters, numbers, dots or underscores.");
    }
    changes.handle = normaliseHandle(input.handle);
  }
  if (input.bio !== undefined) {
    if (input.bio !== null && typeof input.bio !== "string") throw new ProfileError("invalid_bio", "The bio has to be text.");
    const bio = input.bio?.trim() ?? "";
    if (bio.length > 160) throw new ProfileError("invalid_bio", "Keep the bio to 160 characters.");
    changes.bio = bio || null;
  }
  if (input.defaultVisibility !== undefined) {
    if (!visibilities.includes(input.defaultVisibility as Visibility)) {
      throw new ProfileError("invalid_visibility", "Visibility is public, friends or private.");
    }
    changes.defaultVisibility = input.defaultVisibility as Visibility;
  }

  if (changes.handle && changes.handle !== existing?.handle) {
    const [taken] = await db.select({ userId: profile.userId }).from(profile).where(eq(profile.handle, changes.handle));
    if (taken) throw new ProfileError("handle_taken", `@${changes.handle} is taken.`);
  }

  if (existing) {
    if (Object.keys(changes).length > 0) await db.update(profile).set(changes).where(eq(profile.userId, userId));
  } else {
    if (!changes.handle) throw new ProfileError("no_handle", "Pick a handle first.");
    await db.insert(profile).values({ userId, ...changes, handle: changes.handle });
  }
  return (await getMine(db, userId))!;
}

/** Someone's profile by handle, with how they relate to you. Null when nobody has that handle. */
export async function byHandle(db: Database, me: string, handle: string): Promise<Person | null> {
  const [row] = await db
    .select({ userId: profile.userId, handle: profile.handle, bio: profile.bio, name: user.name })
    .from(profile)
    .innerJoin(user, eq(user.id, profile.userId))
    .where(eq(profile.handle, normaliseHandle(handle)));
  if (!row) return null;
  return { ...row, relation: relationFrom(me, row.userId, await friendshipBetween(db, me, row.userId)) };
}

/**
 * People whose handle starts with what you typed, up to 20, yourself left out. Anyone can be found
 * by handle whatever their visibility, so friends can always send a request.
 */
export async function search(db: Database, me: string, query: string): Promise<Person[]> {
  const text = normaliseHandle(query).replace(/[^a-z0-9_.]/g, "");
  if (!text) return [];
  const rows = await db
    .select({
      userId: profile.userId,
      handle: profile.handle,
      bio: profile.bio,
      name: user.name,
      requesterId: friendship.requesterId,
      status: friendship.status,
    })
    .from(profile)
    .innerJoin(user, eq(user.id, profile.userId))
    .leftJoin(
      friendship,
      or(
        and(eq(friendship.requesterId, me), eq(friendship.addresseeId, profile.userId)),
        and(eq(friendship.requesterId, profile.userId), eq(friendship.addresseeId, me)),
      ),
    )
    // `_` is a wildcard in LIKE, so it's escaped to match only an underscore.
    .where(and(like(profile.handle, `${text.replaceAll("_", "\\_")}%`), ne(profile.userId, me)))
    .orderBy(asc(profile.handle))
    .limit(20);
  return rows.map(({ requesterId, status, ...person }) => ({
    ...person,
    relation: relationFrom(me, person.userId, requesterId && status ? { requesterId, status } : undefined),
  }));
}
