CREATE SEQUENCE "public"."sync_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1;--> statement-breakpoint
CREATE TABLE "exercise" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"name" text NOT NULL,
	"equipment" text NOT NULL,
	"is_builtin" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "exercise_brand" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"exercise_id" text NOT NULL,
	"brand" text,
	"label" text
);
--> statement-breakpoint
CREATE TABLE "exercise_muscle" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"exercise_id" text NOT NULL,
	"muscle" text NOT NULL,
	"share" double precision NOT NULL
);
--> statement-breakpoint
CREATE TABLE "routine" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"name" text NOT NULL,
	"position" double precision NOT NULL
);
--> statement-breakpoint
CREATE TABLE "routine_exercise" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"routine_id" text NOT NULL,
	"exercise_brand_id" text NOT NULL,
	"position" double precision NOT NULL,
	"rest_seconds" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "routine_exercise_setting" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"routine_exercise_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision,
	"text_value" text
);
--> statement-breakpoint
CREATE TABLE "routine_set" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"routine_exercise_id" text NOT NULL,
	"position" double precision NOT NULL,
	"kind" text NOT NULL,
	"set_type" text NOT NULL,
	"weight_kg" double precision,
	"reps" integer,
	"duration_seconds" integer
);
--> statement-breakpoint
CREATE TABLE "routine_set_override" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"routine_set_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision NOT NULL
);
--> statement-breakpoint
CREATE TABLE "setting" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"exercise_brand_id" text NOT NULL,
	"name" text NOT NULL,
	"kind" text NOT NULL,
	"value" double precision,
	"text_value" text,
	"direction" text,
	"range_min" double precision,
	"range_max" double precision,
	"split_by_value" integer NOT NULL,
	"factor" double precision,
	"position" double precision NOT NULL
);
--> statement-breakpoint
CREATE TABLE "workout" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"title" text NOT NULL,
	"note" text,
	"started_at" bigint NOT NULL,
	"finished_at" bigint,
	"routine_id" text
);
--> statement-breakpoint
CREATE TABLE "workout_exercise" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"workout_id" text NOT NULL,
	"exercise_brand_id" text NOT NULL,
	"position" double precision NOT NULL,
	"rest_seconds" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "workout_exercise_note" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"workout_exercise_id" text NOT NULL,
	"position" double precision NOT NULL,
	"text" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "workout_exercise_setting" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"workout_exercise_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision,
	"text_value" text
);
--> statement-breakpoint
CREATE TABLE "workout_set" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"workout_exercise_id" text NOT NULL,
	"position" double precision NOT NULL,
	"kind" text NOT NULL,
	"set_type" text NOT NULL,
	"weight_kg" double precision,
	"reps" integer,
	"duration_seconds" integer,
	"rpe" double precision,
	"completed_at" bigint
);
--> statement-breakpoint
CREATE TABLE "workout_set_override" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"server_seq" bigint DEFAULT nextval('sync_seq') NOT NULL,
	"workout_set_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision NOT NULL
);
--> statement-breakpoint
ALTER TABLE "exercise" ADD CONSTRAINT "exercise_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_brand" ADD CONSTRAINT "exercise_brand_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_muscle" ADD CONSTRAINT "exercise_muscle_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine" ADD CONSTRAINT "routine_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_exercise" ADD CONSTRAINT "routine_exercise_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_exercise_setting" ADD CONSTRAINT "routine_exercise_setting_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_set" ADD CONSTRAINT "routine_set_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_set_override" ADD CONSTRAINT "routine_set_override_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "setting" ADD CONSTRAINT "setting_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout" ADD CONSTRAINT "workout_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_exercise" ADD CONSTRAINT "workout_exercise_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_exercise_note" ADD CONSTRAINT "workout_exercise_note_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_exercise_setting" ADD CONSTRAINT "workout_exercise_setting_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_set" ADD CONSTRAINT "workout_set_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_set_override" ADD CONSTRAINT "workout_set_override_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "exercise_user_seq_idx" ON "exercise" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "exercise_seq_idx" ON "exercise" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "exercise_brand_user_seq_idx" ON "exercise_brand" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "exercise_brand_seq_idx" ON "exercise_brand" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "exercise_muscle_user_seq_idx" ON "exercise_muscle" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "exercise_muscle_seq_idx" ON "exercise_muscle" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "routine_user_seq_idx" ON "routine" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "routine_seq_idx" ON "routine" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "routine_exercise_user_seq_idx" ON "routine_exercise" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "routine_exercise_seq_idx" ON "routine_exercise" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "routine_exercise_setting_user_seq_idx" ON "routine_exercise_setting" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "routine_exercise_setting_seq_idx" ON "routine_exercise_setting" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "routine_set_user_seq_idx" ON "routine_set" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "routine_set_seq_idx" ON "routine_set" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "routine_set_override_user_seq_idx" ON "routine_set_override" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "routine_set_override_seq_idx" ON "routine_set_override" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "setting_user_seq_idx" ON "setting" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "setting_seq_idx" ON "setting" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "workout_user_seq_idx" ON "workout" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "workout_seq_idx" ON "workout" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "workout_exercise_user_seq_idx" ON "workout_exercise" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "workout_exercise_seq_idx" ON "workout_exercise" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "workout_exercise_note_user_seq_idx" ON "workout_exercise_note" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "workout_exercise_note_seq_idx" ON "workout_exercise_note" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "workout_exercise_setting_user_seq_idx" ON "workout_exercise_setting" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "workout_exercise_setting_seq_idx" ON "workout_exercise_setting" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "workout_set_user_seq_idx" ON "workout_set" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "workout_set_seq_idx" ON "workout_set" USING btree ("server_seq");--> statement-breakpoint
CREATE INDEX "workout_set_override_user_seq_idx" ON "workout_set_override" USING btree ("user_id","server_seq");--> statement-breakpoint
CREATE UNIQUE INDEX "workout_set_override_seq_idx" ON "workout_set_override" USING btree ("server_seq");