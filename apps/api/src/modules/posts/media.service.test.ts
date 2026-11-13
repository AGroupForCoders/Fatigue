import { describe, expect, it } from "vitest";
import { friendship, post, postMedia, profile } from "../../db/schema";
import { addUser, testDb } from "../../db/test-db";
import { MemoryStorage } from "../../lib/storage/storage";
import { cleanUp, completeUpload, deleteAccountFiles, MediaError, prepareUpload, removeMedia } from "./media.service";
import { feed, get, remove, share } from "./posts.service";

const photo = { kind: "photo", contentType: "image/jpeg", byteSize: 1000, width: 2048, height: 1536, position: 0 };
const video = { kind: "video", contentType: "video/mp4", byteSize: 5000, width: 1920, height: 1080, durationSeconds: 12.5, position: 1 };

async function setUp() {
  const db = await testDb();
  for (const id of ["anton", "jos", "stranger"]) {
    await addUser(db, id);
    await db.insert(profile).values({ userId: id, handle: id });
  }
  await db.insert(friendship).values({ id: "f", requesterId: "anton", addresseeId: "jos", status: "accepted" });
  await share(db, "anton", "p1", { workoutId: "w1", visibility: "friends", startedAt: "2026-11-10T18:00:00.000Z", snapshotVersion: 1, snapshot: {} });
  return { db, storage: new MemoryStorage() };
}

async function rejects(promise: Promise<unknown>, code: MediaError["code"]) {
  await expect(promise).rejects.toMatchObject({ code });
}

