ALTER TABLE "exercise" ADD COLUMN "measures" text[];--> statement-breakpoint
ALTER TABLE "setting" ADD COLUMN "every_set" boolean DEFAULT false NOT NULL;