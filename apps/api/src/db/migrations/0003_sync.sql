CREATE TABLE "exercise" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"name" text NOT NULL,
	"equipment" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"version" bigint NOT NULL,
	"schema" integer NOT NULL,
	CONSTRAINT "exercise_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "exercise_brand" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"exercise_id" text NOT NULL,
	"brand" text,
	"label" text,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"version" bigint NOT NULL,
	"schema" integer NOT NULL,
	CONSTRAINT "exercise_brand_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "exercise_muscle" (
	"user_id" text NOT NULL,
	"exercise_id" text NOT NULL,
	"muscle" text NOT NULL,
	"share" double precision NOT NULL,
	CONSTRAINT "exercise_muscle_user_id_exercise_id_muscle_pk" PRIMARY KEY("user_id","exercise_id","muscle")
);
--> statement-breakpoint
CREATE TABLE "routine" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"name" text NOT NULL,
	"position" double precision NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"version" bigint NOT NULL,
	"schema" integer NOT NULL,
	CONSTRAINT "routine_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "routine_exercise" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"routine_id" text NOT NULL,
	"exercise_brand_id" text NOT NULL,
	"position" double precision NOT NULL,
	"rest_seconds" integer NOT NULL,
	CONSTRAINT "routine_exercise_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "routine_exercise_setting" (
	"user_id" text NOT NULL,
	"routine_exercise_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision,
	"text_value" text,
	CONSTRAINT "routine_exercise_setting_user_id_routine_exercise_id_setting_id_pk" PRIMARY KEY("user_id","routine_exercise_id","setting_id")
);
--> statement-breakpoint
CREATE TABLE "routine_set" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"routine_exercise_id" text NOT NULL,
	"position" double precision NOT NULL,
	"kind" text NOT NULL,
	"set_type" text DEFAULT 'normal' NOT NULL,
	"weight_kg" double precision,
	"reps" integer,
	"duration_seconds" integer,
	CONSTRAINT "routine_set_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "routine_set_override" (
	"user_id" text NOT NULL,
	"routine_set_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision NOT NULL,
	CONSTRAINT "routine_set_override_user_id_routine_set_id_setting_id_pk" PRIMARY KEY("user_id","routine_set_id","setting_id")
);
--> statement-breakpoint
CREATE TABLE "setting" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"exercise_brand_id" text NOT NULL,
	"name" text NOT NULL,
	"kind" text NOT NULL,
	"value" double precision,
	"text_value" text,
	"direction" text,
	"range_min" double precision,
	"range_max" double precision,
	"split_by_value" boolean DEFAULT false NOT NULL,
	"factor" double precision,
	"position" double precision NOT NULL,
	"deleted_at" bigint,
	CONSTRAINT "setting_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "sync_account" (
	"user_id" text PRIMARY KEY NOT NULL,
	"version" bigint DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE "user_setting" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"weight_unit" text NOT NULL,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"version" bigint NOT NULL,
	"schema" integer NOT NULL,
	CONSTRAINT "user_setting_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "workout" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"title" text NOT NULL,
	"note" text,
	"started_at" bigint NOT NULL,
	"finished_at" bigint NOT NULL,
	"routine_id" text,
	"import_key" text,
	"gym_name" text,
	"gym_address" text,
	"gym_latitude" double precision,
	"gym_longitude" double precision,
	"updated_at" bigint NOT NULL,
	"deleted_at" bigint,
	"version" bigint NOT NULL,
	"schema" integer NOT NULL,
	CONSTRAINT "workout_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "workout_exercise" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"workout_id" text NOT NULL,
	"exercise_brand_id" text NOT NULL,
	"position" double precision NOT NULL,
	"rest_seconds" integer NOT NULL,
	CONSTRAINT "workout_exercise_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "workout_exercise_note" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"workout_exercise_id" text NOT NULL,
	"position" double precision NOT NULL,
	"text" text NOT NULL,
	CONSTRAINT "workout_exercise_note_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "workout_exercise_setting" (
	"user_id" text NOT NULL,
	"workout_exercise_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision,
	"text_value" text,
	CONSTRAINT "workout_exercise_setting_user_id_workout_exercise_id_setting_id_pk" PRIMARY KEY("user_id","workout_exercise_id","setting_id")
);
--> statement-breakpoint
CREATE TABLE "workout_set" (
	"user_id" text NOT NULL,
	"id" text NOT NULL,
	"workout_exercise_id" text NOT NULL,
	"position" double precision NOT NULL,
	"kind" text NOT NULL,
	"set_type" text DEFAULT 'normal' NOT NULL,
	"weight_kg" double precision,
	"reps" integer,
	"duration_seconds" integer,
	"rpe" double precision,
	"completed_at" bigint,
	CONSTRAINT "workout_set_user_id_id_pk" PRIMARY KEY("user_id","id")
);
--> statement-breakpoint
CREATE TABLE "workout_set_override" (
	"user_id" text NOT NULL,
	"workout_set_id" text NOT NULL,
	"setting_id" text NOT NULL,
	"value" double precision NOT NULL,
	CONSTRAINT "workout_set_override_user_id_workout_set_id_setting_id_pk" PRIMARY KEY("user_id","workout_set_id","setting_id")
);
--> statement-breakpoint
ALTER TABLE "exercise" ADD CONSTRAINT "exercise_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_brand" ADD CONSTRAINT "exercise_brand_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_muscle" ADD CONSTRAINT "exercise_muscle_user_id_exercise_id_exercise_user_id_id_fk" FOREIGN KEY ("user_id","exercise_id") REFERENCES "public"."exercise"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine" ADD CONSTRAINT "routine_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_exercise" ADD CONSTRAINT "routine_exercise_user_id_routine_id_routine_user_id_id_fk" FOREIGN KEY ("user_id","routine_id") REFERENCES "public"."routine"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_exercise_setting" ADD CONSTRAINT "routine_exercise_setting_user_id_routine_exercise_id_routine_exercise_user_id_id_fk" FOREIGN KEY ("user_id","routine_exercise_id") REFERENCES "public"."routine_exercise"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_set" ADD CONSTRAINT "routine_set_user_id_routine_exercise_id_routine_exercise_user_id_id_fk" FOREIGN KEY ("user_id","routine_exercise_id") REFERENCES "public"."routine_exercise"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "routine_set_override" ADD CONSTRAINT "routine_set_override_user_id_routine_set_id_routine_set_user_id_id_fk" FOREIGN KEY ("user_id","routine_set_id") REFERENCES "public"."routine_set"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "setting" ADD CONSTRAINT "setting_user_id_exercise_brand_id_exercise_brand_user_id_id_fk" FOREIGN KEY ("user_id","exercise_brand_id") REFERENCES "public"."exercise_brand"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_account" ADD CONSTRAINT "sync_account_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_setting" ADD CONSTRAINT "user_setting_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout" ADD CONSTRAINT "workout_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_exercise" ADD CONSTRAINT "workout_exercise_user_id_workout_id_workout_user_id_id_fk" FOREIGN KEY ("user_id","workout_id") REFERENCES "public"."workout"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_exercise_note" ADD CONSTRAINT "workout_exercise_note_user_id_workout_exercise_id_workout_exercise_user_id_id_fk" FOREIGN KEY ("user_id","workout_exercise_id") REFERENCES "public"."workout_exercise"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_exercise_setting" ADD CONSTRAINT "workout_exercise_setting_user_id_workout_exercise_id_workout_exercise_user_id_id_fk" FOREIGN KEY ("user_id","workout_exercise_id") REFERENCES "public"."workout_exercise"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_set" ADD CONSTRAINT "workout_set_user_id_workout_exercise_id_workout_exercise_user_id_id_fk" FOREIGN KEY ("user_id","workout_exercise_id") REFERENCES "public"."workout_exercise"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_set_override" ADD CONSTRAINT "workout_set_override_user_id_workout_set_id_workout_set_user_id_id_fk" FOREIGN KEY ("user_id","workout_set_id") REFERENCES "public"."workout_set"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "exercise_version_idx" ON "exercise" USING btree ("user_id","version");--> statement-breakpoint
CREATE INDEX "exercise_brand_version_idx" ON "exercise_brand" USING btree ("user_id","version");--> statement-breakpoint
CREATE INDEX "routine_version_idx" ON "routine" USING btree ("user_id","version");--> statement-breakpoint
CREATE INDEX "routine_exercise_routine_idx" ON "routine_exercise" USING btree ("user_id","routine_id");--> statement-breakpoint
CREATE INDEX "routine_set_exercise_idx" ON "routine_set" USING btree ("user_id","routine_exercise_id");--> statement-breakpoint
CREATE INDEX "setting_brand_idx" ON "setting" USING btree ("user_id","exercise_brand_id");--> statement-breakpoint
CREATE INDEX "user_setting_version_idx" ON "user_setting" USING btree ("user_id","version");--> statement-breakpoint
CREATE INDEX "workout_version_idx" ON "workout" USING btree ("user_id","version");--> statement-breakpoint
CREATE INDEX "workout_exercise_workout_idx" ON "workout_exercise" USING btree ("user_id","workout_id");--> statement-breakpoint
CREATE INDEX "workout_exercise_note_exercise_idx" ON "workout_exercise_note" USING btree ("user_id","workout_exercise_id");--> statement-breakpoint
CREATE INDEX "workout_set_exercise_idx" ON "workout_set" USING btree ("user_id","workout_exercise_id");