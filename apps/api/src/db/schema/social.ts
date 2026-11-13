import { sql } from "drizzle-orm";
import { check, index, integer, jsonb, pgTable, text, timestamp, uniqueIndex } from "drizzle-orm/pg-core";
import { user } from "./auth";

// Social tables. They live on the server only and never go through sync, as the Social docs page explains.

export const visibilities = ["public", "friends", "private"] as const;
export type Visibility = (typeof visibilities)[number];

/** Someone's handle, bio and default post visibility. The display name stays on `user.name`. */
export const profile = pgTable(
  "profile",
  {
    userId: text("user_id")
      .primaryKey()
      .references(() => user.id, { onDelete: "cascade" }),
    handle: text("handle").notNull().unique(),
    bio: text("bio"),
    photoKey: text("photo_key"),
    defaultVisibility: text("default_visibility", { enum: visibilities }).notNull().default("public"),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    updatedAt: timestamp("updated_at")
      .defaultNow()
      .$onUpdate(() => new Date())
      .notNull(),
  },
  (table) => [
    check("profile_handle_format", sql`${table.handle} ~ '^[a-z0-9_.]{3,20}$'`),
    check("profile_bio_length", sql`char_length(${table.bio}) <= 160`),
  ],
);

/**
 * A friend request, or a friendship once accepted. One row per pair whoever asked first, so the
 * unique index is on the lower and higher of the two IDs. Declining or unfriending deletes the row.
 */
export const friendship = pgTable(
  "friendship",
  {
    id: text("id").primaryKey(),
    requesterId: text("requester_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    addresseeId: text("addressee_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    status: text("status", { enum: ["pending", "accepted"] }).notNull().default("pending"),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    respondedAt: timestamp("responded_at"),
  },
  (table) => [
    uniqueIndex("friendship_pair").on(sql`least(${table.requesterId}, ${table.addresseeId})`, sql`greatest(${table.requesterId}, ${table.addresseeId})`),
    index("friendship_requester_idx").on(table.requesterId),
    index("friendship_addressee_idx").on(table.addresseeId),
    check("friendship_not_self", sql`${table.requesterId} <> ${table.addresseeId}`),
  ],
);

/**
 * A shared workout. The phone makes the ID, so a share made offline can be sent again without making
 * two posts. `snapshot` is the workout as it was when shared; friends never read the synced tables.
 */
export const post = pgTable(
  "post",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    workoutId: text("workout_id"),
    caption: text("caption"),
    snapshot: jsonb("snapshot").notNull(),
    snapshotVersion: integer("snapshot_version").notNull(),
    visibility: text("visibility", { enum: visibilities }).notNull(),
    startedAt: timestamp("started_at").notNull(),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    updatedAt: timestamp("updated_at")
      .defaultNow()
      .$onUpdate(() => new Date())
      .notNull(),
    deletedAt: timestamp("deleted_at"),
  },
  (table) => [
    index("post_feed_idx").on(table.userId, table.startedAt.desc(), table.id.desc()),
    // Sharing a workout again replaces its post, so each workout has at most one live post.
    uniqueIndex("post_workout").on(table.userId, table.workoutId).where(sql`${table.deletedAt} is null and ${table.workoutId} is not null`),
    check("post_caption_length", sql`char_length(${table.caption}) <= 2000`),
  ],
);
