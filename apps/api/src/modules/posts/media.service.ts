import { and, asc, eq, inArray, isNotNull, isNull, lt, or } from "drizzle-orm";
import type { Database } from "../../db/client";
import { mediaKinds, post, postMedia, type MediaKind } from "../../db/schema";
import type { MediaStorage, UploadLink } from "../../lib/storage/storage";

/** A photo or video on a post, as the app shows it. `url` is a download link that expires at `expiresAt`. */
export type MediaView = {
  id: string;
  kind: MediaKind;
  width: number | null;
  height: number | null;
  durationSeconds: number | null;
  position: number;
  url: string;
  expiresAt: Date;
};

/** What preparing an upload returns. `upload` is missing once the file is already in. */
export type PreparedUpload = { id: string; status: "pending" | "ready"; upload?: UploadLink };

export type MediaInput = {
  kind?: unknown;
  contentType?: unknown;
  byteSize?: unknown;
  width?: unknown;
  height?: unknown;
  durationSeconds?: unknown;
  position?: unknown;
};

export class MediaError extends Error {
  constructor(
    readonly code: "invalid" | "not_found" | "deleted" | "removed" | "too_many" | "not_uploaded",
    message: string,
  ) {
    super(message);
  }
}

/** The most photos and videos a post holds, the same as a workout on the phone. */
export const maxMediaPerPost = 3;
/** What the phone may send. It shrinks photos to JPEG and videos to 1080p MP4 first. */
export const accepted: Record<MediaKind, { contentType: string; extension: string; maxBytes: number }> = {
  photo: { contentType: "image/jpeg", extension: "jpg", maxBytes: 10 * 1024 * 1024 },
  video: { contentType: "video/mp4", extension: "mp4", maxBytes: 50 * 1024 * 1024 },
};
/** IDs end up in storage keys, so they're kept to what the phone makes: UUIDs. */
export const idPattern = /^[A-Za-z0-9-]{1,64}$/;
/** How long an upload link works. */
export const uploadSeconds = 15 * 60;
/** How long a download link works. The feed hands out fresh ones on every load. */
export const downloadSeconds = 60 * 60;
/** How long an upload may stay unfinished before the clean-up removes it. */
export const pendingSeconds = 24 * 60 * 60;

/**
 * Gets a photo or video on your post ready to upload, and returns where to send it. The phone makes the ID,
 * so asking twice gives a fresh link for the same file rather than a second one.
 */
export async function prepareUpload(
  db: Database,
  storage: MediaStorage,
  me: string,
  postId: string,
  mediaId: string,
  input: MediaInput,
  now = new Date(),
): Promise<PreparedUpload> {
  if (!idPattern.test(mediaId)) throw new MediaError("invalid", "Media IDs are letters, numbers and dashes.");
  await requireOwnPost(db, me, postId);

  const [existing] = await db.select().from(postMedia).where(eq(postMedia.id, mediaId));
  if (existing) {
    if (existing.postId !== postId || existing.userId !== me) throw new MediaError("not_found", "There's no media with that ID on this post.");
    if (existing.removedAt) throw new MediaError("removed", "That photo or video was taken off the post.");
    if (existing.status === "ready") return { id: existing.id, status: "ready" };
    const upload = await storage.uploadLink(existing.objectKey, existing.contentType, existing.byteSize, uploadSeconds, now);
    return { id: existing.id, status: "pending", upload };
  }

  const values = validate(input);
  const onPost = await db
    .select({ id: postMedia.id })
    .from(postMedia)
    .where(and(eq(postMedia.postId, postId), isNull(postMedia.removedAt)));
  if (onPost.length >= maxMediaPerPost) throw new MediaError("too_many", `A post holds up to ${maxMediaPerPost} photos and videos.`);

  const objectKey = `users/${me}/posts/${postId}/${mediaId}.${accepted[values.kind].extension}`;
  await db.insert(postMedia).values({ id: mediaId, postId, userId: me, objectKey, ...values });
  const upload = await storage.uploadLink(objectKey, values.contentType, values.byteSize, uploadSeconds, now);
  return { id: mediaId, status: "pending", upload };
}

/** The phone has sent the file. Checks it's there at the size it said, then shows it on the post. */
export async function completeUpload(db: Database, storage: MediaStorage, me: string, postId: string, mediaId: string, now = new Date()) {
  const row = await requireOwnMedia(db, me, postId, mediaId);
  if (row.status === "pending") {
    const size = await storage.size(row.objectKey);
    if (size === null) throw new MediaError("not_uploaded", "The file hasn't arrived yet.");
    if (size !== row.byteSize) throw new MediaError("invalid", "The file that arrived isn't the size you said.");
    await db.update(postMedia).set({ status: "ready" }).where(eq(postMedia.id, mediaId));
  }
  return view(storage, { ...row, status: "ready" }, now);
}

