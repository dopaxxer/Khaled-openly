/* eslint-disable @typescript-eslint/no-explicit-any -- Dynamic SQLite row boundary; all incoming payloads are validated with Zod and client-facing models are typed. */
/* Openly API: all product data and media access pass through these authorization checks. */
import { z } from "zod";
// SQLite rows are dynamic at the database boundary; client DTOs are defined separately.
type Row = Record<string, any>;
export interface Database {
  prepare(sql: string): Statement;
  batch(statements: Statement[]): Promise<any[]>;
}
export interface Statement {
  bind(...values: any[]): Statement;
  first<T = Row>(): Promise<T | null>;
  all<T = Row>(): Promise<{ results: T[] }>;
  run(): Promise<any>;
}
export interface Bucket {
  put(key: string, value: any, options?: any): Promise<any>;
  get(key: string): Promise<any>;
  delete(key: string): Promise<any>;
}
export interface APIEnv {
  DB: Database;
  BUCKET: Bucket;
  RESEND_API_KEY?: string;
  MAIL_FROM?: string;
  PUBLIC_ORIGIN?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  IOS_BUNDLE_ID?: string;
  APNS_SANDBOX?: string;
  MODERATOR_IDS?: string;
}
const encoder = new TextEncoder();
const now = () => Date.now();
const id = () => crypto.randomUUID();
const token = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
const hash = async (s: string) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(s))),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
const fail = (code: string, status = 400): never => {
  throw new APIError(code, status);
};
class APIError extends Error {
  constructor(
    public code: string,
    public status: number,
  ) {
    super(code);
  }
}
const json = (
  data: unknown,
  status = 200,
  headers: Record<string, string> = {},
) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...headers,
    },
  });
const parseJSON = (s: string | null, fallback: any = null) => {
  try {
    return s ? JSON.parse(s) : fallback;
  } catch {
    return fallback;
  }
};
const uidSchema = z.string().uuid();
const interests = z
  .array(
    z.enum([
      "music",
      "art",
      "books",
      "photography",
      "film",
      "everyday",
      "design",
      "science",
      "gaming",
      "travel",
    ]),
  )
  .max(10);
const musicURL = z
  .string()
  .url()
  .max(2000)
  .refine((value) => {
    try {
      const u = new URL(value);
      return (
        u.protocol === "https:" &&
        ["apple.com", "mzstatic.com"].some(
          (host) => u.hostname === host || u.hostname.endsWith("." + host),
        )
      );
    } catch {
      return false;
    }
  }, "Unsupported music URL");
const songSchema = z.object({
  id: z.number().int().positive(),
  title: z.string().max(300),
  artist: z.string().max(300),
  artwork: musicURL,
  url: musicURL,
  preview: musicURL.nullable(),
});
const publicFields =
  "id, username, name, bio, avatar, interests, song, accent, private";
function exposeUser(u: Row, own = false): Row {
  const fields = (
    publicFields +
    (own
      ? ", email, messages, receipts, activity, language, theme, onboarded, notifications"
      : "")
  ).split(", ");
  return Object.fromEntries(
    fields.map((k) => [
      k,
      ["interests", "song", "notifications"].includes(k)
        ? parseJSON(u[k], k === "song" ? null : [])
        : u[k],
    ]),
  );
}
function exposePost(p: Row) {
  return { ...p, song: parseJSON(p.song) };
}
async function passwordHash(password: string, salt = token()) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const out = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt: encoder.encode(salt),
      iterations: 100000,
      hash: "SHA-256",
    },
    key,
    256,
  );
  return (
    salt +
    ":" +
    Array.from(new Uint8Array(out), (b) =>
      b.toString(16).padStart(2, "0"),
    ).join("")
  );
}
function equal(a: string, b: string) {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++)
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return result === 0;
}
const followed = `EXISTS (SELECT 1 FROM follows f WHERE f.follower=v.id AND f.followed=p.author AND f.status='accepted')`;
const unblocked = (a: string, b: string) =>
  `NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker=${a} AND b.blocked=${b}) OR (b.blocker=${b} AND b.blocked=${a}))`;
