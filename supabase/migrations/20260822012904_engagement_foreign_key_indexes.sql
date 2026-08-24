create index if not exists bookmarks_post_idx
  on private.bookmarks (post_id);
create index if not exists notifications_actor_idx
  on private.notifications (actor_id);
create index if not exists notifications_post_idx
  on private.notifications (post_id);
create index if not exists notifications_comment_idx
  on private.notifications (comment_id)
  where comment_id is not null;
