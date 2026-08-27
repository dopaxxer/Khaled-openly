create index if not exists interests_created_by_idx
  on public.interests (created_by)
  where created_by is not null;