export const postACL = `(p.expires IS NULL OR p.expires>v.time) AND ${unblocked("p.author", "v.id")} AND (p.circleId IS NULL OR EXISTS (SELECT 1 FROM circles c WHERE c.id=p.circleId AND (c.private=0 OR EXISTS(SELECT 1 FROM members cm WHERE cm.circleId=c.id AND cm.userId=v.id AND cm.status='accepted')))) AND (p.author=v.id OR ((u.private=0 OR ${followed}) AND (p.audience='public' OR (p.audience='followers' AND ${followed}))))`;
class Context {
  user!: Row;
  uid = "";
  constructor(
    public req: Request,
    public env: APIEnv,
  ) {}
  stmt(sql: string, ...args: any[]) {
    return this.env.DB.prepare(sql).bind(...args);
  }
  async one(sql: string, ...args: any[]) {
    return this.stmt(sql, ...args).first<Row>();
  }
  async all(sql: string, ...args: any[]) {
    return (await this.stmt(sql, ...args).all<Row>()).results;
  }
  async run(sql: string, ...args: any[]) {
    return this.stmt(sql, ...args).run();
  }
  async body() {
    if (Number(this.req.headers.get("content-length") || 0) > 30000)
      fail("too_large", 413);
    const t = await this.req.text();
    if (t.length > 30000) fail("too_large", 413);
    try {
      return JSON.parse(t);
    } catch {
      return fail("invalid_request");
    }
  }
  async rate(key: string, max: number, window = 60000) {
    const t = now();
    const r = await this.one(
      "INSERT INTO rate_limits (key,count,expires) VALUES (?,1,?) ON CONFLICT(key) DO UPDATE SET count=CASE WHEN expires<? THEN 1 ELSE count+1 END, expires=CASE WHEN expires<? THEN ? ELSE expires END RETURNING count",
      key,
      t + window,
      t,
      t,
      t + window,
    );
    if (r!.count > max) fail("rate_limited", 429);
  }
  async auth() {
    const bearer = this.req.headers.get("authorization");
    const raw = bearer?.startsWith("Bearer ")
      ? bearer.slice(7)
      : this.req.headers
          .get("cookie")
          ?.match(/(?:^|;\s*)openly_session=([a-f0-9]{64})(?:;|$)/)?.[1];
    if (!raw) fail("sign_in", 401);
    const u = await this.one(
      "SELECT u.* FROM sessions s JOIN users u ON u.id=s.userId WHERE s.token=? AND s.expires>?",
      await hash(raw!),
      now(),
    );
    if (!u) fail("sign_in", 401);
    this.user = u!;
    this.uid = u!.id;
    return raw!;
  }
  async blocked(other: string) {
    return !!(await this.one(
      "SELECT 1 FROM blocks WHERE (blocker=? AND blocked=?) OR (blocker=? AND blocked=?)",
      this.uid,
      other,
      other,
      this.uid,
    ));
  }
  async person(other: string) {
    const u = await this.one(
      "SELECT * FROM users WHERE id=? OR username=?",
      other,
      other,
    );
    if (!u || (await this.blocked(u.id))) fail("unavailable", 404);
    return u!;
  }
  async post(postId: string) {
    const p = await this.one(
      `SELECT p.*,u.username,u.name,u.avatar,u.accent FROM posts p JOIN users u ON u.id=p.author CROSS JOIN (SELECT ? id, ? time) v WHERE p.id=? AND ${postACL}`,
      this.uid,
      now(),
      postId,
    );
    if (!p) fail("unavailable", 404);
    return p!;
  }
  async circle(circleId: string, memberRequired = false, moderator = false) {
    const c = await this.one(
      "SELECT c.*,m.role,m.status FROM circles c LEFT JOIN members m ON m.circleId=c.id AND m.userId=? WHERE c.id=?",
      this.uid,
      circleId,
    );
    if (
      !c ||
      (await this.blocked(c.owner)) ||
      (c.private && c.status !== "accepted") ||
      (memberRequired && c.status !== "accepted") ||
      (moderator &&
        (!["owner", "moderator"].includes(c.role) || c.status !== "accepted"))
    )
      fail("unavailable", 404);
    return c!;
  }
  async conversation(cid: string, accepted = false) {
    const c = await this.one(
      "SELECT * FROM conversations WHERE id=? AND (a=? OR b=?)",
      cid,
      this.uid,
      this.uid,
    );
    if (!c) fail("unavailable", 404);
    const other = c!.a === this.uid ? c!.b : c!.a;
    if (await this.blocked(other)) fail("unavailable", 404);
    if (accepted && c!.status !== "accepted") fail("request_pending", 403);
    return { ...c!, other } as Row;
  }
  async ownMedia(mediaId: string | null | undefined) {
    if (!mediaId) return null;
    uidSchema.parse(mediaId);
    const m = await this.one(
      "SELECT * FROM media WHERE id=? AND owner=?",
      mediaId,
      this.uid,
    );
    if (!m) fail("invalid_media");
    return m!;
  }
  async notification(recipient: string, type: string, target: string) {
    if (recipient === this.uid || (await this.blocked(recipient))) return;
    const n = await this.one(
      "SELECT notifications FROM users WHERE id=?",
      recipient,
    );
    if (!parseJSON(n?.notifications, []).includes(type)) return;
    await this.run(
      "INSERT INTO notifications(id,recipient,actor,type,target,created) VALUES (?,?,?,?,?,?)",
      id(),
      recipient,
      this.uid,
      type,
      target,
      now(),
    );
    if (type === "message") {
      const muted = await this.one(
        "SELECT muted FROM conversation_state WHERE conversationId=? AND userId=?",
        target,
        recipient,
      );
      if (muted?.muted) return;
    }
    await this.push(recipient, type, target);
  }
  async push(recipient: string, type: string, target: string) {
    const e = this.env;
    if (
      !e.APNS_PRIVATE_KEY ||
      !e.APNS_KEY_ID ||
      !e.APNS_TEAM_ID ||
      !e.IOS_BUNDLE_ID
    )
      return;
    try {
      const b64 = (s: string) =>
        btoa(s).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
      const h = b64(JSON.stringify({ alg: "ES256", kid: e.APNS_KEY_ID }));
      const p = b64(
        JSON.stringify({ iss: e.APNS_TEAM_ID, iat: Math.floor(now() / 1000) }),
      );
      const der = Uint8Array.from(
        atob(e.APNS_PRIVATE_KEY.replace(/-----[^-]+-----|\s/g, "")),
        (c) => c.charCodeAt(0),
      );
      const key = await crypto.subtle.importKey(
        "pkcs8",
        der,
        { name: "ECDSA", namedCurve: "P-256" },
        false,
        ["sign"],
      );
      const signature = await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        encoder.encode(h + "." + p),
      );
      const jwt =
        h +
        "." +
        p +
        "." +
        b64(String.fromCharCode(...new Uint8Array(signature)));
      for (const device of await this.all(
        "SELECT token FROM devices WHERE owner=? AND platform=?",
        recipient,
        "ios",
      )) {
        await fetch(
          `https://api${e.APNS_SANDBOX === "true" ? ".sandbox" : ""}.push.apple.com/3/device/${device.token}`,
          {
            method: "POST",
            headers: {
              authorization: `bearer ${jwt}`,
              "apns-topic": e.IOS_BUNDLE_ID,
              "apns-push-type": "alert",
            },
            body: JSON.stringify({
              aps: {
                alert: {
                  title: "Openly",
                  body:
                    (
                      await this.one(
                        "SELECT language FROM users WHERE id=?",
                        recipient,
                      )
                    )?.language === "ar"
                      ? "لديك إشعار جديد."
                      : "You have a new update.",
                },
                sound: "default",
              },
              type,
              target,
            }),
          },
        );
      }
    } catch {
      /* Push failures never fail the committed social action. */
    }
  }
}
async function authRoute(c: Context, path: string) {
  const ip = c.req.headers.get("cf-connecting-ip") || "local";
  await c.rate("auth:" + ip, 12, 60000);
  const data = await c.body();
  if (path === "register") {
    const d = z
      .object({
        email: z.string().email().max(254),
        password: z.string().min(12).max(256),
        username: z.string().regex(/^[a-zA-Z0-9_]{3,24}$/),
        name: z.string().trim().min(1).max(60),
      })
      .parse(data);
    const userId = id(),
      recovery = token();
    try {
      await c.run(
        "INSERT INTO users(id,email,username,password,recovery,name,created) VALUES (?,?,?,?,?,?,?)",
        userId,
        d.email.toLowerCase(),
        d.username.toLowerCase(),
        await passwordHash(d.password),
        await hash(recovery),
        d.name,
        now(),
      );
    } catch (e) {
      if (String(e).includes("UNIQUE")) fail("account_exists", 409);
      throw e;
    }
    const raw = token();
    await c.run(
      "INSERT INTO sessions(token,userId,expires) VALUES (?,?,?)",
      await hash(raw),
      userId,
      now() + 2592000000,
    );
    return sessionResponse(
      c,
      {
        user: exposeUser(
          (await c.one("SELECT * FROM users WHERE id=?", userId))!,
          true,
        ),
        recovery,
      },
      raw,
      201,
    );
  }
  if (path === "login") {
    const d = z
      .object({ email: z.string().max(254), password: z.string().max(256) })
      .parse(data);
    const u = await c.one(
      "SELECT * FROM users WHERE email=?",
      d.email.toLowerCase(),
    );
    const calculated = await passwordHash(
      d.password,
      u?.password.split(":")[0] || "nonexistent-account-timing-salt",
    );
    if (!u || !equal(calculated, u.password)) fail("invalid_credentials", 401);
    const raw = token();
    await c.run(
      "INSERT INTO sessions(token,userId,expires) VALUES (?,?,?)",
      await hash(raw),
      u!.id,
      now() + 2592000000,
    );
    return sessionResponse(c, { user: exposeUser(u!, true) }, raw);
  }
  if (path === "recover") {
    const d = z
      .object({
        email: z.string().email(),
        recovery: z.string().min(32).max(128),
        password: z.string().min(12).max(256),
      })
      .parse(data);
    const u = await c.one(
      "SELECT * FROM users WHERE email=?",
      d.email.toLowerCase(),
    );
    if (!u || !equal(await hash(d.recovery.trim()), u.recovery))
      fail("invalid_recovery", 400);
    const recovery = token();
    await c.env.DB.batch([
      c.stmt(
        "UPDATE users SET password=?, recovery=? WHERE id=?",
        await passwordHash(d.password),
        await hash(recovery),
        u!.id,
      ),
      c.stmt("DELETE FROM sessions WHERE userId=?", u!.id),
    ]);
    return json({ ok: true, recovery });
  }
  return fail("not_found", 404);
}
function sessionResponse(c: Context, data: Row, raw: string, status = 200) {
  const secure = new URL(c.req.url).protocol === "https:" ? "; Secure" : "";
  return json(
    {
      ...data,
      ...(c.req.headers.get("x-openly-client") === "ios" ? { token: raw } : {}),
    },
    status,
    {
      "set-cookie": `openly_session=${raw}; HttpOnly; SameSite=Lax; Path=/; Max-Age=2592000${secure}`,
    },
  );
}
async function feed(c: Context, url: URL, extra = "1=1", args: any[] = []) {
  const kind = url.searchParams.get("kind") || "post";
  const before = Number(url.searchParams.get("before") || now() + 1);
  const cursor = url.searchParams.get("cursor") || "~";
  const limit = Math.min(
    40,
    Math.max(1, Number(url.searchParams.get("limit")) || 20),
  );
  const mode = url.searchParams.get("mode");
  const author = url.searchParams.get("author"),
    circleId = url.searchParams.get("circle");
  let filter = "";
  const more: any[] = [];
  if (author) {
    filter += " AND p.author=?";
    more.push(author);
  }
  if (circleId) {
    await c.circle(circleId);
    filter += " AND p.circleId=?";
    more.push(circleId);
  } else if (!author) {
    filter +=
      " AND (p.circleId IS NULL OR EXISTS (SELECT 1 FROM members fm WHERE fm.circleId=p.circleId AND fm.userId=v.id AND fm.status='accepted'))";
  }
  if (mode === "following") filter += ` AND (p.author=v.id OR ${followed})`;
  const ranked =
    mode === "for-you" &&
    url.searchParams.get("sort") !== "chronological" &&
    !author;
  const relevance = `2*(SELECT count(*) FROM json_each(u.interests) i WHERE i.value IN (SELECT value FROM json_each((SELECT interests FROM users WHERE id=v.id)))) + CASE WHEN EXISTS(SELECT 1 FROM likes il JOIN posts ip ON ip.id=il.postId WHERE il.userId=v.id AND ip.author=p.author) THEN 1 ELSE 0 END`;
  const score = ranked ? relevance : "0";
  const scoreBefore = Number(url.searchParams.get("score") || 10000);
  // Rank + time + ID form one stable cursor. Newly changed interests/interactions intentionally refresh ranking.
  const keyset = ranked
    ? `((${score})<? OR ((${score})=? AND (p.created<? OR (p.created=? AND p.id<?))))`
    : "(p.created<? OR (p.created=? AND p.id<?))";
  const pageArgs = ranked
    ? [scoreBefore, scoreBefore, before, before, cursor]
    : [before, before, cursor];
  const rows = await c.all(
    `SELECT p.*,u.username,u.name,u.avatar,u.accent, (${score}) score, EXISTS(SELECT 1 FROM likes l WHERE l.postId=p.id AND l.userId=v.id) liked,(SELECT count(*) FROM likes l WHERE l.postId=p.id) likes,(SELECT count(*) FROM comments cm WHERE cm.postId=p.id AND ${unblocked("cm.author", "v.id")}) comments,EXISTS(SELECT 1 FROM saves s JOIN collections co ON co.id=s.collectionId WHERE s.postId=p.id AND co.owner=v.id) saved FROM posts p JOIN users u ON u.id=p.author CROSS JOIN (SELECT ? id,? time) v WHERE ${postACL} AND p.kind=? AND ${keyset} AND NOT EXISTS(SELECT 1 FROM hidden h WHERE h.postId=p.id AND h.userId=v.id) AND (${extra}) ${filter} ORDER BY ${ranked ? "score DESC," : ""}p.created DESC,p.id DESC LIMIT ?`,
    c.uid,
    now(),
    kind,
    ...pageArgs,
    ...args,
    ...more,
    limit,
  );
  return json({
    items: rows.map(exposePost),
    next:
      rows.length === limit
        ? {
            before: rows.at(-1)!.created,
            cursor: rows.at(-1)!.id,
            score: rows.at(-1)!.score,
          }
        : null,
  });
}
async function canMedia(c: Context, mid: string) {
  const m = await c.one("SELECT * FROM media WHERE id=?", mid);
  if (!m) fail("unavailable", 404);
  const expired = await c.one(
    "SELECT 1 FROM posts WHERE image=? AND kind=? AND expires<=?",
    mid,
    "moment",
    now(),
  );
  if (expired) fail("unavailable", 404);
  const p = await c.one(
    `SELECT 1 FROM posts p JOIN users u ON u.id=p.author CROSS JOIN (SELECT ? id,? time) v WHERE p.image=? AND ${postACL}`,
    c.uid,
    now(),
    mid,
  );
  if (p) return m!;
  const msg = await c.one(
    "SELECT m.conversationId FROM messages m WHERE m.media=?",
    mid,
  );
  if (msg) {
    await c.conversation(msg.conversationId);
    return m!;
  }
  const avatar = await c.one("SELECT id FROM users WHERE avatar=?", mid);
  if (avatar && !(await c.blocked(avatar.id))) return m!;
  if (m!.owner === c.uid) {
    const linked = await c.one("SELECT 1 FROM posts WHERE image=?", mid);
    if (!linked) return m!;
  }
  fail("unavailable", 404);
}
export async function api(request: Request, env: APIEnv): Promise<Response> {
  const c = new Context(request, env);
  const url = new URL(request.url);
  const parts = url.pathname
    .replace(/^\/api\/?/, "")
    .split("/")
    .filter(Boolean);
  const [resource, target, action] = parts;
  try {
    if (resource === "health")
      return json({ ok: true, service: "openly", version: "1.0.0" });
    if (request.method !== "GET" && request.method !== "HEAD") {
      const origin = request.headers.get("origin");
      if (origin && origin !== url.origin) fail("origin_denied", 403);
    }
    if (
      resource === "auth" &&
      request.method === "POST" &&
      ["register", "login", "recover"].includes(target)
    )
      return await authRoute(c, target);
    const raw = await c.auth();
    if (request.method !== "GET") await c.rate("write:" + c.uid, 120);
    if (
      resource === "auth" &&
      target === "logout" &&
      request.method === "POST"
    ) {
      await c.run("DELETE FROM sessions WHERE token=?", await hash(raw));
      return json({ ok: true }, 200, {
        "set-cookie":
          "openly_session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0; Secure",
      });
    }
    if (resource === "me") {
      if (request.method === "GET")
        return json({
          user: exposeUser(c.user, true),
          capabilities: {
            push: !!(
              env.APNS_PRIVATE_KEY &&
              env.APNS_KEY_ID &&
              env.APNS_TEAM_ID &&
              env.IOS_BUNDLE_ID
            ),
            emailRecovery: false,
          },
        });
      if (request.method === "PATCH") {
        const d = z
          .object({
            name: z.string().trim().min(1).max(60).optional(),
            bio: z.string().max(300).optional(),
            interests: interests.optional(),
            song: songSchema.nullable().optional(),
            avatar: uidSchema.nullable().optional(),
            accent: z.enum(["blue", "indigo", "slate"]).optional(),
            private: z.number().int().min(0).max(1).optional(),
            messages: z
              .enum(["everyone", "requests", "following", "nobody"])
              .optional(),
            receipts: z.number().int().min(0).max(1).optional(),
            activity: z.number().int().min(0).max(1).optional(),
            language: z.enum(["en", "ar"]).optional(),
            theme: z.enum(["light", "dark", "system"]).optional(),
            onboarded: z.literal(1).optional(),
            notifications: z
              .array(
                z.enum([
                  "like",
                  "comment",
                  "follow",
                  "follow_request",
                  "message_request",
                  "message",
                ]),
              )
              .max(6)
              .optional(),
          })
          .strict()
          .parse(await c.body());
        if (d.avatar) await c.ownMedia(d.avatar);
        const entries = Object.entries(d);
        if (entries.length)
          await c.run(
            `UPDATE users SET ${entries.map(([k]) => `"${k}"=?`).join(",")} WHERE id=?`,
            ...entries.map(([k, v]) =>
              ["interests", "song", "notifications"].includes(k)
                ? JSON.stringify(v)
                : v,
            ),
            c.uid,
          );
        return json({
          user: exposeUser(
            (await c.one("SELECT * FROM users WHERE id=?", c.uid))!,
            true,
          ),
        });
      }
      if (request.method === "DELETE") {
        if (await c.one("SELECT 1 FROM circles WHERE owner=?", c.uid))
          fail("leave_owned_circles");
        await c.run("DELETE FROM users WHERE id=?", c.uid);
        return json({ ok: true }, 200, {
          "set-cookie": "openly_session=; Path=/; Max-Age=0; HttpOnly; Secure",
        });
      }
    }
    if (resource === "people") {
      if (!target && request.method === "GET") {
        const q = (url.searchParams.get("q") || "").slice(0, 100);
        const items = await c.all(
          `SELECT u.*, f.status following FROM users u LEFT JOIN follows f ON f.follower=? AND f.followed=u.id CROSS JOIN (SELECT ? id) v WHERE u.id<>v.id AND ${unblocked("u.id", "v.id")} AND (u.username LIKE ? ESCAPE '\\' OR u.name LIKE ? ESCAPE '\\') ORDER BY (SELECT count(*) FROM json_each(u.interests) i WHERE i.value IN (SELECT value FROM json_each(?))) DESC,u.created DESC LIMIT 30`,
          c.uid,
          c.uid,
          "%" + escapeLike(q) + "%",
          "%" + escapeLike(q) + "%",
          c.user.interests,
        );
        return json({
          items: items.map((u) => ({
            ...exposeUser(u),
            following: u.following,
            shared: parseJSON(u.interests, []).filter((i: string) =>
              parseJSON(c.user.interests, []).includes(i),
            ),
          })),
        });
      }
      const u = await c.person(target);
      if (!action && request.method === "GET") {
        const follow = await c.one(
          "SELECT status FROM follows WHERE follower=? AND followed=?",
          c.uid,
          u.id,
        );
        return json({
          user: {
            ...exposeUser(u),
            following: follow?.status || null,
            shared: parseJSON(u.interests, []).filter((i: string) =>
              parseJSON(c.user.interests, []).includes(i),
            ),
            followers: (await c.one(
              "SELECT count(*) n FROM follows WHERE followed=? AND status=?",
              u.id,
              "accepted",
            ))!.n,
          },
        });
      }
      if (action === "follow") {
        if (u.id === c.uid) fail("invalid_request");
        if (request.method === "POST") {
          const previous = await c.one(
            "SELECT status FROM follows WHERE follower=? AND followed=?",
            c.uid,
            u.id,
          );
          if (previous) return json(previous);
          const status = u.private ? "pending" : "accepted";
          await c.run(
            "INSERT OR IGNORE INTO follows(follower,followed,status,created) VALUES (?,?,?,?)",
            c.uid,
            u.id,
            status,
            now(),
          );
          await c.notification(
            u.id,
            u.private ? "follow_request" : "follow",
            c.uid,
          );
          return json({ status });
        }
        if (request.method === "DELETE") {
          await c.run(
            "DELETE FROM follows WHERE follower=? AND followed=?",
            c.uid,
            u.id,
          );
          return json({ ok: true });
        }
      }
      if (action === "block" && request.method === "POST") {
        if (u.id === c.uid) fail("invalid_request");
        await c.env.DB.batch([
          c.stmt(
            "INSERT OR IGNORE INTO blocks(blocker,blocked) VALUES (?,?)",
            c.uid,
            u.id,
          ),
          c.stmt(
            "DELETE FROM follows WHERE (follower=? AND followed=?) OR (follower=? AND followed=?)",
            c.uid,
            u.id,
            u.id,
            c.uid,
          ),
        ]);
        return json({ ok: true });
      }
    }
    if (resource === "blocks") {
      if (request.method === "GET")
        return json({
          items: await c.all(
            "SELECT u.id,u.name,u.username FROM users u JOIN blocks b ON b.blocked=u.id WHERE b.blocker=?",
            c.uid,
          ),
        });
      if (target && request.method === "DELETE") {
        await c.run(
          "DELETE FROM blocks WHERE blocker=? AND blocked=?",
          c.uid,
          target,
        );
        return json({ ok: true });
      }
    }
    if (resource === "requests") {
      if (request.method === "GET")
        return json({
          items: await c.all(
            "SELECT u.id,u.name,u.username,u.avatar FROM follows f JOIN users u ON u.id=f.follower WHERE f.followed=? AND f.status=?",
            c.uid,
            "pending",
          ),
        });
      if (target && request.method === "POST") {
        const d = z.object({ accept: z.boolean() }).parse(await c.body());
        if (await c.blocked(target)) fail("unavailable", 404);
        if (d.accept) {
          await c.run(
            "UPDATE follows SET status=? WHERE follower=? AND followed=? AND status=?",
            "accepted",
            target,
            c.uid,
            "pending",
          );
          await c.notification(target, "follow", c.uid);
        } else
          await c.run(
            "DELETE FROM follows WHERE follower=? AND followed=? AND status=?",
            target,
            c.uid,
            "pending",
          );
        return json({ ok: true });
      }
    }
    if (resource === "feed" && request.method === "GET")
      return await feed(c, url);
    if (resource === "posts") {
      if (!target && request.method === "POST") {
        await c.rate("post:" + c.uid, 15);
        const d = z
          .object({
            id: uidSchema,
            body: z.string().trim().max(1500),
            image: uidSchema.nullable().optional(),
            song: songSchema.nullable().optional(),
            audience: z
              .enum(["public", "followers", "only_me"])
              .default("public"),
            circleId: uidSchema.nullable().optional(),
            kind: z
              .enum(["post", "moment", "question", "conversation"])
              .default("post"),
            mood: z.string().max(40).nullable().optional(),
          })
          .parse(await c.body());
        if (!d.body && !d.image && !d.song) fail("empty_post");
        const old = await c.one("SELECT * FROM posts WHERE id=?", d.id);
        if (old) {
          if (old.author !== c.uid) fail("conflict", 409);
          return json({ post: exposePost(old) });
        }
        const media = await c.ownMedia(d.image);
        if (media && !media.type.startsWith("image/")) fail("invalid_media");
        if (
          d.image &&
          (await c.one("SELECT 1 FROM posts WHERE image=?", d.image))
        )
          fail("media_already_used");
        if (d.circleId) await c.circle(d.circleId, true);
        if (["question", "conversation"].includes(d.kind) && !d.circleId)
          fail("invalid_request");
        await c.run(
          "INSERT INTO posts(id,author,body,image,song,audience,circleId,kind,mood,expires,created) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
          d.id,
          c.uid,
          d.body,
          d.image || null,
          d.song ? JSON.stringify(d.song) : null,
          d.audience,
          d.circleId || null,
          d.kind,
          d.mood || null,
          d.kind === "moment" ? now() + 86400000 : null,
          now(),
        );
        return json({ post: exposePost(await c.post(d.id)) }, 201);
      }
      if (target) {
        const p = await c.post(target);
        if (!action && request.method === "GET")
          return json({ post: exposePost(p) });
        if (!action && request.method === "PATCH") {
          if (p.author !== c.uid) fail("forbidden", 403);
          const d = z
            .object({
              body: z.string().trim().max(1500).optional(),
              audience: z.enum(["public", "followers", "only_me"]).optional(),
              pinned: z.number().int().min(0).max(1).optional(),
            })
            .strict()
            .parse(await c.body());
          const entries = Object.entries(d);
          if (d.body === "" && !p.image && !p.song) fail("empty_post");
          if (entries.length)
            await c.run(
              `UPDATE posts SET ${entries.map(([k]) => `"${k}"=?`).join(",")},updated=? WHERE id=?`,
              ...entries.map(([, v]) => v),
              now(),
              target,
            );
          return json({ post: exposePost(await c.post(target)) });
        }
        if (!action && request.method === "DELETE") {
          if (p.author !== c.uid) {
            if (!p.circleId) fail("forbidden", 403);
            await c.circle(p.circleId, true, true);
          }
          await c.run("DELETE FROM posts WHERE id=?", target);
          return json({ ok: true });
        }
        if (action === "like") {
          if (request.method === "POST") {
            const old = await c.one(
              "SELECT 1 FROM likes WHERE postId=? AND userId=?",
              target,
              c.uid,
            );
            await c.run(
              "INSERT OR IGNORE INTO likes(postId,userId) VALUES (?,?)",
              target,
              c.uid,
            );
            if (!old) await c.notification(p.author, "like", target);
          } else if (request.method === "DELETE")
            await c.run(
              "DELETE FROM likes WHERE postId=? AND userId=?",
              target,
              c.uid,
            );
          else fail("method", 405);
          return json({ ok: true });
        }
        if (action === "hide" && request.method === "POST") {
          await c.run(
            "INSERT OR IGNORE INTO hidden(postId,userId) VALUES (?,?)",
            target,
            c.uid,
          );
          return json({ ok: true });
        }
        if (action === "comments") {
          if (request.method === "GET") {
            const before = Number(url.searchParams.get("before") || now() + 1);
            return json({
              items: await c.all(
                `SELECT cm.*,u.username,u.name,u.avatar FROM comments cm JOIN users u ON u.id=cm.author CROSS JOIN (SELECT ? id) v WHERE cm.postId=? AND cm.created<? AND ${unblocked("cm.author", "v.id")} ORDER BY cm.created DESC LIMIT 40`,
                c.uid,
                target,
                before,
              ),
            });
          }
          if (request.method === "POST") {
            const d = z
              .object({
                id: uidSchema,
                body: z.string().trim().min(1).max(1000),
                parent: uidSchema.nullable().optional(),
              })
              .parse(await c.body());
            if (
              d.parent &&
              !(await c.one(
                "SELECT 1 FROM comments WHERE id=? AND postId=?",
                d.parent,
                target,
              ))
            )
              fail("unavailable", 404);
            const old = await c.one("SELECT * FROM comments WHERE id=?", d.id);
            if (old) {
              if (old.author !== c.uid || old.postId !== target)
                fail("conflict", 409);
              return json({ ok: true });
            }
            await c.run(
              "INSERT INTO comments(id,postId,author,parent,body,created) VALUES (?,?,?,?,?,?)",
              d.id,
              target,
              c.uid,
              d.parent || null,
              d.body,
              now(),
            );
            await c.notification(p.author, "comment", target);
            if (d.parent) {
              const parent = await c.one(
                "SELECT author FROM comments WHERE id=?",
                d.parent,
              );
              if (parent?.author !== p.author)
                await c.notification(parent!.author, "comment", target);
            }
            return json({ ok: true }, 201);
          }
        }
      }
    }
    if (resource === "collections") {
      if (!target && request.method === "GET")
        return json({
          items: await c.all(
            "SELECT c.*, (SELECT count(*) FROM saves s WHERE s.collectionId=c.id) count FROM collections c WHERE c.owner=? ORDER BY c.created DESC",
            c.uid,
          ),
        });
      if (!target && request.method === "POST") {
        const d = z
          .object({ name: z.string().trim().min(1).max(60) })
          .parse(await c.body());
        const cid = id();
        await c.run(
          "INSERT INTO collections(id,owner,name,created) VALUES (?,?,?,?)",
          cid,
          c.uid,
          d.name,
          now(),
        );
        return json({ id: cid }, 201);
      }
      const collection = await c.one(
        "SELECT * FROM collections WHERE id=? AND owner=?",
        target,
        c.uid,
      );
      if (!collection) fail("unavailable", 404);
      if (request.method === "GET")
        return await feed(
          c,
          url,
          "EXISTS(SELECT 1 FROM saves s WHERE s.postId=p.id AND s.collectionId=?)",
          [target],
        );
      if (!action && request.method === "DELETE") {
        await c.run("DELETE FROM collections WHERE id=?", target);
        return json({ ok: true });
      }
      if (!action && request.method === "PATCH") {
        const d = z
          .object({ name: z.string().trim().min(1).max(60) })
          .parse(await c.body());
        await c.run("UPDATE collections SET name=? WHERE id=?", d.name, target);
        return json({ ok: true });
      }
      if (action && ["POST", "DELETE"].includes(request.method)) {
        await c.post(action);
        if (request.method === "POST")
          await c.run(
            "INSERT OR IGNORE INTO saves(collectionId,postId) VALUES (?,?)",
            target,
            action,
          );
        else
          await c.run(
            "DELETE FROM saves WHERE collectionId=? AND postId=?",
            target,
            action,
          );
        return json({ ok: true });
      }
    }
    if (resource === "circles") {
      if (!target && request.method === "GET") {
        const q = escapeLike((url.searchParams.get("q") || "").slice(0, 100));
        return json({
          items: await c.all(
            `SELECT c.*, m.status,m.role,(SELECT count(*) FROM members mm WHERE mm.circleId=c.id AND mm.status='accepted') members FROM circles c LEFT JOIN members m ON m.circleId=c.id AND m.userId=? CROSS JOIN (SELECT ? id) v WHERE ${unblocked("c.owner", "v.id")} AND c.name LIKE ? ESCAPE '\\' ORDER BY (c.interest IN (SELECT value FROM json_each((SELECT interests FROM users WHERE id=v.id)))) DESC,c.created DESC LIMIT 30`,
            c.uid,
            c.uid,
            "%" + q + "%",
          ),
        });
      }
      if (!target && request.method === "POST") {
        const d = z
          .object({
            name: z.string().trim().min(3).max(60),
            description: z.string().trim().max(500),
            rules: z.string().max(1500),
            interest: interests.element,
            private: z.number().int().min(0).max(1),
          })
          .parse(await c.body());
        const cid = id();
        await c.env.DB.batch([
          c.stmt(
            "INSERT INTO circles(id,owner,name,description,rules,interest,private,created) VALUES (?,?,?,?,?,?,?,?)",
            cid,
            c.uid,
            d.name,
            d.description,
            d.rules,
            d.interest,
            d.private,
            now(),
          ),
          c.stmt(
            "INSERT INTO members(circleId,userId,role,status,created) VALUES (?,?,?,?,?)",
            cid,
            c.uid,
            "owner",
            "accepted",
            now(),
          ),
        ]);
        return json({ id: cid }, 201);
      }
      if (target && action === "join" && request.method === "POST") {
        const circle = await c.one("SELECT * FROM circles WHERE id=?", target);
        if (!circle || (await c.blocked(circle.owner)))
          fail("unavailable", 404);
        const current = await c.one(
          "SELECT status FROM members WHERE circleId=? AND userId=?",
          target,
          c.uid,
        );
        if (current?.status === "banned") fail("unavailable", 404);
        if (current) return json(current);
        const status = circle!.private ? "pending" : "accepted";
        await c.run(
          "INSERT OR IGNORE INTO members(circleId,userId,role,status,created) VALUES (?,?,?,?,?)",
          target,
          c.uid,
          "member",
          status,
          now(),
        );
        return json({ status });
      }
      const circle = await c.circle(target);
      if (!action && request.method === "GET") return json({ circle });
      if (action === "leave" && request.method === "POST") {
        if (circle.owner === c.uid) fail("owner_cannot_leave");
        await c.run(
          "DELETE FROM members WHERE circleId=? AND userId=?",
          target,
          c.uid,
        );
        return json({ ok: true });
      }
      if (!action && request.method === "DELETE") {
        if (circle.owner !== c.uid) fail("forbidden", 403);
        await c.run("DELETE FROM circles WHERE id=?", target);
        return json({ ok: true });
      }
      if (action === "members") {
        await c.circle(target, true);
        if (request.method === "GET") {
          const mod = ["owner", "moderator"].includes(circle.role);
          return json({
            items: await c.all(
              `SELECT m.userId,m.status,m.role,u.username,u.name,u.avatar FROM members m JOIN users u ON u.id=m.userId CROSS JOIN (SELECT ? id) v WHERE m.circleId=? AND ${unblocked("u.id", "v.id")} AND (m.status='accepted' OR ?=1) LIMIT 100`,
              c.uid,
              target,
              mod ? 1 : 0,
            ),
          });
        }
        if (request.method === "PATCH") {
          await c.circle(target, true, true);
          const d = z
            .object({
              userId: uidSchema,
              operation: z.enum(["accept", "remove", "moderator", "member"]),
            })
            .parse(await c.body());
          if (d.userId === circle.owner) fail("forbidden", 403);
          const member = await c.one(
            "SELECT * FROM members WHERE circleId=? AND userId=?",
            target,
            d.userId,
          );
          if (!member) fail("unavailable", 404);
          if (
            (["moderator", "member"].includes(d.operation) ||
              member!.role === "moderator") &&
            circle.owner !== c.uid
          )
            fail("forbidden", 403);
          if (d.operation === "remove")
            await c.run(
              "UPDATE members SET status=? WHERE circleId=? AND userId=?",
              "banned",
              target,
              d.userId,
            );
          else if (d.operation === "accept")
            await c.run(
              "UPDATE members SET status=? WHERE circleId=? AND userId=? AND status=?",
              "accepted",
              target,
              d.userId,
              "pending",
            );
          else
            await c.run(
              "UPDATE members SET role=? WHERE circleId=? AND userId=?",
              d.operation,
              target,
              d.userId,
            );
          return json({ ok: true });
        }
      }
    }
    if (resource === "search" && request.method === "GET") {
      const q = escapeLike((url.searchParams.get("q") || "").slice(0, 100));
      return await feed(c, url, "p.body LIKE ? ESCAPE '\\'", ["%" + q + "%"]);
    }
    if (resource === "music" && request.method === "GET") {
      const q = (url.searchParams.get("q") || "").trim().slice(0, 100);
      if (q.length < 2) return json({ items: [] });
      await c.rate("music:" + c.uid, 30);
      const r = await fetch(
        "https://itunes.apple.com/search?" +
          new URLSearchParams({
            term: q,
            entity: "song",
            limit: "12",
            country: "DE",
          }),
        { signal: AbortSignal.timeout(8000) },
      );
      if (!r.ok) fail("music_unavailable", 503);
      const data: any = await r.json();
      return json({
        items: (data.results || []).map((s: Row) => ({
          id: s.trackId,
          title: s.trackName,
          artist: s.artistName,
          artwork: s.artworkUrl100,
          url: s.trackViewUrl,
          preview: s.previewUrl || null,
        })),
      });
    }
    if (resource === "media") {
      if (!target && request.method === "POST") {
        await c.rate("upload:" + c.uid, 20, 3600000);
        const size = Number(request.headers.get("content-length") || 0);
        if (size > 10 * 1024 * 1024) fail("too_large", 413);
        const type = request.headers.get("content-type")?.split(";")[0] || "";
        if (
          ![
            "image/jpeg",
            "image/png",
            "image/webp",
            "audio/webm",
            "audio/mp4",
            "audio/mpeg",
            "audio/ogg",
          ].includes(type)
        )
          fail("unsupported_media", 415);
        const reader = request.body?.getReader();
        if (!reader) fail("invalid_media");
        const chunks: Uint8Array[] = [];
        let total = 0;
        while (true) {
          const { done, value } = await reader!.read();
          if (done) break;
          total += value.length;
          if (total > 10 * 1024 * 1024) {
            await reader!.cancel();
            fail("too_large", 413);
          }
          chunks.push(value);
        }
        const bytes = new Uint8Array(total);
        let pos = 0;
        for (const chunk of chunks) {
          bytes.set(chunk, pos);
          pos += chunk.length;
        }
        if (!total || !validMagic(type, bytes)) fail("invalid_media");
        const used = await c.one(
          "SELECT coalesce(sum(size),0) size FROM media WHERE owner=? AND created>?",
          c.uid,
          now() - 86400000,
        );
        if (used!.size + total > 100 * 1024 * 1024) fail("upload_quota", 429);
        const mid = id();
        await env.BUCKET.put(mid, bytes, {
          httpMetadata: { contentType: type },
        });
        try {
          await c.run(
            "INSERT INTO media(id,owner,type,size,created) VALUES (?,?,?,?,?)",
            mid,
            c.uid,
            type,
            total,
            now(),
          );
        } catch (e) {
          await env.BUCKET.delete(mid);
          throw e;
        }
        return json({ id: mid, type, size: total }, 201);
      }
      if (target && request.method === "GET") {
        const m = await canMedia(c, target);
        const object = await env.BUCKET.get(target);
        if (!object) fail("unavailable", 404);
        return new Response(object.body, {
          headers: {
            "content-type": m!.type,
            "content-length": String(m!.size),
            "cache-control": "private, no-store, max-age=0",
            "x-content-type-options": "nosniff",
            "content-security-policy": "default-src 'none'",
            "content-disposition": "inline",
          },
        });
      }
    }
    if (resource === "conversations") {
      if (!target && request.method === "GET") {
        const rows = await c.all(
          `SELECT c.*,u.name,u.username,u.avatar,u.id other,cs.muted,cs.draft,(SELECT body FROM messages WHERE conversationId=c.id ORDER BY created DESC,id DESC LIMIT 1) lastBody,(SELECT created FROM messages WHERE conversationId=c.id ORDER BY created DESC,id DESC LIMIT 1) lastAt,(SELECT count(*) FROM messages WHERE conversationId=c.id AND sender<>? AND read IS NULL) unread FROM conversations c JOIN users u ON u.id=CASE WHEN c.a=? THEN c.b ELSE c.a END LEFT JOIN conversation_state cs ON cs.conversationId=c.id AND cs.userId=? CROSS JOIN (SELECT ? id) v WHERE (c.a=v.id OR c.b=v.id) AND ${unblocked("u.id", "v.id")} ORDER BY coalesce(lastAt,c.created) DESC LIMIT 50`,
          c.uid,
          c.uid,
          c.uid,
          c.uid,
        );
        return json({ items: rows });
      }
      if (!target && request.method === "POST") {
        const d = z.object({ userId: uidSchema }).parse(await c.body());
        const u = await c.person(d.userId);
        if (u.id === c.uid) fail("invalid_request");
        const pair = [c.uid, u.id].sort();
        const existing = await c.one(
          "SELECT * FROM conversations WHERE a=? AND b=?",
          ...pair,
        );
        if (existing) return json({ conversation: existing });
        if (u.messages === "nobody") fail("messages_closed", 403);
        const permitted = await c.one(
          "SELECT 1 FROM follows WHERE follower=? AND followed=? AND status=?",
          u.id,
          c.uid,
          "accepted",
        );
        if (u.messages === "following" && !permitted)
          fail("messages_closed", 403);
        const status =
          u.messages === "everyone" || permitted ? "accepted" : "pending";
        const cid = id();
        await c.run(
          "INSERT OR IGNORE INTO conversations(id,a,b,initiator,status,created) VALUES (?,?,?,?,?,?)",
          cid,
          ...pair,
          c.uid,
          status,
          now(),
        );
        const result = await c.one(
          "SELECT * FROM conversations WHERE a=? AND b=?",
          ...pair,
        );
        if (result!.id === cid && status === "pending")
          await c.notification(u.id, "message_request", cid);
        return json({ conversation: result }, 201);
      }
      const conv = await c.conversation(target);
      if (action === "accept" && request.method === "POST") {
        if (conv.initiator === c.uid) fail("forbidden", 403);
        await c.run(
          "UPDATE conversations SET status=? WHERE id=?",
          "accepted",
          target,
        );
        return json({ ok: true });
      }
      if (action === "decline" && request.method === "POST") {
        if (conv.initiator === c.uid) fail("forbidden", 403);
        await c.run(
          "UPDATE conversations SET status=? WHERE id=?",
          "declined",
          target,
        );
        return json({ ok: true });
      }
      if (action === "state") {
        if (request.method === "GET")
          return json({
            state: await c.one(
              "SELECT * FROM conversation_state WHERE conversationId=? AND userId=?",
              target,
              c.uid,
            ),
          });
        if (request.method === "PATCH") {
          const d = z
            .object({
              draft: z.string().max(5000).optional(),
              muted: z.number().int().min(0).max(1).optional(),
              typing: z.boolean().optional(),
            })
            .parse(await c.body());
          await c.run(
            "INSERT OR IGNORE INTO conversation_state(conversationId,userId) VALUES (?,?)",
            target,
            c.uid,
          );
          const entries = Object.entries(d).filter(([k]) => k !== "typing");
          if (entries.length)
            await c.run(
              `UPDATE conversation_state SET ${entries.map(([k]) => `"${k}"=?`).join(",")} WHERE conversationId=? AND userId=?`,
              ...entries.map(([, v]) => v),
              target,
              c.uid,
            );
          if (d.typing !== undefined)
            await c.run(
              "UPDATE conversation_state SET typingUntil=? WHERE conversationId=? AND userId=?",
              d.typing && c.user.activity ? now() + 5000 : 0,
              target,
              c.uid,
            );
          return json({ ok: true });
        }
      }
      if (action === "messages") {
        if (request.method === "GET") {
          const before = Number(url.searchParams.get("before") || now() + 1);
          const cursor = url.searchParams.get("cursor") || "~";
          const after = Number(url.searchParams.get("after") || 0);
          const items = await c.all(
            "SELECT m.*, (SELECT json_group_array(json_object('userId',r.userId,'emoji',r.emoji)) FROM reactions r WHERE r.messageId=m.id) reactions FROM messages m WHERE conversationId=? AND (created<? OR (created=? AND id<?)) AND created>=? ORDER BY created DESC,id DESC LIMIT 40",
            target,
            before,
            before,
            cursor,
            after,
          );
          const other = await c.one(
            "SELECT receipts,activity FROM users WHERE id=?",
            conv.other,
          );
          const state = await c.one(
            "SELECT typingUntil FROM conversation_state WHERE conversationId=? AND userId=?",
            target,
            conv.other,
          );
          return json({
            items: items
              .reverse()
              .map((m) => ({
                ...m,
                read: other!.receipts ? m.read : null,
                reactions: parseJSON(m.reactions, []),
              })),
            typing: !!other!.activity && state?.typingUntil > now(),
            status: conv.status,
            next:
              items.length === 40
                ? { before: items[0].created, cursor: items[0].id }
                : null,
          });
        }
        if (request.method === "POST") {
          await c.rate("message:" + c.uid, 60);
          const d = z
            .object({
              id: uidSchema,
              body: z.string().trim().max(5000),
              media: uidSchema.nullable().optional(),
              replyTo: uidSchema.nullable().optional(),
            })
            .parse(await c.body());
          if (!d.body && !d.media) fail("empty_message");
          const old = await c.one("SELECT * FROM messages WHERE id=?", d.id);
          if (old) {
            if (old.sender !== c.uid || old.conversationId !== target)
              fail("conflict", 409);
            return json({ message: old });
          }
          if (conv.status !== "accepted") {
            const count = await c.one(
              "SELECT count(*) n FROM messages WHERE conversationId=?",
              target,
            );
            if (
              conv.status !== "pending" ||
              conv.initiator !== c.uid ||
              count!.n >= 1 ||
              d.media
            )
              fail("request_pending", 403);
          }
          await c.ownMedia(d.media);
          if (
            d.media &&
            (await c.one("SELECT 1 FROM messages WHERE media=?", d.media))
          )
            fail("media_already_used");
          if (
            d.replyTo &&
            !(await c.one(
              "SELECT 1 FROM messages WHERE id=? AND conversationId=?",
              d.replyTo,
              target,
            ))
          )
            fail("unavailable", 404);
          await c.run(
            "INSERT OR IGNORE INTO messages(id,conversationId,sender,body,media,replyTo,created) SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM conversations c WHERE c.id=? AND (c.status='accepted' OR (c.status='pending' AND c.initiator=? AND NOT EXISTS(SELECT 1 FROM messages mx WHERE mx.conversationId=c.id))))",
            d.id,
            target,
            c.uid,
            d.body,
            d.media || null,
            d.replyTo || null,
            now(),
            target,
            c.uid,
          );
          if (
            !(await c.one(
              "SELECT 1 FROM messages WHERE id=? AND sender=?",
              d.id,
              c.uid,
            ))
          )
            fail("request_pending", 403);
          await c.notification(conv.other, "message", target);
          return json(
            { message: await c.one("SELECT * FROM messages WHERE id=?", d.id) },
            201,
          );
        }
      }
      if (action === "ack" && request.method === "POST") {
        const d = z
          .object({
            ids: z.array(uidSchema).min(1).max(100),
            read: z.boolean().default(false),
          })
          .parse(await c.body());
        await c.run(
          `UPDATE messages SET delivered=coalesce(delivered,?),read=CASE WHEN ?=1 THEN coalesce(read,?) ELSE read END WHERE conversationId=? AND sender<>? AND id IN (${d.ids.map(() => "?").join(",")})`,
          now(),
          d.read && c.user.receipts ? 1 : 0,
          now(),
          target,
          c.uid,
          ...d.ids,
        );
        return json({ ok: true });
      }
      if (action === "events" && request.method === "GET") {
        let cancelled = false;
        let controllerRef: ReadableStreamDefaultController<Uint8Array>;
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            controllerRef = controller;
          },
          cancel() {
            cancelled = true;
          },
        });
        const run = async () => {
          let previous = "";
          try {
            for (let tick = 0; tick < 25 && !cancelled; tick++) {
              const active = await c.one(
                "SELECT 1 FROM sessions WHERE token=? AND expires>?",
                await hash(raw),
                now(),
              );
              if (!active) break;
              await c.conversation(target);
              const state = await c.one(
                "SELECT count(*) n, max(created) newest, max(delivered) delivered,max(read) seen FROM messages WHERE conversationId=?",
                target,
              );
              const react = await c.one(
                "SELECT count(*) n, group_concat(r.emoji) emoji FROM reactions r JOIN messages m ON m.id=r.messageId WHERE m.conversationId=?",
                target,
              );
              const typing = await c.one(
                "SELECT typingUntil FROM conversation_state WHERE conversationId=? AND userId=?",
                target,
                conv.other,
              );
              const next = JSON.stringify([state, react, typing]);
              if (next !== previous) {
                controllerRef.enqueue(
                  encoder.encode("event: update\ndata: {}\n\n"),
                );
                previous = next;
              } else controllerRef.enqueue(encoder.encode(": heartbeat\n\n"));
              await new Promise((resolve) => setTimeout(resolve, 1000));
            }
          } catch {
            /* Losing permission closes the stream without disclosing content. */
          } finally {
            if (!cancelled) controllerRef.close();
          }
        };
        void run();
        return new Response(stream, {
          headers: {
            "content-type": "text/event-stream",
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
          },
        });
      }
    }
    if (
      resource === "messages" &&
      target &&
      action === "reaction" &&
      request.method === "POST"
    ) {
      const m = await c.one("SELECT * FROM messages WHERE id=?", target);
      if (!m) fail("unavailable", 404);
      await c.conversation(m!.conversationId, true);
      const d = z
        .object({ emoji: z.enum(["♥", "👍", "✨", "😂", ""]).default("♥") })
        .parse(await c.body());
      if (d.emoji)
        await c.run(
          "INSERT INTO reactions(messageId,userId,emoji) VALUES (?,?,?) ON CONFLICT(messageId,userId) DO UPDATE SET emoji=excluded.emoji",
          target,
          c.uid,
          d.emoji,
        );
      else
        await c.run(
          "DELETE FROM reactions WHERE messageId=? AND userId=?",
          target,
          c.uid,
        );
      return json({ ok: true });
    }
    if (resource === "notifications") {
      if (request.method === "GET") {
        const rows = await c.all(
          `SELECT n.*,u.name,u.username,u.avatar FROM notifications n JOIN users u ON u.id=n.actor CROSS JOIN (SELECT ? id) v WHERE n.recipient=v.id AND ${unblocked("n.actor", "v.id")} ORDER BY n.created DESC LIMIT 60`,
          c.uid,
        );
        const visible = [];
        for (const n of rows) {
          try {
            if (["like", "comment"].includes(n.type)) await c.post(n.target);
            if (["message", "message_request"].includes(n.type))
              await c.conversation(n.target);
            visible.push(n);
          } catch {
            /* Deleted or newly restricted content is omitted. */
          }
        }
        return json({ items: visible });
      }
      if (request.method === "POST") {
        if (target)
          await c.run(
            "UPDATE notifications SET read=? WHERE id=? AND recipient=?",
            now(),
            target,
            c.uid,
          );
        else
          await c.run(
            "UPDATE notifications SET read=? WHERE recipient=? AND read IS NULL",
            now(),
            c.uid,
          );
        return json({ ok: true });
      }
    }
    if (resource === "reports") {
      if (request.method === "POST") {
        const d = z
          .object({
            kind: z.enum(["post", "person", "message"]),
            target: uidSchema,
            reason: z.string().trim().min(3).max(1000),
          })
          .parse(await c.body());
        let circleId = null;
        if (d.kind === "post") circleId = (await c.post(d.target)).circleId;
        if (d.kind === "person") await c.person(d.target);
        if (d.kind === "message") {
          const m = await c.one(
            "SELECT conversationId FROM messages WHERE id=?",
            d.target,
          );
          if (!m) fail("unavailable", 404);
          await c.conversation(m!.conversationId);
        }
        await c.run(
          "INSERT INTO reports(id,reporter,kind,target,circleId,reason,created) VALUES (?,?,?,?,?,?,?)",
          id(),
          c.uid,
          d.kind,
          d.target,
          circleId,
          d.reason,
          now(),
        );
        return json({ ok: true }, 201);
      }
      const circleId = url.searchParams.get("circle");
      const admin = (env.MODERATOR_IDS || "").split(",").includes(c.uid);
      if (circleId) await c.circle(circleId, true, true);
      else if (!admin) fail("forbidden", 403);
      if (request.method === "GET")
        return json({
          items: await c.all(
            "SELECT * FROM reports WHERE (? IS NULL OR circleId=?) AND status=? ORDER BY created DESC LIMIT 50",
            circleId,
            circleId,
            "open",
          ),
        });
      if (target && request.method === "PATCH") {
        const report = await c.one("SELECT * FROM reports WHERE id=?", target);
        if (!report || (!admin && report.circleId !== circleId))
          fail("unavailable", 404);
        const d = z.object({ remove: z.boolean() }).parse(await c.body());
        if (d.remove) {
          if (report!.kind === "post")
            await c.run("DELETE FROM posts WHERE id=?", report!.target);
          else if (report!.kind === "message" && admin)
            await c.run("DELETE FROM messages WHERE id=?", report!.target);
          else fail("invalid_request");
        }
        await c.run(
          "UPDATE reports SET status=? WHERE id=?",
          "reviewed",
          target,
        );
        return json({ ok: true });
      }
    }
    if (resource === "drafts" && target) {
      if (!/^[a-z0-9_-]{1,50}$/i.test(target)) fail("invalid_request");
      if (request.method === "GET")
        return json({
          value: parseJSON(
            (
              await c.one(
                "SELECT value FROM drafts WHERE userId=? AND key=?",
                c.uid,
                target,
              )
            )?.value,
            {},
          ),
        });
      if (request.method === "PUT") {
        const data = await c.body();
        await c.run(
          "INSERT INTO drafts(userId,key,value,updated) VALUES (?,?,?,?) ON CONFLICT(userId,key) DO UPDATE SET value=excluded.value,updated=excluded.updated",
          c.uid,
          target,
          JSON.stringify(data),
          now(),
        );
        return json({ ok: true });
      }
      if (request.method === "DELETE") {
        await c.run(
          "DELETE FROM drafts WHERE userId=? AND key=?",
          c.uid,
          target,
        );
        return json({ ok: true });
      }
    }
    if (resource === "devices" && request.method === "POST") {
      if (!env.APNS_PRIVATE_KEY) fail("push_unavailable", 503);
      const d = z
        .object({
          token: z.string().regex(/^[a-f0-9]{64,200}$/),
          platform: z.literal("ios"),
        })
        .parse(await c.body());
      await c.run(
        "INSERT INTO devices(token,owner,platform,created) VALUES (?,?,?,?) ON CONFLICT(token) DO UPDATE SET owner=excluded.owner",
        d.token,
        c.uid,
        d.platform,
        now(),
      );
      return json({ ok: true });
    }
    return fail("not_found", 404);
  } catch (e) {
    if (e instanceof APIError) return json({ error: e.code }, e.status);
    if (e instanceof z.ZodError)
      return json(
        { error: "validation", fields: e.issues.map((i) => i.path.join(".")) },
        400,
      );
    console.error("Openly API failure", {
      resource,
      method: request.method,
      error: e instanceof Error ? e.name : "unknown",
    });
    return json({ error: "server_error" }, 500);
  }
}
function escapeLike(q: string) {
  return q.replace(/[\\%_]/g, "\\$&");
}
function validMagic(type: string, b: Uint8Array) {
  const ascii = (start: number, end: number) =>
    String.fromCharCode(...b.slice(start, end));
  if (type === "image/jpeg")
    return b[0] === 255 && b[1] === 216 && b[2] === 255;
  if (type === "image/png") return b[0] === 137 && ascii(1, 4) === "PNG";
  if (type === "image/webp")
    return ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP";
  if (type === "audio/webm")
    return b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3;
  if (type === "audio/ogg") return ascii(0, 4) === "OggS";
  if (type === "audio/mp4") return ascii(4, 8) === "ftyp";
  if (type === "audio/mpeg")
    return ascii(0, 3) === "ID3" || (b[0] === 255 && (b[1] & 224) === 224);
  return false;
}
