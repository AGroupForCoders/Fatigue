import { and, desc, eq, inArray, isNull, or, sql, type SQL } from "drizzle-orm";
import type { Database } from "../../db/client";
import { friendship, post, profile, user, visibilities, type Visibility } from "../../db/schema";
import { photoUrls } from "../../lib/photos";
import type { MediaStorage } from "../../lib/storage/storage";
import { mediaFor, type MediaView } from "./media.service";

/** A shared workout as the app shows it, with who shared it. */
export type PostView = {
  id: string;
  author: { userId: string; handle: string; name: string; photoUrl: string | null };
  /** The workout's ID on the sharer's phone. Only sent to the sharer. */
  workoutId: string | null;
  caption: string | null;
  visibility: Visibility;
  startedAt: Date;
  createdAt: Date;
  snapshotVersion: number;
  snapshot: unknown;
  /** Finished photos and videos, in order, with download links. Empty when storage isn't set up. */
  media: MediaView[];
};

export type Page = { posts: PostView[]; nextCursor: string | null };

export type ShareInput = {
  workoutId?: unknown;
  caption?: unknown;
  visibility?: unknown;
  startedAt?: unknown;
  snapshotVersion?: unknown;
  snapshot?: unknown;
};

export class PostError extends Error {
  constructor(
    readonly code: "invalid" | "no_profile" | "not_found" | "deleted",
    message: string,
  ) {
    super(message);
  }
}

/** How many posts a page holds. */
export const pageSize = 20;
/** The largest snapshot accepted, in bytes of JSON. A long workout is a few tens of kilobytes. */
const maxSnapshotBytes = 256 * 1024;

/**
 * Shares a workout, or shares it again. The phone makes `id`, so sending the same share twice (such as
 * after a timeout) updates the one post. Sharing a workout that already has a live post replaces that
 * post's snapshot and keeps its ID, which the result carries.
 */
export async function share(db: Database, me: string, id: string, input: ShareInput, storage: MediaStorage | null = null): Promise<PostView> {
  const [author] = await db.select({ defaultVisibility: profile.defaultVisibility }).from(profile).where(eq(profile.userId, me));
  if (!author) throw new PostError("no_profile", "Pick a handle before sharing.");
  const values = validate(input, author.defaultVisibility);

  const [byId] = await db.select({ userId: post.userId, deletedAt: post.deletedAt }).from(post).where(eq(post.id, id));
  if (byId && byId.userId !== me) throw new PostError("not_found", "There's no post with that ID.");
  if (byId?.deletedAt) throw new PostError("deleted", "That post was deleted.");

  let target = byId ? id : undefined;
  if (!target && values.workoutId) {
    const [byWorkout] = await db
      .select({ id: post.id })
      .from(post)
      .where(and(eq(post.userId, me), eq(post.workoutId, values.workoutId), isNull(post.deletedAt)));
    target = byWorkout?.id;
  }

  if (target) {
    await db.update(post).set(values).where(eq(post.id, target));
  } else {
    target = id;
    await db.insert(post).values({ id, userId: me, ...values });
  }
  return (await get(db, me, target, storage))!;
}

function validate(input: ShareInput, defaultVisibility: Visibility) {
  const fail = (message: string) => new PostError("invalid", message);
  if (input.workoutId != null && typeof input.workoutId !== "string") throw fail("workoutId has to be text.");
  if (input.caption != null && typeof input.caption !== "string") throw fail("The caption has to be text.");
  const caption = (input.caption as string | null | undefined)?.trim() || null;
  if (caption && caption.length > 2000) throw fail("Keep the caption to 2000 characters.");
  if (input.visibility !== undefined && !visibilities.includes(input.visibility as Visibility)) {
    throw fail("Visibility is public, friends or private.");
  }
  const startedAt = typeof input.startedAt === "string" ? new Date(input.startedAt) : null;
  if (!startedAt || Number.isNaN(startedAt.getTime())) throw fail("startedAt has to be an ISO 8601 date.");
  if (!Number.isInteger(input.snapshotVersion) || (input.snapshotVersion as number) < 1) throw fail("snapshotVersion has to be a whole number from 1.");
  if (!input.snapshot || typeof input.snapshot !== "object" || Array.isArray(input.snapshot)) throw fail("The snapshot has to be an object.");
  if (new TextEncoder().encode(JSON.stringify(input.snapshot)).length > maxSnapshotBytes) throw fail("That workout is too big to share.");
  return {
    workoutId: (input.workoutId as string | null | undefined) ?? null,
    caption,
    visibility: (input.visibility as Visibility | undefined) ?? defaultVisibility,
    startedAt,
    snapshotVersion: input.snapshotVersion as number,
    snapshot: input.snapshot,
  };
}

