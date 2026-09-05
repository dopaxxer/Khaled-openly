CREATE TABLE `blocks` (
	`blocker` text NOT NULL,
	`blocked` text NOT NULL,
	PRIMARY KEY(`blocker`, `blocked`),
	FOREIGN KEY (`blocker`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`blocked`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `circles` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`name` text NOT NULL,
	`description` text NOT NULL,
	`rules` text NOT NULL,
	`interest` text NOT NULL,
	`private` integer DEFAULT 0 NOT NULL,
	`created` integer NOT NULL,
	FOREIGN KEY (`owner`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `collections` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`name` text NOT NULL,
	`created` integer NOT NULL,
	FOREIGN KEY (`owner`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `comments` (
	`id` text PRIMARY KEY NOT NULL,
	`postId` text NOT NULL,
	`author` text NOT NULL,
	`parent` text,
	`body` text NOT NULL,
	`created` integer NOT NULL,
	FOREIGN KEY (`postId`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`author`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_comments_post` ON `comments` (`postId`,`created`);--> statement-breakpoint
CREATE TABLE `conversation_state` (
	`conversationId` text NOT NULL,
	`userId` text NOT NULL,
	`muted` integer DEFAULT 0 NOT NULL,
	`draft` text DEFAULT '' NOT NULL,
	`typingUntil` integer DEFAULT 0 NOT NULL,
	PRIMARY KEY(`conversationId`, `userId`),
	FOREIGN KEY (`conversationId`) REFERENCES `conversations`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `conversations` (
	`id` text PRIMARY KEY NOT NULL,
	`a` text NOT NULL,
	`b` text NOT NULL,
	`initiator` text NOT NULL,
	`status` text NOT NULL,
	`created` integer NOT NULL,
	FOREIGN KEY (`a`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`b`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_conversation_pair` ON `conversations` (`a`,`b`);--> statement-breakpoint
CREATE TABLE `devices` (
	`token` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`platform` text NOT NULL,
	`created` integer NOT NULL,
	FOREIGN KEY (`owner`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `drafts` (
	`userId` text NOT NULL,
	`key` text NOT NULL,
	`value` text NOT NULL,
	`updated` integer NOT NULL,
	PRIMARY KEY(`userId`, `key`),
	FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `follows` (
	`follower` text NOT NULL,
	`followed` text NOT NULL,
	`status` text NOT NULL,
	`created` integer NOT NULL,
	PRIMARY KEY(`follower`, `followed`),
	FOREIGN KEY (`follower`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`followed`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_followed_status` ON `follows` (`followed`,`status`);--> statement-breakpoint
CREATE TABLE `hidden` (
	`postId` text NOT NULL,
	`userId` text NOT NULL,
	PRIMARY KEY(`postId`, `userId`),
	FOREIGN KEY (`postId`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `likes` (
	`postId` text NOT NULL,
	`userId` text NOT NULL,
	PRIMARY KEY(`postId`, `userId`),
	FOREIGN KEY (`postId`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `rate_limits` (
	`key` text PRIMARY KEY NOT NULL,
	`count` integer NOT NULL,
	`expires` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `media` (
	`id` text PRIMARY KEY NOT NULL,
	`owner` text NOT NULL,
	`type` text NOT NULL,
	`size` integer NOT NULL,
	`created` integer NOT NULL,
	FOREIGN KEY (`owner`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_media_owner_created` ON `media` (`owner`,`created`);--> statement-breakpoint
CREATE TABLE `members` (
	`circleId` text NOT NULL,
	`userId` text NOT NULL,
	`role` text DEFAULT 'member' NOT NULL,
	`status` text NOT NULL,
	`created` integer NOT NULL,
	PRIMARY KEY(`circleId`, `userId`),
	FOREIGN KEY (`circleId`) REFERENCES `circles`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `messages` (
	`id` text PRIMARY KEY NOT NULL,
	`conversationId` text NOT NULL,
	`sender` text NOT NULL,
	`body` text NOT NULL,
	`media` text,
	`replyTo` text,
	`created` integer NOT NULL,
	`delivered` integer,
	`read` integer,
	FOREIGN KEY (`conversationId`) REFERENCES `conversations`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`sender`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_messages_conversation` ON `messages` (`conversationId`,`created`,`id`);--> statement-breakpoint
CREATE TABLE `notifications` (
	`id` text PRIMARY KEY NOT NULL,
	`recipient` text NOT NULL,
	`actor` text NOT NULL,
	`type` text NOT NULL,
	`target` text NOT NULL,
	`read` integer,
	`created` integer NOT NULL,
	FOREIGN KEY (`recipient`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`actor`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_notifications_recipient` ON `notifications` (`recipient`,`created`);--> statement-breakpoint
CREATE TABLE `posts` (
	`id` text PRIMARY KEY NOT NULL,
	`author` text NOT NULL,
	`body` text NOT NULL,
	`image` text,
	`song` text,
	`audience` text NOT NULL,
	`circleId` text,
	`kind` text DEFAULT 'post' NOT NULL,
	`mood` text,
	`pinned` integer DEFAULT 0 NOT NULL,
	`expires` integer,
	`created` integer NOT NULL,
	`updated` integer,
	FOREIGN KEY (`author`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`circleId`) REFERENCES `circles`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `idx_posts_created` ON `posts` (`created`,`id`);--> statement-breakpoint
CREATE INDEX `idx_posts_author` ON `posts` (`author`,`created`);--> statement-breakpoint
CREATE INDEX `idx_posts_circle` ON `posts` (`circleId`,`created`);--> statement-breakpoint
CREATE TABLE `reactions` (
	`messageId` text NOT NULL,
	`userId` text NOT NULL,
	`emoji` text NOT NULL,
	PRIMARY KEY(`messageId`, `userId`),
	FOREIGN KEY (`messageId`) REFERENCES `messages`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `reports` (
	`id` text PRIMARY KEY NOT NULL,
	`reporter` text NOT NULL,
	`kind` text NOT NULL,
	`target` text NOT NULL,
	`circleId` text,
	`reason` text NOT NULL,
	`status` text DEFAULT 'open' NOT NULL,
	`created` integer NOT NULL,
	FOREIGN KEY (`reporter`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `saves` (
	`collectionId` text NOT NULL,
	`postId` text NOT NULL,
	PRIMARY KEY(`collectionId`, `postId`),
	FOREIGN KEY (`collectionId`) REFERENCES `collections`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`postId`) REFERENCES `posts`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `sessions` (
	`token` text PRIMARY KEY NOT NULL,
	`userId` text NOT NULL,
	`expires` integer NOT NULL,
	FOREIGN KEY (`userId`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY NOT NULL,
	`email` text NOT NULL,
	`username` text NOT NULL,
	`password` text NOT NULL,
	`recovery` text NOT NULL,
	`name` text NOT NULL,
	`bio` text DEFAULT '' NOT NULL,
	`avatar` text,
	`interests` text DEFAULT '[]' NOT NULL,
	`song` text,
	`accent` text DEFAULT 'blue' NOT NULL,
	`private` integer DEFAULT 0 NOT NULL,
	`messages` text DEFAULT 'requests' NOT NULL,
	`receipts` integer DEFAULT 1 NOT NULL,
	`activity` integer DEFAULT 0 NOT NULL,
	`language` text DEFAULT 'en' NOT NULL,
	`theme` text DEFAULT 'system' NOT NULL,
	`onboarded` integer DEFAULT 0 NOT NULL,
	`notifications` text DEFAULT '["like","comment","follow","follow_request","message_request","message"]' NOT NULL,
	`created` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `users_email_unique` ON `users` (`email`);--> statement-breakpoint
CREATE UNIQUE INDEX `users_username_unique` ON `users` (`username`);