/** Takes a photo or video off your post. The file goes straight away; the clean-up retries if that fails. */
export async function removeMedia(db: Database, storage: MediaStorage, me: string, postId: string, mediaId: string, now = new Date()) {
  const row = await requireOwnMedia(db, me, postId, mediaId);
  if (!row.removedAt) await db.update(postMedia).set({ removedAt: now }).where(eq(postMedia.id, mediaId));
  try {
    await storage.delete(row.objectKey);
    await db.delete(postMedia).where(eq(postMedia.id, mediaId));
  } catch {
    // Left for the daily clean-up.
  }
}

/** The finished, not removed media on each of these posts, in order, with download links. */
export async function mediaFor(db: Database, storage: MediaStorage | null, postIds: string[], now = new Date()): Promise<Map<string, MediaView[]>> {
  const byPost = new Map<string, MediaView[]>();
  if (!storage || postIds.length === 0) return byPost;
  const rows = await db
    .select()
    .from(postMedia)
    .where(and(inArray(postMedia.postId, postIds), eq(postMedia.status, "ready"), isNull(postMedia.removedAt)))
    .orderBy(asc(postMedia.position), asc(postMedia.createdAt));
  for (const row of rows) {
    const list = byPost.get(row.postId) ?? [];
    list.push(await view(storage, row, now));
    byPost.set(row.postId, list);
  }
  return byPost;
}

/**
 * The daily clean-up. Deletes the files nobody can see any more, then their rows: uploads never finished
 * within a day, media taken off a post, and everything on deleted posts. Returns how many it removed.
 */
export async function cleanUp(db: Database, storage: MediaStorage, now = new Date()) {
  const stale = new Date(now.getTime() - pendingSeconds * 1000);
  const rows = await db
    .select({ id: postMedia.id, objectKey: postMedia.objectKey })
    .from(postMedia)
    .innerJoin(post, eq(post.id, postMedia.postId))
    .where(or(and(eq(postMedia.status, "pending"), lt(postMedia.createdAt, stale)), isNotNull(postMedia.removedAt), isNotNull(post.deletedAt)));
  let removed = 0;
  for (const row of rows) {
    try {
      await storage.delete(row.objectKey);
      await db.delete(postMedia).where(eq(postMedia.id, row.id));
      removed += 1;
    } catch {
      // Tried again tomorrow.
    }
  }
  return removed;
}

/** Deletes every file an account has stored, before the account itself goes. */
export async function deleteAccountFiles(storage: MediaStorage, userId: string) {
  await storage.deletePrefix(`users/${userId}/`);
}

async function requireOwnPost(db: Database, me: string, postId: string) {
  const [row] = await db.select({ userId: post.userId, deletedAt: post.deletedAt }).from(post).where(eq(post.id, postId));
  if (!row || row.userId !== me) throw new MediaError("not_found", "There's no post with that ID.");
  if (row.deletedAt) throw new MediaError("deleted", "That post was deleted.");
}

async function requireOwnMedia(db: Database, me: string, postId: string, mediaId: string) {
  await requireOwnPost(db, me, postId);
  const [row] = await db.select().from(postMedia).where(and(eq(postMedia.id, mediaId), eq(postMedia.postId, postId), eq(postMedia.userId, me)));
  if (!row) throw new MediaError("not_found", "There's no media with that ID on this post.");
  return row;
}

function validate(input: MediaInput) {
  const fail = (message: string) => new MediaError("invalid", message);
  if (!mediaKinds.includes(input.kind as MediaKind)) throw fail("kind is photo or video.");
  const kind = input.kind as MediaKind;
  const rule = accepted[kind];
  if (input.contentType !== rule.contentType) throw fail(`A ${kind} is sent as ${rule.contentType}.`);
  if (!Number.isInteger(input.byteSize) || (input.byteSize as number) < 1) throw fail("byteSize has to be a whole number of bytes.");
  if ((input.byteSize as number) > rule.maxBytes) throw fail(`A ${kind} can be up to ${rule.maxBytes / 1024 / 1024} MB.`);
  if (!Number.isInteger(input.position) || (input.position as number) < 0 || (input.position as number) >= maxMediaPerPost) {
    throw fail(`position is 0 to ${maxMediaPerPost - 1}.`);
  }
  const size = (value: unknown, name: string) => {
    if (value == null) return null;
    if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > 20_000) throw fail(`${name} has to be a whole number of pixels.`);
    return value as number;
  };
  let durationSeconds: number | null = null;
  if (input.durationSeconds != null) {
    if (kind !== "video" || typeof input.durationSeconds !== "number" || !(input.durationSeconds >= 0)) throw fail("durationSeconds is for videos, in seconds.");
    durationSeconds = input.durationSeconds;
  }
  return {
    kind,
    contentType: rule.contentType,
    byteSize: input.byteSize as number,
    width: size(input.width, "width"),
    height: size(input.height, "height"),
    durationSeconds,
    position: input.position as number,
  };
}

async function view(storage: MediaStorage, row: typeof postMedia.$inferSelect, now: Date): Promise<MediaView> {
  const link = await storage.downloadLink(row.objectKey, downloadSeconds, now);
  return {
    id: row.id,
    kind: row.kind,
    width: row.width,
    height: row.height,
    durationSeconds: row.durationSeconds,
    position: row.position,
    url: link.url,
    expiresAt: link.expiresAt,
  };
}
