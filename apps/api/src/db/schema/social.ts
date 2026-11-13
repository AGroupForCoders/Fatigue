import { sql } from "drizzle-orm";
import { check, index, integer, jsonb, pgTable, real, text, timestamp, uniqueIndex } from "drizzle-orm/pg-core";
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

export const mediaKinds = ["photo", "video"] as const;
export type MediaKind = (typeof mediaKinds)[number];

/**
 * A photo or video on a post. The phone makes the ID (the same as its own media row), asks for an upload
 * link, sends the file straight to storage, then says it's done. Only `ready` rows show on the post.
 * `removed_at` marks one taken off the post; the daily clean-up deletes its file and the row.
 */
export const postMedia = pgTable(
  "post_media",
  {
    id: text("id").primaryKey(),
    postId: text("post_id")
      .notNull()
      .references(() => post.id, { onDelete: "cascade" }),
    /** The post's author, so files can be found per account without a join. */
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    kind: text("kind", { enum: mediaKinds }).notNull(),
    contentType: text("content_type").notNull(),
    byteSize: integer("byte_size").notNull(),
    objectKey: text("object_key").notNull().unique(),
    width: integer("width"),
    height: integer("height"),
    durationSeconds: real("duration_seconds"),
    position: integer("position").notNull(),
    status: text("status", { enum: ["pending", "ready"] }).notNull().default("pending"),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    removedAt: timestamp("removed_at"),
  },
  (table) => [index("post_media_post_idx").on(table.postId, table.position), index("post_media_status_idx").on(table.status, table.createdAt)],
);
