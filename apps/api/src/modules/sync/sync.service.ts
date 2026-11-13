import { and, eq, getTableColumns, gt, inArray, sql } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import type * as schema from "../../db/schema";
import { type SyncTableName, syncTableNames, syncTables } from "../../db/schema/sync";

/**
 * Bumped when a synced table gains or loses a column in a way old apps can't handle. A phone sends the
 * version it was built against; an older one is told to update rather than given rows it can't read.
 */
export const SYNC_SCHEMA_VERSION = 1;

/** The most rows one pull returns, and the most one push accepts. */
export const MAX_PAGE = 500;
export const MAX_PUSH = 2000;

/**
 * How far ahead of the server a row's `updated_at` may be. A phone with its clock set wrong would
 * otherwise win every conflict for as long as it's ahead, so anything further out is clamped to now.
 */
export const CLOCK_SKEW_MS = 5 * 60 * 1000;

/** Any Drizzle Postgres database, so the service runs on postgres.js in production and PGlite in tests. */
export type SyncDb = PgDatabase<PgQueryResultHKT, typeof schema>;

export type RowValue = string | number | null;
/** A row as the phone stores it: snake_case columns, with `id`, `updated_at` and `deleted_at`. */
export type SyncRow = { id: string; updated_at: number; deleted_at: number | null } & Record<string, RowValue>;
export type Change = { table: SyncTableName; row: SyncRow };

/** `updated_at` is what the server stored, which differs from what was sent only when it was clamped. */
export type Accepted = { table: SyncTableName; id: string; updated_at: number };
export type Rejected = { table: string; id: string | null; reason: string };
export type PushResult = { accepted: Accepted[]; rejected: Rejected[] };
export type PullResult = { rows: { table: SyncTableName; seq: number; row: SyncRow }[]; next: number; hasMore: boolean };

export function isSyncTable(name: unknown): name is SyncTableName {
  return typeof name === "string" && Object.hasOwn(syncTables, name);
}

type AnyTable = (typeof syncTables)[SyncTableName];

/** The columns the phone never sends: the server owns them. */
const serverColumns = new Set(["user_id", "server_seq"]);

/**
 * Checks a row against its table and returns it keyed for Drizzle, or the reason it's unusable.
 * Every column of the table ends up present, so a batch insert has the same shape on every row.
 */
function prepare(table: AnyTable, row: Record<string, unknown>, userId: string): { values: Record<string, unknown> } | { reason: string } {
  const columns = getTableColumns(table);
  const byName = new Map(Object.entries(columns).map(([key, column]) => [column.name, { key, column }]));
  const values: Record<string, unknown> = {};

  for (const [name, value] of Object.entries(row)) {
    const found = byName.get(name);
    if (!found || serverColumns.has(name)) return { reason: `Unknown column ${name}.` };
    if (value === null || value === undefined) {
      if (found.column.notNull) return { reason: `${name} can't be empty.` };
      values[found.key] = null;
      continue;
    }
    if (found.column.dataType === "string" && typeof value !== "string") return { reason: `${name} must be text.` };
    if (found.column.dataType === "number" && (typeof value !== "number" || !Number.isFinite(value))) return { reason: `${name} must be a number.` };
    if (found.column.columnType.includes("Int") && !Number.isInteger(value)) return { reason: `${name} must be a whole number.` };
    values[found.key] = value;
  }
  for (const [name, { key, column }] of byName) {
    if (serverColumns.has(name) || key in values) continue;
    if (column.notNull) return { reason: `${name} is missing.` };
    values[key] = null;
  }
  if (typeof values.id !== "string" || values.id === "") return { reason: "id is missing." };
  values.userId = userId;
  values.serverSeq = sql`nextval('sync_seq')`;
  return { values };
}

/**
 * Applies a device's changed rows, newest `updated_at` winning.
 *
 * Everything happens in one transaction under a per-user lock, so two phones on the same account
 * never interleave and the sequence numbers a user sees are in commit order. A row whose id already
 * belongs to someone else is rejected on its own; the rest of the batch still goes through. A row
 * older than the server's copy is accepted but changes nothing: the pull brings the device up to date.
 */
