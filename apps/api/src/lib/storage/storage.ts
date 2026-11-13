import { AwsClient, AwsV4Signer } from "aws4fetch";
import type { Bindings } from "../../env";

/** A link the phone sends a file to, with the headers it must send exactly. */
export type UploadLink = { url: string; method: "PUT"; headers: Record<string, string>; expiresAt: Date };

/** A link anyone holding it can read one file through, until it expires. */
export type DownloadLink = { url: string; expiresAt: Date };

/**
 * Where photos and videos live. R2 in production, through its S3 API rather than a Workers binding, so
 * the API can move host by changing an endpoint and keys (see the tech stack docs page). Memory in tests.
 *
 * Keys always start with `users/<user id>/`, so deleting an account is one prefix.
 */
export interface MediaStorage {
  /** A link that accepts one upload of exactly this type and size, once. */
  uploadLink(key: string, contentType: string, byteSize: number, expiresInSeconds: number, now?: Date): Promise<UploadLink>;
  downloadLink(key: string, expiresInSeconds: number, now?: Date): Promise<DownloadLink>;
  /** The stored file's size, or null when nothing is there yet. */
  size(key: string): Promise<number | null>;
  delete(key: string): Promise<void>;
  /** Deletes every file whose key starts with `prefix`. */
  deletePrefix(prefix: string): Promise<void>;
}

export type R2Config = { accountId: string; bucket: string; accessKeyId: string; secretAccessKey: string };

/** R2 from the Worker's settings, or null when R2 isn't set up, such as in local dev without keys. */
export function storageFromEnv(env: Partial<Bindings>, fetchFn: typeof fetch = fetch): MediaStorage | null {
  const { R2_ACCOUNT_ID: accountId, R2_BUCKET: bucket, R2_ACCESS_KEY_ID: accessKeyId, R2_SECRET_ACCESS_KEY: secretAccessKey } = env;
  if (!accountId || !bucket || !accessKeyId || !secretAccessKey) return null;
  return new R2Storage({ accountId, bucket, accessKeyId, secretAccessKey }, fetchFn);
}

export class R2Storage implements MediaStorage {
  private readonly client: AwsClient;

  constructor(
    private readonly config: R2Config,
    private readonly fetchFn: typeof fetch = fetch,
  ) {
    this.client = new AwsClient({ accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey, service: "s3", region: "auto" });
  }

  private objectURL(key: string) {
    const path = key.split("/").map(encodeURIComponent).join("/");
    return `https://${this.config.accountId}.r2.cloudflarestorage.com/${encodeURIComponent(this.config.bucket)}/${path}`;
  }

  async uploadLink(key: string, contentType: string, byteSize: number, expiresInSeconds: number, now = new Date()): Promise<UploadLink> {
    // Signing the type and length makes R2 refuse any other upload, so the size the phone declared is the
    // size stored. `if-none-match: *` means the file can only be written once.
    const headers = { "content-type": contentType, "content-length": String(byteSize), "if-none-match": "*" };
    const url = new URL(this.objectURL(key));
    url.searchParams.set("X-Amz-Expires", String(expiresInSeconds));
    const signed = await new AwsV4Signer({
      method: "PUT",
      url: url.toString(),
      headers,
      accessKeyId: this.config.accessKeyId,
      secretAccessKey: this.config.secretAccessKey,
      service: "s3",
      region: "auto",
      signQuery: true,
      // aws4fetch leaves content-type and content-length out of the signature unless told otherwise.
      allHeaders: true,
      datetime: amzDate(now),
    }).sign();
    return { url: signed.url.toString(), method: "PUT", headers, expiresAt: new Date(now.getTime() + expiresInSeconds * 1000) };
  }

  async downloadLink(key: string, expiresInSeconds: number, now = new Date()): Promise<DownloadLink> {
    const url = new URL(this.objectURL(key));
    url.searchParams.set("X-Amz-Expires", String(expiresInSeconds));
    const signed = await new AwsV4Signer({
      method: "GET",
      url: url.toString(),
      accessKeyId: this.config.accessKeyId,
      secretAccessKey: this.config.secretAccessKey,
      service: "s3",
      region: "auto",
      signQuery: true,
      datetime: amzDate(now),
    }).sign();
    return { url: signed.url.toString(), expiresAt: new Date(now.getTime() + expiresInSeconds * 1000) };
  }

  async size(key: string) {
    const res = await this.send(this.objectURL(key), { method: "HEAD" });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`R2 HEAD ${key} answered ${res.status}`);
    return Number(res.headers.get("content-length"));
  }

  async delete(key: string) {
    const res = await this.send(this.objectURL(key), { method: "DELETE" });
    if (!res.ok && res.status !== 404) throw new Error(`R2 DELETE ${key} answered ${res.status}`);
  }

  async deletePrefix(prefix: string) {
    let token: string | undefined;
    do {
      const url = new URL(`https://${this.config.accountId}.r2.cloudflarestorage.com/${encodeURIComponent(this.config.bucket)}`);
      url.searchParams.set("list-type", "2");
      url.searchParams.set("prefix", prefix);
      if (token) url.searchParams.set("continuation-token", token);
      const res = await this.send(url.toString(), { method: "GET" });
      if (!res.ok) throw new Error(`R2 list ${prefix} answered ${res.status}`);
      const listing = parseListing(await res.text());
      for (const key of listing.keys) await this.delete(key);
      token = listing.next;
    } while (token);
  }

  private async send(url: string, init: RequestInit) {
    const signed = await this.client.sign(url, init);
    return this.fetchFn(signed);
  }
}

/** The keys and continuation token from an S3 ListObjectsV2 answer. */
export function parseListing(xml: string): { keys: string[]; next?: string } {
  const unescape = (text: string) =>
    text.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&");
  const keys = [...xml.matchAll(/<Key>([^<]*)<\/Key>/g)].map((match) => unescape(match[1]!));
  const truncated = /<IsTruncated>true<\/IsTruncated>/.test(xml);
  const next = xml.match(/<NextContinuationToken>([^<]*)<\/NextContinuationToken>/)?.[1];
  return { keys, next: truncated && next ? unescape(next) : undefined };
}

/** ISO 8601 basic, as SigV4 wants it: 20261113T081500Z. */
function amzDate(date: Date) {
  return date.toISOString().replace(/[:-]|\.\d{3}/g, "");
}

/** Files in memory, for tests. `put` stands in for the phone's upload. */
export class MemoryStorage implements MediaStorage {
  readonly files = new Map<string, number>();
  readonly deleted: string[] = [];

  put(key: string, byteSize: number) {
    this.files.set(key, byteSize);
  }

  async uploadLink(key: string, contentType: string, byteSize: number, expiresInSeconds: number, now = new Date()): Promise<UploadLink> {
    return {
      url: `https://storage.test/${key}?upload`,
      method: "PUT",
      headers: { "content-type": contentType, "content-length": String(byteSize), "if-none-match": "*" },
      expiresAt: new Date(now.getTime() + expiresInSeconds * 1000),
    };
  }

  async downloadLink(key: string, expiresInSeconds: number, now = new Date()): Promise<DownloadLink> {
    return { url: `https://storage.test/${key}`, expiresAt: new Date(now.getTime() + expiresInSeconds * 1000) };
  }

  async size(key: string) {
    return this.files.get(key) ?? null;
  }

  async delete(key: string) {
    this.files.delete(key);
    this.deleted.push(key);
  }

  async deletePrefix(prefix: string) {
    for (const key of [...this.files.keys()]) if (key.startsWith(prefix)) await this.delete(key);
  }
}
