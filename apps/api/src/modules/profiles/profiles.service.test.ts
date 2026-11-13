import { describe, expect, it } from "vitest";
import { addUser, testDb } from "../../db/test-db";
import { byHandle, getMine, saveMine, search } from "./profiles.service";

describe("profiles", () => {
  it("has no profile until you pick a handle, then saves it lowercase with public as the default", async () => {
    const db = await testDb();
    await addUser(db, "anton", "Anton");
    expect(await getMine(db, "anton")).toBeNull();

    const mine = await saveMine(db, "anton", { handle: "@Anton.G" });

    expect(mine).toEqual({ userId: "anton", handle: "anton.g", name: "Anton", bio: null, defaultVisibility: "public", relation: "self" });
  });

  it("needs a handle the first time, and rejects bad ones", async () => {
    const db = await testDb();
    await addUser(db, "anton");
    await expect(saveMine(db, "anton", { bio: "hi" })).rejects.toMatchObject({ code: "no_handle" });
    await expect(saveMine(db, "anton", { handle: "ab" })).rejects.toMatchObject({ code: "invalid_handle" });
    await expect(saveMine(db, "anton", { handle: "no spaces" })).rejects.toMatchObject({ code: "invalid_handle" });
    await expect(saveMine(db, "anton", { handle: "anton", defaultVisibility: "everyone" })).rejects.toMatchObject({ code: "invalid_visibility" });
    await expect(saveMine(db, "anton", { handle: "anton", bio: "x".repeat(161) })).rejects.toMatchObject({ code: "invalid_bio" });
  });

  it("won't give two people the same handle, whatever the case", async () => {
    const db = await testDb();
    await addUser(db, "anton");
    await addUser(db, "jos");
    await saveMine(db, "anton", { handle: "lifter" });

    await expect(saveMine(db, "jos", { handle: "LIFTER" })).rejects.toMatchObject({ code: "handle_taken" });
  });

  it("changes only the fields sent, and an empty bio clears it", async () => {
    const db = await testDb();
    await addUser(db, "anton");
    await saveMine(db, "anton", { handle: "anton", bio: "Leg day enjoyer" });

    expect(await saveMine(db, "anton", { defaultVisibility: "friends" })).toMatchObject({ handle: "anton", bio: "Leg day enjoyer", defaultVisibility: "friends" });
    expect(await saveMine(db, "anton", { bio: "" })).toMatchObject({ bio: null });
    expect(await saveMine(db, "anton", { handle: "anton" })).toMatchObject({ handle: "anton" });
  });

  it("finds people by the start of their handle, leaving you out", async () => {
    const db = await testDb();
    for (const [id, handle] of [["anton", "anton"], ["andy", "andy_lifts"], ["andx", "andylifts"], ["jos", "jos"]]) {
      await addUser(db, id!);
      await saveMine(db, id!, { handle });
    }

    expect((await search(db, "anton", "an")).map((p) => p.handle)).toEqual(["andy_lifts", "andylifts"]);
    expect((await search(db, "anton", "@ANDY_")).map((p) => p.handle)).toEqual(["andy_lifts"]);
    expect(await search(db, "anton", "   ")).toEqual([]);
  });

  it("looks someone up by handle and says how they relate to you", async () => {
    const db = await testDb();
    await addUser(db, "anton");
    await addUser(db, "jos", "Jos");
    await saveMine(db, "anton", { handle: "anton" });
    await saveMine(db, "jos", { handle: "jos", bio: "Hi" });

    expect(await byHandle(db, "anton", "JOS")).toEqual({ userId: "jos", handle: "jos", name: "Jos", bio: "Hi", relation: "none" });
    expect(await byHandle(db, "anton", "anton")).toMatchObject({ relation: "self" });
    expect(await byHandle(db, "anton", "nobody")).toBeNull();
  });
});
