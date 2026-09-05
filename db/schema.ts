import {
  sqliteTable,
  text,
  integer,
  index,
  uniqueIndex,
  primaryKey,
} from "drizzle-orm/sqlite-core";
export const users = sqliteTable("users", {
  id: text().primaryKey(),
  email: text().notNull().unique(),
  username: text().notNull().unique(),
  password: text().notNull(),
  recovery: text().notNull(),
  name: text().notNull(),
  bio: text().notNull().default(""),
  avatar: text(),
  interests: text().notNull().default("[]"),
  song: text(),
  accent: text().notNull().default("blue"),
  private: integer().notNull().default(0),
  messages: text().notNull().default("requests"),
  receipts: integer().notNull().default(1),
  activity: integer().notNull().default(0),
  language: text().notNull().default("en"),
  theme: text().notNull().default("system"),
  onboarded: integer().notNull().default(0),
  notifications: text()
    .notNull()
    .default(
      '["like","comment","follow","follow_request","message_request","message"]',
    ),
  created: integer().notNull(),
});
export const sessions = sqliteTable("sessions", {
  token: text().primaryKey(),
  userId: text()
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  expires: integer().notNull(),
});
export const limits = sqliteTable("rate_limits", {
  key: text().primaryKey(),
  count: integer().notNull(),
  expires: integer().notNull(),
});
export const follows = sqliteTable(
  "follows",
  {
    follower: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    followed: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    status: text().notNull(),
    created: integer().notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.follower, t.followed] }),
    index("idx_followed_status").on(t.followed, t.status),
  ],
);
export const blocks = sqliteTable(
  "blocks",
  {
    blocker: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    blocked: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.blocker, t.blocked] })],
);
export const circles = sqliteTable("circles", {
  id: text().primaryKey(),
  owner: text()
    .notNull()
    .references(() => users.id),
  name: text().notNull(),
  description: text().notNull(),
  rules: text().notNull(),
  interest: text().notNull(),
  private: integer().notNull().default(0),
  created: integer().notNull(),
});
export const members = sqliteTable(
  "members",
  {
    circleId: text()
      .notNull()
      .references(() => circles.id, { onDelete: "cascade" }),
    userId: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    role: text().notNull().default("member"),
    status: text().notNull(),
    created: integer().notNull(),
  },
  (t) => [primaryKey({ columns: [t.circleId, t.userId] })],
);
export const posts = sqliteTable(
  "posts",
  {
    id: text().primaryKey(),
    author: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    body: text().notNull(),
    image: text(),
    song: text(),
    audience: text().notNull(),
    circleId: text().references(() => circles.id, { onDelete: "cascade" }),
    kind: text().notNull().default("post"),
    mood: text(),
    pinned: integer().notNull().default(0),
    expires: integer(),
    created: integer().notNull(),
    updated: integer(),
  },
  (t) => [
    index("idx_posts_created").on(t.created, t.id),
    index("idx_posts_author").on(t.author, t.created),
    index("idx_posts_circle").on(t.circleId, t.created),
  ],
);
export const comments = sqliteTable(
  "comments",
  {
    id: text().primaryKey(),
    postId: text()
      .notNull()
      .references(() => posts.id, { onDelete: "cascade" }),
    author: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    parent: text(),
    body: text().notNull(),
    created: integer().notNull(),
  },
  (t) => [index("idx_comments_post").on(t.postId, t.created)],
);
export const likes = sqliteTable(
  "likes",
  {
    postId: text()
      .notNull()
      .references(() => posts.id, { onDelete: "cascade" }),
    userId: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.postId, t.userId] })],
);
export const hidden = sqliteTable(
  "hidden",
  {
    postId: text()
      .notNull()
      .references(() => posts.id, { onDelete: "cascade" }),
    userId: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.postId, t.userId] })],
);
export const collections = sqliteTable("collections", {
  id: text().primaryKey(),
  owner: text()
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text().notNull(),
  created: integer().notNull(),
});
export const saves = sqliteTable(
  "saves",
  {
    collectionId: text()
      .notNull()
      .references(() => collections.id, { onDelete: "cascade" }),
    postId: text()
      .notNull()
      .references(() => posts.id, { onDelete: "cascade" }),
  },
  (t) => [primaryKey({ columns: [t.collectionId, t.postId] })],
);
export const conversations = sqliteTable(
  "conversations",
  {
    id: text().primaryKey(),
    a: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    b: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    initiator: text().notNull(),
    status: text().notNull(),
    created: integer().notNull(),
  },
  (t) => [uniqueIndex("idx_conversation_pair").on(t.a, t.b)],
);
export const conversationState = sqliteTable(
  "conversation_state",
  {
    conversationId: text()
      .notNull()
      .references(() => conversations.id, { onDelete: "cascade" }),
    userId: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    muted: integer().notNull().default(0),
    draft: text().notNull().default(""),
    typingUntil: integer().notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.conversationId, t.userId] })],
);
export const messages = sqliteTable(
  "messages",
  {
    id: text().primaryKey(),
    conversationId: text()
      .notNull()
      .references(() => conversations.id, { onDelete: "cascade" }),
    sender: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    body: text().notNull(),
    media: text(),
    replyTo: text(),
    created: integer().notNull(),
    delivered: integer(),
    read: integer(),
  },
  (t) => [
    index("idx_messages_conversation").on(t.conversationId, t.created, t.id),
  ],
);
export const reactions = sqliteTable(
  "reactions",
  {
    messageId: text()
      .notNull()
      .references(() => messages.id, { onDelete: "cascade" }),
    userId: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    emoji: text().notNull(),
  },
  (t) => [primaryKey({ columns: [t.messageId, t.userId] })],
);
export const media = sqliteTable(
  "media",
  {
    id: text().primaryKey(),
    owner: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    type: text().notNull(),
    size: integer().notNull(),
    created: integer().notNull(),
    expires: integer(),
    restricted: integer().notNull().default(0),
  },
  (t) => [index("idx_media_owner_created").on(t.owner, t.created)],
);
export const notifications = sqliteTable(
  "notifications",
  {
    id: text().primaryKey(),
    recipient: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    actor: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    type: text().notNull(),
    target: text().notNull(),
    read: integer(),
    created: integer().notNull(),
  },
  (t) => [index("idx_notifications_recipient").on(t.recipient, t.created)],
);
export const reports = sqliteTable("reports", {
  id: text().primaryKey(),
  reporter: text()
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  kind: text().notNull(),
  target: text().notNull(),
  circleId: text(),
  reason: text().notNull(),
  status: text().notNull().default("open"),
  created: integer().notNull(),
});
export const drafts = sqliteTable(
  "drafts",
  {
    userId: text()
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    key: text().notNull(),
    value: text().notNull(),
    updated: integer().notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.key] })],
);
export const devices = sqliteTable("devices", {
  token: text().primaryKey(),
  owner: text()
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  platform: text().notNull(),
  created: integer().notNull(),
});
