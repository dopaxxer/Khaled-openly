-- Interest search used LIKE '%' || query || '%'. A query of '%' or '_'
-- enumerated the catalog. Match with position() the same way search_posts does.

create or replace function private.search_interest_items(
  p_query text default null,
  p_kind text default null,
  p_limit integer default 30
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $search$
  with query as (
    select private.normalize_interest_text(p_query) as q,
      case when p_kind in ('book', 'movie', 'topic') then p_kind else null end as k
  ),
  ranked as (
    select interest,
      count(link.user_id)::bigint as popularity,
      query.q
    from public.interests interest
    cross join query
    left join public.user_interests link on link.interest_id = interest.id
    where (query.k is null or interest.kind = query.k)
      and (
        query.q = ''
        or position(query.q in interest.normalized_label) > 0
        or position(query.q in coalesce(interest.normalized_subtitle, '')) > 0
      )
    group by interest.id, query.q
    order by
      case when query.q <> '' and interest.normalized_label = query.q then 0
           when query.q <> '' and position(query.q in interest.normalized_label) = 1 then 1
           else 2 end,
      count(link.user_id) desc,
      interest.label asc
    limit greatest(1, least(coalesce(p_limit, 30), 50))
  )
  select coalesce(
    jsonb_agg(
      private.interest_json(ranked.interest)
      || jsonb_build_object('source', 'saved', 'popularity', ranked.popularity)
    ),
    '[]'::jsonb
  )
  from ranked;
$search$;