export async function push(db: SyncDb, userId: string, changes: { table: string; row: unknown }[], now = Date.now()): Promise<PushResult> {
  const accepted: Accepted[] = [];
  const rejected: Rejected[] = [];

  // Newest first per row, so one statement never updates the same id twice.
  const latest = new Map<SyncTableName, Map<string, SyncRow>>();
  for (const change of changes) {
    const row = change.row && typeof change.row === "object" ? { ...(change.row as Partial<SyncRow>) } : null;
    const id = row && typeof row.id === "string" ? row.id : null;
    if (!isSyncTable(change.table)) {
      rejected.push({ table: String(change.table), id, reason: "Unknown table." });
      continue;
    }
    if (!row || id === null) {
      rejected.push({ table: change.table, id: null, reason: "id is missing." });
      continue;
    }
    if (typeof row.updated_at === "number" && row.updated_at > now + CLOCK_SKEW_MS) {
      row.updated_at = now;
      if (typeof row.deleted_at === "number" && row.deleted_at > now) row.deleted_at = now;
    }
    const rows = latest.get(change.table) ?? new Map<string, SyncRow>();
    const seen = rows.get(id);
    if (!seen || (typeof row.updated_at === "number" && row.updated_at > seen.updated_at)) rows.set(id, row as SyncRow);
    latest.set(change.table, rows);
  }

  await db.transaction(async (tx) => {
    await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${userId}))`);
    for (const name of syncTableNames) {
      const rows = latest.get(name);
      if (!rows) continue;
      const table = syncTables[name];

      const owners = await tx
        .select({ id: table.id, userId: table.userId })
        .from(table)
        .where(inArray(table.id, [...rows.keys()]));
      const foreign = new Set(owners.filter((o) => o.userId !== userId).map((o) => o.id));

      const values: Record<string, unknown>[] = [];
      for (const [id, row] of rows) {
        if (foreign.has(id)) {
          rejected.push({ table: name, id, reason: "This row belongs to another account." });
          continue;
        }
        const prepared = prepare(table, row, userId);
        if ("reason" in prepared) {
          rejected.push({ table: name, id, reason: prepared.reason });
          continue;
        }
        values.push(prepared.values);
        accepted.push({ table: name, id, updated_at: row.updated_at });
      }
      if (values.length === 0) continue;

      const set: Record<string, unknown> = {};
      for (const [key, column] of Object.entries(getTableColumns(table))) {
        if (key === "id" || key === "userId") continue;
        set[key] = key === "serverSeq" ? sql`nextval('sync_seq')` : sql.raw(`excluded."${column.name}"`);
      }
      await tx
        .insert(table)
        .values(values as never)
        .onConflictDoUpdate({
          target: table.id,
          set,
          // Last writer wins. On a tie the server keeps what it has, so every device lands on the same row.
          setWhere: sql`${table.updatedAt} < excluded."updated_at"`,
        });
    }
  });

  return { accepted, rejected };
}

/**
 * Rows of this user with a sequence number after `since`, oldest first, at most `limit` of them.
 * `next` is the cursor to send next time; `hasMore` says to call again straight away.
 */
export async function pull(db: SyncDb, userId: string, since: number, limit = MAX_PAGE): Promise<PullResult> {
  const pageSize = Math.max(1, Math.min(limit, MAX_PAGE));
  const all: PullResult["rows"] = [];

  for (const name of syncTableNames) {
    const table = syncTables[name];
    const columns = getTableColumns(table);
    const rows = await db
      .select()
      .from(table)
      .where(and(eq(table.userId, userId), gt(table.serverSeq, since)))
      .orderBy(table.serverSeq)
      .limit(pageSize + 1);
    for (const stored of rows as Record<string, RowValue>[]) {
      const row: Record<string, RowValue> = {};
      for (const [key, column] of Object.entries(columns)) {
        if (serverColumns.has(column.name)) continue;
        row[column.name] = stored[key] ?? null;
      }
      all.push({ table: name, seq: Number(stored.serverSeq), row: row as SyncRow });
    }
  }

  all.sort((a, b) => a.seq - b.seq);
  const page = all.slice(0, pageSize);
  return { rows: page, next: page.length > 0 ? page[page.length - 1].seq : since, hasMore: all.length > pageSize };
}
