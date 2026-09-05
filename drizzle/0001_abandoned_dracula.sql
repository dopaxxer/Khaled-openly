ALTER TABLE `media` ADD `expires` integer;--> statement-breakpoint
ALTER TABLE `media` ADD `restricted` integer DEFAULT 0 NOT NULL;