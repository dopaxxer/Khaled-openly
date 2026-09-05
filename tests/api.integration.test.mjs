import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync, readdirSync, mkdirSync, writeFileSync } from "node:fs";
import ts from "typescript";
mkdirSync(".test-build", { recursive: true });
writeFileSync(
  ".test-build/api.mjs",
  ts.transpileModule(readFileSync("server/api.ts", "utf8"), {
    compilerOptions: {
      module: ts.ModuleKind.ESNext,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText,
);
const { api } = await import("../.test-build/api.mjs");
let database, env, a, b;
class D1 {
  constructor(db) {
    this.db = db;
  }
  prepare(sql) {
    const state = { args: [] };
    const s = {
      bind(...args) {
        state.args = args;
        return s;
      },
      async first() {
        return this.db.prepare(sql).get(...state.args) || null;
      },
      async all() {
        return { results: this.db.prepare(sql).all(...state.args) };
      },
      async run() {
        return this.db.prepare(sql).run(...state.args);
      },
      db: this.db,
    };
    return s;
  }
  async batch(statements) {
    this.db.exec("BEGIN");
    try {
      const results = [];
      for (const s of statements) results.push(await s.run());
      this.db.exec("COMMIT");
      return results;
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }
}
async function call(path, method = "GET", body, user, headers = {}) {
  const req = new Request("https://openly.test/api/" + path, {
    method,
    headers: {
      ...(user ? { authorization: "Bearer " + user.token } : {}),
      ...(body ? { "content-type": "application/json" } : {}),
      "x-openly-client": "ios",
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const res = await api(req, env);
  const data = res.headers.get("content-type")?.includes("application/json")
    ? await res.json()
    : await res.arrayBuffer();
  return { status: res.status, data, res };
}
async function register(name) {
  const r = await call("auth/register", "POST", {
    name: "Development test " + name,
    username: "test_" + name,
    email: name + "@example.test",
    password: "test-only-long-passphrase-123",
  });
  assert.equal(r.status, 201);
  return { ...r.data.user, token: r.data.token, recovery: r.data.recovery };
}
async function post(user, values = {}) {
  const r = await call(
    "posts",
    "POST",
    {
      id: crypto.randomUUID(),
      body: "Development test post",
      audience: "public",
      ...values,
    },
    user,
  );
  assert.equal(r.status, 201, JSON.stringify(r.data));
  return r.data.post;
}
beforeEach(async () => {
  database = new DatabaseSync(":memory:");
  database.exec("PRAGMA foreign_keys=ON");
  for (const f of readdirSync("drizzle")
    .filter((f) => f.endsWith(".sql"))
    .sort())
    database.exec(readFileSync("drizzle/" + f, "utf8"));
  const blobs = new Map();
  env = {
    DB: new D1(database),
    BUCKET: {
      async put(k, v, o) {
        blobs.set(k, { body: v, ...o });
      },
      async get(k) {
        return blobs.get(k);
      },
      async delete(k) {
        blobs.delete(k);
      },
    },
  };
  a = await register("alice");
  b = await register("bob");
});
afterEach(() => database.close());
test("register → profile → post → discovery → follow → permitted conversation → reply", async () => {
  assert.equal(
    (
      await call(
        "me",
        "PATCH",
        { interests: ["music"], bio: "Testing profile", onboarded: 1 },
        a,
      )
    ).status,
    200,
  );
  await call("me", "PATCH", { interests: ["music"], messages: "everyone" }, b);
  const p = await post(a);
  const people = (await call("people", "GET", null, b)).data.items;
  assert.deepEqual(people.find((x) => x.id === a.id).shared, ["music"]);
  assert.equal(
    (await call("people/" + a.id + "/follow", "POST", null, b)).data.status,
    "accepted",
  );
  assert.ok(
    (await call("feed?mode=following", "GET", null, b)).data.items.some(
      (x) => x.id === p.id,
    ),
  );
  const conv = (await call("conversations", "POST", { userId: b.id }, a)).data
    .conversation;
  assert.equal(conv.status, "accepted");
  const id = crypto.randomUUID();
  assert.equal(
    (
      await call(
        "conversations/" + conv.id + "/messages",
        "POST",
        { id, body: "Real test message" },
        a,
      )
    ).status,
    201,
  );
  const received = (
    await call("conversations/" + conv.id + "/messages", "GET", null, b)
  ).data.items;
  assert.equal(received[0].body, "Real test message");
  assert.equal(
    (
      await call(
        "conversations/" + conv.id + "/messages",
        "POST",
        { id: crypto.randomUUID(), body: "Real reply", replyTo: id },
        b,
      )
    ).status,
    201,
  );
});
test("private account follow requests and accepted follow permissions", async () => {
  await call("me", "PATCH", { private: 1 }, a);
  const p = await post(a);
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 404);
  assert.equal(
    (await call("people/" + a.id + "/follow", "POST", null, b)).data.status,
    "pending",
  );
  assert.equal(
    (await call("requests/" + b.id, "POST", { accept: true }, b)).status,
    200,
  );
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 404);
  await call("requests/" + b.id, "POST", { accept: true }, a);
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 200);
  await call("people/" + a.id + "/follow", "DELETE", null, b);
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 404);
});
test("only-me audience, ownership, private collections and search do not leak", async () => {
  const p = await post(a, { audience: "only_me", body: "secret-zebra" });
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 404);
  assert.equal(
    (await call("search?q=secret-zebra", "GET", null, b)).data.items.length,
    0,
  );
  const pub = await post(a);
  assert.equal(
    (await call("posts/" + pub.id, "PATCH", { body: "hijacked" }, b)).status,
    403,
  );
  const collection = (await call("collections", "POST", { name: "Private" }, a))
    .data.id;
  await call("collections/" + collection + "/" + p.id, "POST", null, a);
  assert.equal(
    (await call("collections/" + collection, "GET", null, b)).status,
    404,
  );
  assert.equal(
    (await call("collections/" + collection, "DELETE", null, b)).status,
    404,
  );
  assert.equal(
    (await call("collections/" + collection, "GET", null, a)).data.items[0].id,
    p.id,
  );
});
test("message requests permit one introduction, prevent initiator acceptance, require actual acknowledgments", async () => {
  const conv = (await call("conversations", "POST", { userId: b.id }, a)).data
    .conversation;
  assert.equal(conv.status, "pending");
  assert.equal(
    (await call("conversations/" + conv.id + "/accept", "POST", null, a))
      .status,
    403,
  );
  const mid = crypto.randomUUID();
  await call(
    "conversations/" + conv.id + "/messages",
    "POST",
    { id: mid, body: "Hello" },
    a,
  );
  assert.equal(
    (
      await call(
        "conversations/" + conv.id + "/messages",
        "POST",
        { id: crypto.randomUUID(), body: "Too soon" },
        a,
      )
    ).status,
    403,
  );
  const first = (
    await call("conversations/" + conv.id + "/messages", "GET", null, a)
  ).data.items[0];
  assert.equal(first.delivered, null);
  assert.equal(first.read, null);
  await call("conversations/" + conv.id + "/accept", "POST", null, b);
  await call(
    "conversations/" + conv.id + "/ack",
    "POST",
    { ids: [mid], read: false },
    b,
  );
  const delivered = (
    await call("conversations/" + conv.id + "/messages", "GET", null, a)
  ).data.items[0];
  assert.ok(delivered.delivered);
  assert.equal(delivered.read, null);
  await call(
    "conversations/" + conv.id + "/ack",
    "POST",
    { ids: [mid], read: true },
    b,
  );
  assert.ok(
    (await call("conversations/" + conv.id + "/messages", "GET", null, a)).data
      .items[0].read,
  );
  await call("me", "PATCH", { receipts: 0 }, b);
  assert.equal(
    (await call("conversations/" + conv.id + "/messages", "GET", null, a)).data
      .items[0].read,
    null,
  );
});
test("idempotency rejects duplicate posts and duplicate message retries", async () => {
  const pid = crypto.randomUUID();
  await post(a, { id: pid });
  assert.equal(
    (
      await call(
        "posts",
        "POST",
        { id: pid, body: "retry", audience: "public" },
        a,
      )
    ).status,
    200,
  );
  assert.equal(
    database.prepare("SELECT count(*) n FROM posts WHERE id=?").get(pid).n,
    1,
  );
  assert.equal(
    (
      await call(
        "posts",
        "POST",
        { id: pid, body: "steal", audience: "public" },
        b,
      )
    ).status,
    409,
  );
  await call("me", "PATCH", { messages: "everyone" }, b);
  const conv = (await call("conversations", "POST", { userId: b.id }, a)).data
    .conversation;
  const mid = crypto.randomUUID();
  const body = { id: mid, body: "retry-safe" };
  await call("conversations/" + conv.id + "/messages", "POST", body, a);
  await call("conversations/" + conv.id + "/messages", "POST", body, a);
  assert.equal(
    database.prepare("SELECT count(*) n FROM messages WHERE id=?").get(mid).n,
    1,
  );
});
test("blocking is enforced across feeds, profiles, search, notifications and messages", async () => {
  await call("me", "PATCH", { messages: "everyone" }, b);
  const p = await post(a);
  await call("posts/" + p.id + "/like", "POST", null, b);
  const conv = (await call("conversations", "POST", { userId: b.id }, a)).data
    .conversation;
  await call("people/" + b.id + "/block", "POST", null, a);
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 404);
  assert.equal((await call("people/" + a.id, "GET", null, b)).status, 404);
  assert.equal(
    (await call("people?q=test_alice", "GET", null, b)).data.items.length,
    0,
  );
  assert.equal(
    (await call("notifications", "GET", null, a)).data.items.length,
    0,
  );
  assert.equal(
    (await call("conversations/" + conv.id + "/messages", "GET", null, b))
      .status,
    404,
  );
  assert.equal(
    (await call("conversations", "GET", null, b)).data.items.length,
    0,
  );
});
test("private Circle membership and moderator authorization are enforced", async () => {
  const cid = (
    await call(
      "circles",
      "POST",
      {
        name: "Test Circle",
        description: "Development only",
        rules: "Respect privacy",
        interest: "books",
        private: 1,
      },
      a,
    )
  ).data.id;
  assert.equal((await call("circles/" + cid, "GET", null, b)).status, 404);
  const p = await post(a, { circleId: cid });
  await call("circles/" + cid + "/join", "POST", null, b);
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 404);
  assert.equal(
    (
      await call(
        "circles/" + cid + "/members",
        "PATCH",
        { userId: b.id, operation: "accept" },
        b,
      )
    ).status,
    404,
  );
  await call(
    "circles/" + cid + "/members",
    "PATCH",
    { userId: b.id, operation: "accept" },
    a,
  );
  assert.equal((await call("posts/" + p.id, "GET", null, b)).status, 200);
  assert.equal((await call("posts/" + p.id, "DELETE", null, b)).status, 404);
  await call(
    "circles/" + cid + "/members",
    "PATCH",
    { userId: b.id, operation: "moderator" },
    a,
  );
  assert.equal((await call("posts/" + p.id, "DELETE", null, b)).status, 200);
});
test("Moment expiration is enforced on posts and protected media, including its author", async () => {
  const mid = crypto.randomUUID();
  database
    .prepare("INSERT INTO media(id,owner,type,size,created) VALUES (?,?,?,?,?)")
    .run(mid, a.id, "image/png", 8, Date.now());
  await env.BUCKET.put(mid, new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]));
  const p = await post(a, { kind: "moment", image: mid });
  assert.equal(
    database.prepare("SELECT expires FROM media WHERE id=?").get(mid).expires,
    p.expires,
  );
  assert.equal((await call("media/" + mid, "GET", null, b)).status, 200);
  database
    .prepare("UPDATE posts SET expires=? WHERE id=?")
    .run(Date.now() - 1, p.id);
  assert.equal((await call("posts/" + p.id, "GET", null, a)).status, 404);
  assert.equal((await call("media/" + mid, "GET", null, a)).status, 404);
  assert.equal((await call("media/" + mid, "GET", null, b)).status, 404);
  assert.equal(
    (await call("feed?kind=moment", "GET", null, b)).data.items.length,
    0,
  );
});
test("expired media stays inaccessible after content removal and account deletion purges bytes", async () => {
  const mid = crypto.randomUUID();
  database
    .prepare("INSERT INTO media(id,owner,type,size,created) VALUES (?,?,?,?,?)")
    .run(mid, a.id, "image/png", 8, Date.now());
  await env.BUCKET.put(mid, new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]));
  const p = await post(a, { kind: "moment", image: mid });
  database
    .prepare("UPDATE media SET expires=? WHERE id=?")
    .run(Date.now() - 1, mid);
  database.prepare("DELETE FROM posts WHERE id=?").run(p.id);
  assert.equal((await call("media/" + mid, "GET", null, a)).status, 404);
  assert.equal((await call("media/" + mid, "GET", null, b)).status, 404);
  assert.ok(await env.BUCKET.get(mid));
  assert.equal((await call("me", "DELETE", null, a)).status, 200);
  assert.equal(await env.BUCKET.get(mid), undefined);
  assert.equal((await call("me", "GET", null, a)).status, 401);
});
test("ranked zero-score cursors do not repeat content and profile pins precede newer posts", async () => {
  const first = await post(a, { body: "First" });
  const second = await post(a, { body: "Second" });
  const page1 = (await call("feed?mode=for-you&limit=1", "GET", null, b)).data;
  assert.equal(page1.next.score, 0);
  const q = new URLSearchParams({ ...page1.next, mode: "for-you", limit: "1" });
  const page2 = (await call("feed?" + q, "GET", null, b)).data;
  assert.notEqual(page1.items[0].id, page2.items[0].id);
  await call("posts/" + first.id, "PATCH", { pinned: 1 }, a);
  const profile = (await call("feed?author=" + a.id, "GET", null, b)).data;
  assert.equal(profile.items[0].id, first.id);
  assert.equal(profile.items[1].id, second.id);
});
test("restricted images cannot be fetched by guessing identifiers", async () => {
  const mid = crypto.randomUUID();
  database
    .prepare("INSERT INTO media(id,owner,type,size,created) VALUES (?,?,?,?,?)")
    .run(mid, a.id, "image/png", 8, Date.now());
  await env.BUCKET.put(mid, new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]));
  await post(a, { audience: "only_me", image: mid });
  assert.equal((await call("media/" + mid, "GET", null, b)).status, 404);
  assert.equal((await call("media/" + mid, "GET", null, a)).status, 200);
});
test("session revocation, recovery rotation and CSRF origin checks", async () => {
  assert.equal(
    (
      await call("me", "PATCH", { bio: "attack" }, a, {
        origin: "https://evil.test",
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await call("auth/recover", "POST", {
        email: a.email,
        recovery: "0".repeat(64),
        password: "new-passphrase-secure",
      })
    ).status,
    400,
  );
  const result = await call("auth/recover", "POST", {
    email: a.email,
    recovery: a.recovery,
    password: "new-passphrase-secure",
  });
  assert.equal(result.status, 200);
  assert.equal((await call("me", "GET", null, a)).status, 401);
  assert.equal(
    (
      await call("auth/recover", "POST", {
        email: a.email,
        recovery: a.recovery,
        password: "another-passphrase",
      })
    ).status,
    400,
  );
});
test("deleting content removes its notifications from readers", async () => {
  const p = await post(a);
  await call("posts/" + p.id + "/like", "POST", null, b);
  assert.equal(
    (await call("notifications", "GET", null, a)).data.items.length,
    1,
  );
  await call("posts/" + p.id, "DELETE", null, a);
  assert.equal(
    (await call("notifications", "GET", null, a)).data.items.length,
    0,
  );
});
test("drafts and preferences persist independently for different accounts", async () => {
  await call("drafts/post", "PUT", { body: "Alice draft" }, a);
  await call("drafts/post", "PUT", { body: "Bob draft" }, b);
  assert.equal(
    (await call("drafts/post", "GET", null, a)).data.value.body,
    "Alice draft",
  );
  assert.equal(
    (await call("drafts/post", "GET", null, b)).data.value.body,
    "Bob draft",
  );
  await call("me", "PATCH", { language: "ar", theme: "dark" }, a);
  const me = (await call("me", "GET", null, a)).data.user;
  assert.equal(me.language, "ar");
  assert.equal(me.theme, "dark");
  assert.equal((await call("me", "GET", null, b)).data.user.language, "en");
});
test("SSE publishes changes from real message writes and can reconnect", async () => {
  await call("me", "PATCH", { messages: "everyone" }, b);
  const conv = (await call("conversations", "POST", { userId: b.id }, a)).data
    .conversation;
  const connect = () =>
    api(
      new Request(
        "https://openly.test/api/conversations/" + conv.id + "/events",
        { headers: { authorization: "Bearer " + b.token } },
      ),
      env,
    );
  const stream = await connect();
  assert.equal(stream.headers.get("content-type"), "text/event-stream");
  const reader = stream.body.getReader();
  assert.match(
    new TextDecoder().decode((await reader.read()).value),
    /event: update/,
  );
  await call(
    "conversations/" + conv.id + "/messages",
    "POST",
    { id: crypto.randomUUID(), body: "Event-backed message" },
    a,
  );
  assert.match(
    new TextDecoder().decode((await reader.read()).value),
    /event: update/,
  );
  await reader.cancel();
  const reconnect = await connect();
  const again = reconnect.body.getReader();
  assert.match(
    new TextDecoder().decode((await again.read()).value),
    /event: update/,
  );
  await again.cancel();
});
test("a third account cannot access a conversation or acknowledge its messages", async () => {
  const outsider = await register("outsider");
  await call("me", "PATCH", { messages: "everyone" }, b);
  const conv = (await call("conversations", "POST", { userId: b.id }, a)).data
    .conversation;
  const mid = crypto.randomUUID();
  await call(
    "conversations/" + conv.id + "/messages",
    "POST",
    { id: mid, body: "Private" },
    a,
  );
  assert.equal(
    (
      await call(
        "conversations/" + conv.id + "/messages",
        "GET",
        null,
        outsider,
      )
    ).status,
    404,
  );
  assert.equal(
    (
      await call(
        "conversations/" + conv.id + "/ack",
        "POST",
        { ids: [mid], read: true },
        outsider,
      )
    ).status,
    404,
  );
  await call(
    "conversations/" + conv.id + "/ack",
    "POST",
    { ids: [mid], read: true },
    a,
  );
  assert.equal(
    (await call("conversations/" + conv.id + "/messages", "GET", null, a)).data
      .items[0].read,
    null,
  );
});
test("uploads validate bytes and interrupted uploads cannot leave accessible media", async () => {
  const bad = await api(
    new Request("https://openly.test/api/media", {
      method: "POST",
      headers: {
        authorization: "Bearer " + a.token,
        "content-type": "image/png",
      },
      body: "<script>not an image</script>",
    }),
    env,
  );
  assert.equal(bad.status, 400);
  assert.equal(database.prepare("SELECT count(*) n FROM media").get().n, 0);
  const valid = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  const uploaded = await api(
    new Request("https://openly.test/api/media", {
      method: "POST",
      headers: {
        authorization: "Bearer " + a.token,
        "content-type": "image/png",
      },
      body: valid,
    }),
    env,
  );
  assert.equal(uploaded.status, 201);
  const mid = (await uploaded.json()).id;
  assert.equal((await call("media/" + mid, "GET", null, b)).status, 404);
  const interrupted = new ReadableStream({
    pull(controller) {
      controller.error(new Error("simulated network interruption"));
    },
  });
  const failed = await api(
    new Request("https://openly.test/api/media", {
      method: "POST",
      duplex: "half",
      headers: {
        authorization: "Bearer " + a.token,
        "content-type": "image/png",
      },
      body: interrupted,
    }),
    env,
  );
  assert.equal(failed.status, 500);
  assert.equal(database.prepare("SELECT count(*) n FROM media").get().n, 1);
});
