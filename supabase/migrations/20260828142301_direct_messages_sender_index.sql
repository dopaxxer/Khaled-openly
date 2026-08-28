create index if not exists direct_messages_sender_idx
  on private.direct_messages (sender_id, created_at desc);
