import { createApp } from "./app";
import { createDb } from "./db/client";
import type { Bindings } from "./env";
import { storageFromEnv } from "./lib/storage/storage";
import { cleanUp } from "./modules/posts/media.service";

const app = createApp();

// The Cloudflare Workers entry point: Hono handles requests, and the daily cron trigger in wrangler.jsonc
// runs the media clean-up. Nothing else here knows about Workers.
export default {
  fetch: app.fetch,
  async scheduled(_controller: ScheduledController, env: Bindings, ctx: ExecutionContext) {
    const storage = storageFromEnv(env);
    if (!storage) return;
    const { db, close } = createDb(env.DATABASE_URL);
    ctx.waitUntil(
      cleanUp(db, storage)
        .then((removed) => console.log(`Media clean-up removed ${removed} file(s)`))
        .finally(() => close()),
    );
  },
} satisfies ExportedHandler<Bindings>;