describe("media on posts", () => {
  it("hands out an upload link for exactly the declared file, under the owner's folder", async () => {
    const { db, storage } = await setUp();
    const prepared = await prepareUpload(db, storage, "anton", "p1", "m1", photo);

    expect(prepared.status).toBe("pending");
    expect(prepared.upload?.url).toContain("users/anton/posts/p1/m1.jpg");
    expect(prepared.upload?.headers).toMatchObject({ "content-type": "image/jpeg", "content-length": "1000" });
  });

  it("only shows media once the file has arrived", async () => {
    const { db, storage } = await setUp();
    await prepareUpload(db, storage, "anton", "p1", "m1", photo);
    expect((await get(db, "jos", "p1", storage))?.media).toEqual([]);
    await rejects(completeUpload(db, storage, "anton", "p1", "m1"), "not_uploaded");

    storage.put("users/anton/posts/p1/m1.jpg", 1000);
    await completeUpload(db, storage, "anton", "p1", "m1");

    const seen = await get(db, "jos", "p1", storage);
    expect(seen?.media).toMatchObject([{ id: "m1", kind: "photo", width: 2048, height: 1536, url: "https://storage.test/users/anton/posts/p1/m1.jpg" }]);
  });

  it("refuses a file of another size", async () => {
    const { db, storage } = await setUp();
    await prepareUpload(db, storage, "anton", "p1", "m1", photo);
    storage.put("users/anton/posts/p1/m1.jpg", 999);
    await rejects(completeUpload(db, storage, "anton", "p1", "m1"), "invalid");
  });

  it("asking again gives a fresh link for the same file, and none once it's in", async () => {
    const { db, storage } = await setUp();
    await prepareUpload(db, storage, "anton", "p1", "m1", photo);
    const again = await prepareUpload(db, storage, "anton", "p1", "m1", photo);
    expect(again.upload).toBeDefined();
    expect(await db.select().from(postMedia)).toHaveLength(1);

    storage.put("users/anton/posts/p1/m1.jpg", 1000);
    await completeUpload(db, storage, "anton", "p1", "m1");
    expect(await prepareUpload(db, storage, "anton", "p1", "m1", photo)).toEqual({ id: "m1", status: "ready" });
  });

  it("keeps media in the order the phone gave", async () => {
    const { db, storage } = await setUp();
    await prepareUpload(db, storage, "anton", "p1", "m2", video);
    await prepareUpload(db, storage, "anton", "p1", "m1", photo);
    storage.put("users/anton/posts/p1/m1.jpg", 1000);
    storage.put("users/anton/posts/p1/m2.mp4", 5000);
    await completeUpload(db, storage, "anton", "p1", "m2");
    await completeUpload(db, storage, "anton", "p1", "m1");

    const page = await feed(db, "jos", undefined, storage);
    expect(page.posts[0]?.media.map((m) => [m.id, m.kind, m.durationSeconds])).toEqual([
      ["m1", "photo", null],
      ["m2", "video", 12.5],
    ]);
  });

  it("people who can't see the post never get its links", async () => {
    const { db, storage } = await setUp();
    await prepareUpload(db, storage, "anton", "p1", "m1", photo);
    storage.put("users/anton/posts/p1/m1.jpg", 1000);
    await completeUpload(db, storage, "anton", "p1", "m1");

    expect(await get(db, "stranger", "p1", storage)).toBeNull();
    expect((await feed(db, "stranger", undefined, storage)).posts).toEqual([]);
  });

  it("only the author can add to a post", async () => {
    const { db, storage } = await setUp();
    await rejects(prepareUpload(db, storage, "jos", "p1", "m1", photo), "not_found");
  });

  it("holds up to three", async () => {
    const { db, storage } = await setUp();
    for (const id of ["a", "b", "c"]) await prepareUpload(db, storage, "anton", "p1", id, { ...photo, position: 0 });
    await rejects(prepareUpload(db, storage, "anton", "p1", "d", photo), "too_many");
  });

  it("refuses what the phone shouldn't send", async () => {
    const { db, storage } = await setUp();
    await rejects(prepareUpload(db, storage, "anton", "p1", "m1", { ...photo, contentType: "image/heic" }), "invalid");
    await rejects(prepareUpload(db, storage, "anton", "p1", "m1", { ...photo, byteSize: 11 * 1024 * 1024 }), "invalid");
    await rejects(prepareUpload(db, storage, "anton", "p1", "m1", { ...video, byteSize: 51 * 1024 * 1024 }), "invalid");
    await rejects(prepareUpload(db, storage, "anton", "p1", "m1", { ...photo, durationSeconds: 3 }), "invalid");
    await rejects(prepareUpload(db, storage, "anton", "p1", "../m1", photo), "invalid");
  });

  it("taking media off a post deletes its file, and it can't be sent again", async () => {
    const { db, storage } = await setUp();
    await prepareUpload(db, storage, "anton", "p1", "m1", photo);
    storage.put("users/anton/posts/p1/m1.jpg", 1000);
    await completeUpload(db, storage, "anton", "p1", "m1");
    await removeMedia(db, storage, "anton", "p1", "m1");

    expect(storage.files.size).toBe(0);
    expect((await get(db, "jos", "p1", storage))?.media).toEqual([]);
  });

  it("the clean-up removes stale uploads and deleted posts' files", async () => {
    const { db, storage } = await setUp();
    await share(db, "anton", "p2", { workoutId: "w2", startedAt: "2026-11-11T18:00:00.000Z", snapshotVersion: 1, snapshot: {} });
    const yesterday = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000);
    await prepareUpload(db, storage, "anton", "p1", "stale", photo, yesterday);
    await db.update(postMedia).set({ createdAt: yesterday });
    await prepareUpload(db, storage, "anton", "p1", "fresh", photo);
    await prepareUpload(db, storage, "anton", "p2", "gone", photo);
    storage.put("users/anton/posts/p2/gone.jpg", 1000);
    await completeUpload(db, storage, "anton", "p2", "gone");
    await remove(db, "anton", "p2");

    expect(await cleanUp(db, storage)).toBe(2);
    expect((await db.select({ id: postMedia.id }).from(postMedia)).map((row) => row.id)).toEqual(["fresh"]);
    expect(storage.deleted).toEqual(expect.arrayContaining(["users/anton/posts/p1/stale.jpg", "users/anton/posts/p2/gone.jpg"]));
  });

  it("deleting an account removes everything under its folder", async () => {
    const storage = new MemoryStorage();
    storage.put("users/anton/posts/p1/m1.jpg", 1);
    storage.put("users/anton/profile/x.jpg", 1);
    storage.put("users/antonia/profile/y.jpg", 1);
    await deleteAccountFiles(storage, "anton");
    expect([...storage.files.keys()]).toEqual(["users/antonia/profile/y.jpg"]);
  });

  it("a deleted post refuses new media", async () => {
    const { db, storage } = await setUp();
    await db.update(post).set({ deletedAt: new Date() });
    await rejects(prepareUpload(db, storage, "anton", "p1", "m1", photo), "deleted");
  });
});
