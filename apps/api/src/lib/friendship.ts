import { and, eq, or } from "drizzle-orm";
import type { Database } from "../db/client";
import { friendship } from "../db/schema";

/**
 * How someone relates to you: yourself, a friend, a request either way, or nobody yet.
 * Profiles and friends both need it, so it lives here rather than in either module.
 */
export type Relation = "self" | "friends" | "incoming" | "outgoing" | "none";

/** The friendship row between two people, whichever of them sent the request. */
export async function friendshipBetween(db: Database, a: string, b: string) {
  const [row] = await db
    .select()
    .from(friendship)
    .where(
      or(
        and(eq(friendship.requesterId, a), eq(friendship.addresseeId, b)),
        and(eq(friendship.requesterId, b), eq(friendship.addresseeId, a)),
      ),
    )
    .limit(1);
  return row;
}

/** `row` is the friendship between `me` and someone else, if there is one. */
export function relationFrom(me: string, other: string, row: { requesterId: string; status: string } | undefined): Relation {
  if (me === other) return "self";
  if (!row) return "none";
  if (row.status === "accepted") return "friends";
  return row.requesterId === me ? "outgoing" : "incoming";
}
