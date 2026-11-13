import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import type { Database } from "../../db/client";
import { friendship, profile, user } from "../../db/schema";
import { addUser, testDb } from "../../db/test-db";
import { accept, list, remove, request } from "./friends.service";

async function people(...ids: string[]) {
  const db = await testDb();
  for (const id of ids) {
    await addUser(db, id);
    await db.insert(profile).values({ userId: id, handle: id });
  }
  return db;
}

async function rows(db: Database) {
  return db.select().from(friendship);
}

describe("friends", () => {
  it("sends a request, and accepting it makes you friends both ways", async () => {
    const db = await people("anton", "jos");

    expect(await request(db, "anton", "jos")).toBe("outgoing");
    expect((await list(db, "jos")).map((f) => [f.handle, f.relation])).toEqual([["anton", "incoming"]]);

    expect(await accept(db, "jos", "anton")).toBe("friends");
    expect((await list(db, "anton")).map((f) => [f.handle, f.relation])).toEqual([["jos", "friends"]]);
    expect((await list(db, "jos")).map((f) => [f.handle, f.relation])).toEqual([["anton", "friends"]]);
  });

  it("accepts instead when they already asked you, so there's still one row", async () => {
    const db = await people("anton", "jos");
    await request(db, "anton", "jos");

    expect(await request(db, "jos", "anton")).toBe("friends");
    expect(await rows(db)).toHaveLength(1);
  });

  it("asking twice changes nothing", async () => {
    const db = await people("anton", "jos");
    await request(db, "anton", "jos");

    expect(await request(db, "anton", "jos")).toBe("outgoing");
    expect(await rows(db)).toHaveLength(1);
  });

  it("only the person asked can accept", async () => {
    const db = await people("anton", "jos");
    await request(db, "anton", "jos");

    await expect(accept(db, "anton", "jos")).rejects.toMatchObject({ code: "no_request" });
  });

  it("declining, taking back or unfriending deletes the row, so either can ask again", async () => {
    const db = await people("anton", "jos");
    await request(db, "anton", "jos");
    await remove(db, "jos", "anton");
    expect(await rows(db)).toHaveLength(0);

    expect(await request(db, "jos", "anton")).toBe("outgoing");
    await accept(db, "anton", "jos");
    await remove(db, "anton", "jos");
    expect(await list(db, "jos")).toEqual([]);
  });

  it("won't add yourself, someone without a handle, or anyone before you have one", async () => {
    const db = await people("anton");
    await addUser(db, "nohandle");

    await expect(request(db, "anton", "anton")).rejects.toMatchObject({ code: "self" });
    await expect(request(db, "anton", "nohandle")).rejects.toMatchObject({ code: "not_found" });
    await expect(request(db, "nohandle", "anton")).rejects.toMatchObject({ code: "no_profile" });
  });

  it("the database refuses a second row for the same pair, whichever way round", async () => {
    const db = await people("anton", "jos");
    await db.insert(friendship).values({ id: "a", requesterId: "anton", addresseeId: "jos" });

    await expect(db.insert(friendship).values({ id: "b", requesterId: "jos", addresseeId: "anton" })).rejects.toThrow();
  });

  it("lists friends first, then requests to you, then requests you sent", async () => {
    const db = await people("anton", "bea", "cal", "dan");
    await request(db, "anton", "bea");
    await request(db, "cal", "anton");
    await request(db, "dan", "anton");
    await accept(db, "anton", "dan");

    expect((await list(db, "anton")).map((f) => `${f.handle} ${f.relation}`)).toEqual(["dan friends", "cal incoming", "bea outgoing"]);
  });

  it("deleting an account removes its friendships and profile", async () => {
    const db = await people("anton", "jos");
    await request(db, "anton", "jos");

    await db.delete(user).where(eq(user.id, "anton"));

    expect(await rows(db)).toHaveLength(0);
    expect(await db.select().from(profile).where(eq(profile.userId, "anton"))).toHaveLength(0);
  });
});
