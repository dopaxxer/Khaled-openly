create index if not exists direct_message_presence_user_idx
  on private.direct_message_presence (user_id, last_seen_at desc);
