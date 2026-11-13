import { and, asc, eq, or } from "drizzle-orm";
import type { Database } from "../../db/client";
import { friendship, profile, user } from "../../db/schema";
import { friendshipBetween, relationFrom, type Relation } from "../../lib/friendship";

/** A friend or a request, as it shows in a list. */
export type FriendRow = {
  userId: string;
  handle: string;
  name: string;
  relation: Relation;
  /** When the request was sent, or when it was accepted for a friend. */
  since: Date;
};

export class FriendError extends Error {
  constructor(
    readonly code: "not_found" | "self" | "no_profile" | "no_request",
    message: string,
  ) {
    super(message);
  }
}

/**
 * Sends a friend request to `otherId`. If they already sent you one, this accepts it instead, so two
 * people tapping "Add" at the same time end up friends. Asking again changes nothing.
 */
export async function request(db: Database, me: string, otherId: string): Promise<Relation> {
  if (me === otherId) throw new FriendError("self", "You can't add yourself.");
  const [mine] = await db.select({ userId: profile.userId }).from(profile).where(eq(profile.userId, me));
  if (!mine) throw new FriendError("no_profile", "Pick a handle before adding friends.");
  const [theirs] = await db.select({ userId: profile.userId }).from(profile).where(eq(profile.userId, otherId));
  if (!theirs) throw new FriendError("not_found", "There's nobody with that handle.");

  const existing = await friendshipBetween(db, me, otherId);
  if (existing) {
    if (existing.status === "pending" && existing.addresseeId === me) return accept(db, me, otherId);
    return relationFrom(me, otherId, existing);
  }
  // The unique index on the pair stops a second row if both send at the same moment.
  await db
    .insert(friendship)
    .values({ id: crypto.randomUUID(), requesterId: me, addresseeId: otherId })
    .onConflictDoNothing();
  return relationFrom(me, otherId, await friendshipBetween(db, me, otherId));
}

/** Accepts the request `otherId` sent you. */
export async function accept(db: Database, me: string, otherId: string): Promise<Relation> {
  const updated = await db
    .update(friendship)
    .set({ status: "accepted", respondedAt: new Date() })
    .where(and(eq(friendship.requesterId, otherId), eq(friendship.addresseeId, me), eq(friendship.status, "pending")))
    .returning({ id: friendship.id });
  if (updated.length === 0) {
    const existing = await friendshipBetween(db, me, otherId);
    if (existing?.status === "accepted") return "friends";
    throw new FriendError("no_request", "There's no request from them to accept.");
  }
  return "friends";
}

/**
 * Ends whatever is between you and `otherId`: declines their request, takes back yours, or unfriends.
 * The row is deleted, so either of you can ask again later.
 */
export async function remove(db: Database, me: string, otherId: string) {
  await db
    .delete(friendship)
    .where(
      or(
        and(eq(friendship.requesterId, me), eq(friendship.addresseeId, otherId)),
        and(eq(friendship.requesterId, otherId), eq(friendship.addresseeId, me)),
      ),
    );
}

/**
 * Your friends, then requests sent to you, then requests you sent, each sorted by handle.
 * The app splits them by `relation`.
 */
export async function list(db: Database, me: string): Promise<FriendRow[]> {
  const rows = await db
    .select({
      requesterId: friendship.requesterId,
      addresseeId: friendship.addresseeId,
      status: friendship.status,
      createdAt: friendship.createdAt,
      respondedAt: friendship.respondedAt,
      handle: profile.handle,
      name: user.name,
    })
    .from(friendship)
    .innerJoin(
      profile,
      or(
        and(eq(friendship.requesterId, me), eq(profile.userId, friendship.addresseeId)),
        and(eq(friendship.addresseeId, me), eq(profile.userId, friendship.requesterId)),
      ),
    )
    .innerJoin(user, eq(user.id, profile.userId))
    .where(or(eq(friendship.requesterId, me), eq(friendship.addresseeId, me)))
    .orderBy(asc(profile.handle));

  const order: Relation[] = ["friends", "incoming", "outgoing"];
  return rows
    .map((row) => {
      const userId = row.requesterId === me ? row.addresseeId : row.requesterId;
      return {
        userId,
        handle: row.handle,
        name: row.name,
        relation: relationFrom(me, userId, row),
        since: row.respondedAt ?? row.createdAt,
      };
    })
    .sort((a, b) => order.indexOf(a.relation) - order.indexOf(b.relation));
}
