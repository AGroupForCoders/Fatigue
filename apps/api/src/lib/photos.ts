import { inArray } from "drizzle-orm";
import type { Database } from "../db/client";
import { profile } from "../db/schema";
import type { MediaStorage } from "./storage/storage";
import { downloadSeconds } from "../modules/posts/media.service";

/**
 * Download links for these people's profile photos, by user ID. Anyone signed in can see a profile photo,
 * the same as a handle. People without a photo, or no storage set up, are left out.
 */
export async function photoUrls(db: Database, storage: MediaStorage | null, userIds: string[], now = new Date()): Promise<Map<string, string>> {
  const urls = new Map<string, string>();
  const ids = [...new Set(userIds)];
  if (!storage || ids.length === 0) return urls;
  const rows = await db.select({ userId: profile.userId, photoKey: profile.photoKey }).from(profile).where(inArray(profile.userId, ids));
  for (const row of rows) {
    if (row.photoKey) urls.set(row.userId, (await storage.downloadLink(row.photoKey, downloadSeconds, now)).url);
  }
  return urls;
}

/** Adds `photoUrl` to each person. */
export async function withPhotos<T extends { userId: string }>(db: Database, storage: MediaStorage | null, people: T[]) {
  const urls = await photoUrls(db, storage, people.map((person) => person.userId));
  return people.map((person) => ({ ...person, photoUrl: urls.get(person.userId) ?? null }));
}
