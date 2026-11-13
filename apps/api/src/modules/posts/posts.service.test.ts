import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import type { Database } from "../../db/client";
import { friendship, post, profile, user } from "../../db/schema";
import { addUser, testDb } from "../../db/test-db";
import { byAuthor, feed, get, pageSize, remove, share, type ShareInput } from "./posts.service";

async function people(...ids: string[]) {
  const db = await testDb();
  for (const id of ids) {
    await addUser(db, id);
    await db.insert(profile).values({ userId: id, handle: id });
  }
  return db;
}

async function befriend(db: Database, a: string, b: string) {
  await db.insert(friendship).values({ id: `${a}-${b}`, requesterId: a, addresseeId: b, status: "accepted" });
}

function workout(overrides: ShareInput = {}): ShareInput {
  return {
    workoutId: "w1",
    startedAt: "2026-11-10T18:00:00.000Z",
    snapshotVersion: 1,
    snapshot: { title: "Leg day", exercises: [] },
    ...overrides,
  };
}

describe("posts", () => {
  it("shares a workout with your profile's default visibility, and says who shared it", async () => {
    const db = await people("anton");
    const shared = await share(db, "anton", "p1", workout({ caption: "  New notch  " }));

    expect(shared).toMatchObject({
      id: "p1",
      author: { userId: "anton", handle: "anton", name: "anton" },
      workoutId: "w1",
      caption: "New notch",
      visibility: "public",
      snapshot: { title: "Leg day", exercises: [] },
    });
  });

  it("sending the same share twice updates the one post", async () => {
    const db = await people("anton");
    await share(db, "anton", "p1", workout());
    await share(db, "anton", "p1", workout({ caption: "Again" }));

    expect(await db.select().from(post)).toHaveLength(1);
    expect((await get(db, "anton", "p1"))?.caption).toBe("Again");
  });

  it("sharing a workout again replaces its post and keeps the first ID", async () => {
    const db = await people("anton");
    await share(db, "anton", "p1", workout());
    const again = await share(db, "anton", "p2", workout({ snapshot: { title: "Leg day, edited" } }));

    expect(again.id).toBe("p1");
    expect(again.snapshot).toEqual({ title: "Leg day, edited" });
    expect(await db.select().from(post)).toHaveLength(1);
  });

  it("refuses bad input, sharing before you have a handle, and someone else's post ID", async () => {
    const db = await people("anton", "jos");
    await addUser(db, "nohandle");
    await share(db, "jos", "theirs", workout());

    await expect(share(db, "nohandle", "p1", workout())).rejects.toMatchObject({ code: "no_profile" });
    await expect(share(db, "anton", "p1", workout({ startedAt: "yesterday" }))).rejects.toMatchObject({ code: "invalid" });
    await expect(share(db, "anton", "p1", workout({ snapshot: [] }))).rejects.toMatchObject({ code: "invalid" });
    await expect(share(db, "anton", "p1", workout({ snapshotVersion: 0 }))).rejects.toMatchObject({ code: "invalid" });
    await expect(share(db, "anton", "p1", workout({ visibility: "everyone" }))).rejects.toMatchObject({ code: "invalid" });
    await expect(share(db, "anton", "p1", workout({ snapshot: { blob: "x".repeat(300_000) } }))).rejects.toMatchObject({ code: "invalid" });
    await expect(share(db, "anton", "theirs", workout())).rejects.toMatchObject({ code: "not_found" });
  });

  it("public posts show to anyone, friends only to friends, private only to you", async () => {
    const db = await people("anton", "jos", "stranger");
    await befriend(db, "anton", "jos");
    await share(db, "anton", "public", workout({ workoutId: "a", visibility: "public" }));
    await share(db, "anton", "friends", workout({ workoutId: "b", visibility: "friends" }));
    await share(db, "anton", "private", workout({ workoutId: "c", visibility: "private" }));

    const seenBy = async (viewer: string) => (await byAuthor(db, viewer, "anton")).posts.map((p) => p.id).sort();
    expect(await seenBy("anton")).toEqual(["friends", "private", "public"]);
    expect(await seenBy("jos")).toEqual(["friends", "public"]);
    expect(await seenBy("stranger")).toEqual(["public"]);
    expect(await get(db, "stranger", "friends")).toBeNull();
  });

  it("only the sharer gets the workout ID back", async () => {
    const db = await people("anton", "jos");
    await share(db, "anton", "p1", workout());

    expect((await get(db, "jos", "p1"))?.workoutId).toBeNull();
  });

  it("the feed is your posts and your friends', not strangers' or friends' private ones", async () => {
    const db = await people("anton", "jos", "bea", "stranger");
    await befriend(db, "jos", "anton");
    await befriend(db, "anton", "bea");
    await share(db, "anton", "mine", workout({ workoutId: "1", startedAt: "2026-11-10T10:00:00Z", visibility: "private" }));
    await share(db, "jos", "jos-public", workout({ workoutId: "2", startedAt: "2026-11-11T10:00:00Z" }));
    await share(db, "bea", "bea-friends", workout({ workoutId: "3", startedAt: "2026-11-09T10:00:00Z", visibility: "friends" }));
    await share(db, "bea", "bea-private", workout({ workoutId: "4", startedAt: "2026-11-12T10:00:00Z", visibility: "private" }));
    await share(db, "stranger", "stranger-public", workout({ workoutId: "5" }));

    expect((await feed(db, "anton")).posts.map((p) => p.id)).toEqual(["jos-public", "mine", "bea-friends"]);
  });

  it("pages through the feed without repeating or skipping, even with two workouts at the same time", async () => {
    const db = await people("anton");
    const count = pageSize + 5;
    for (let i = 0; i < count; i++) {
      const startedAt = new Date(Date.UTC(2026, 10, 1 + Math.floor(i / 2))).toISOString();
      await share(db, "anton", `p${String(i).padStart(2, "0")}`, workout({ workoutId: `w${i}`, startedAt }));
    }

    const first = await feed(db, "anton");
    expect(first.posts).toHaveLength(pageSize);
    expect(first.nextCursor).not.toBeNull();
    const second = await feed(db, "anton", first.nextCursor!);
    expect(second.nextCursor).toBeNull();

    const ids = [...first.posts, ...second.posts].map((p) => p.id);
    expect(new Set(ids).size).toBe(count);
    await expect(feed(db, "anton", "not-a-cursor")).rejects.toMatchObject({ code: "invalid" });
  });

  it("a deleted post disappears, and sending it again is refused", async () => {
    const db = await people("anton");
    await share(db, "anton", "p1", workout());
    await remove(db, "anton", "p1");

    expect((await feed(db, "anton")).posts).toEqual([]);
    expect(await get(db, "anton", "p1")).toBeNull();
    await expect(share(db, "anton", "p1", workout())).rejects.toMatchObject({ code: "deleted" });
    expect((await share(db, "anton", "p2", workout())).id).toBe("p2");
  });

  it("only the sharer can delete a post", async () => {
    const db = await people("anton", "jos");
    await share(db, "anton", "p1", workout());
    await remove(db, "jos", "p1");

    expect(await get(db, "anton", "p1")).not.toBeNull();
  });

  it("unfriending hides friends only posts again", async () => {
    const db = await people("anton", "jos");
    await befriend(db, "anton", "jos");
    await share(db, "anton", "p1", workout({ visibility: "friends" }));
    await db.delete(friendship);

    expect(await get(db, "jos", "p1")).toBeNull();
    expect((await feed(db, "jos")).posts).toEqual([]);
  });

  it("deleting an account removes its posts", async () => {
    const db = await people("anton");
    await share(db, "anton", "p1", workout());
    await db.delete(user).where(eq(user.id, "anton"));

    expect(await db.select().from(post)).toHaveLength(0);
  });
});