/** Deletes your post. It disappears straight away; sending the same share again afterwards is refused. */
export async function remove(db: Database, me: string, id: string) {
  await db
    .update(post)
    .set({ deletedAt: new Date() })
    .where(and(eq(post.id, id), eq(post.userId, me), isNull(post.deletedAt)));
}

/** One post, if you're allowed to see it. */
export async function get(db: Database, me: string, id: string, storage: MediaStorage | null = null): Promise<PostView | null> {
  const [row] = await select(db, me, and(eq(post.id, id), visibleTo(me))!, 1, storage);
  return row ?? null;
}

/** Your posts and your friends' posts you can see, newest workout first. */
export async function feed(db: Database, me: string, cursor?: string, storage: MediaStorage | null = null): Promise<Page> {
  const authors = or(eq(post.userId, me), and(inArray(post.userId, friendIdsQuery(me)), inArray(post.visibility, ["public", "friends"])));
  return page(db, me, and(isNull(post.deletedAt), authors)!, cursor, storage);
}

/** Someone's posts that you can see, newest workout first. All of them when it's you. */
export async function byAuthor(db: Database, me: string, authorId: string, cursor?: string, storage: MediaStorage | null = null): Promise<Page> {
  return page(db, me, and(eq(post.userId, authorId), visibleTo(me))!, cursor, storage);
}

/** Who can see a post: the author always, anyone for public, accepted friends for friends only. Never once deleted. */
function visibleTo(me: string) {
  return and(
    isNull(post.deletedAt),
    or(
      eq(post.userId, me),
      eq(post.visibility, "public"),
      and(eq(post.visibility, "friends"), inArray(post.userId, friendIdsQuery(me))),
    ),
  );
}

/** The user IDs of your accepted friends, as a subquery. */
function friendIdsQuery(me: string) {
  return sql`(select case when ${friendship.requesterId} = ${me} then ${friendship.addresseeId} else ${friendship.requesterId} end
    from ${friendship}
    where ${friendship.status} = 'accepted' and (${friendship.requesterId} = ${me} or ${friendship.addresseeId} = ${me}))`;
}

async function page(db: Database, me: string, where: SQL, cursor: string | undefined, storage: MediaStorage | null): Promise<Page> {
  const after = cursor ? decodeCursor(cursor) : null;
  const condition = after ? and(where, sql`(${post.startedAt}, ${post.id}) < (${after.startedAt}, ${after.id})`)! : where;
  const posts = await select(db, me, condition, pageSize, storage);
  const last = posts.at(-1);
  return { posts, nextCursor: posts.length === pageSize && last ? encodeCursor(last.startedAt, last.id) : null };
}

async function select(db: Database, me: string, where: SQL, limit: number, storage: MediaStorage | null): Promise<PostView[]> {
  const rows = await db
    .select({ post, handle: profile.handle, name: user.name })
    .from(post)
    .innerJoin(profile, eq(profile.userId, post.userId))
    .innerJoin(user, eq(user.id, post.userId))
    .where(where)
    .orderBy(desc(post.startedAt), desc(post.id))
    .limit(limit);
  const media = await mediaFor(
    db,
    storage,
    rows.map((row) => row.post.id),
  );
  const photos = await photoUrls(
    db,
    storage,
    rows.map((row) => row.post.userId),
  );
  return rows.map(({ post: row, handle, name }) => ({
    id: row.id,
    author: { userId: row.userId, handle, name, photoUrl: photos.get(row.userId) ?? null },
    workoutId: row.userId === me ? row.workoutId : null,
    caption: row.caption,
    visibility: row.visibility,
    startedAt: row.startedAt,
    createdAt: row.createdAt,
    snapshotVersion: row.snapshotVersion,
    snapshot: row.snapshot,
    media: media.get(row.id) ?? [],
  }));
}

/** The cursor is where the last page ended, so posts shared while you scroll never repeat or skip a row. */
function encodeCursor(startedAt: Date, id: string) {
  return Buffer.from(JSON.stringify([startedAt.toISOString(), id])).toString("base64url");
}

function decodeCursor(cursor: string): { startedAt: string; id: string } {
  try {
    const [startedAt, id] = JSON.parse(Buffer.from(cursor, "base64url").toString()) as [string, string];
    if (typeof startedAt !== "string" || typeof id !== "string" || Number.isNaN(new Date(startedAt).getTime())) throw new Error();
    return { startedAt, id };
  } catch {
    throw new PostError("invalid", "That cursor isn't one this API made.");
  }
}
