begin;

-- 20260827200000_curated_interest_metadata.sql backfilled "Her" with 2014.
-- Spike Jonze's film premiered and released in 2013; 2014 is the year its wide
-- release reached some markets, not the release year Apple and the catalog
-- report. A row that disagrees with the catalog re-sorts every time it is
-- refreshed from Apple, so correct it rather than editing the applied
-- migration, which would never re-run.
update public.interests
set release_year = 2013
where kind = 'movie'
  and label = 'Her'
  and subtitle = 'Spike Jonze'
  and release_year = 2014;

commit;
