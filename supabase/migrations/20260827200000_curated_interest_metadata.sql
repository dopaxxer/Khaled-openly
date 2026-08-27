begin;

-- Curated works existed before catalog metadata was introduced. Keep their
-- existing IDs/user links intact and attach official Apple destinations so
-- native clients can recover artwork through Apple page metadata when the
-- search catalog does not return a direct image.
update public.interests
set external_url = 'https://tv.apple.com/de/movie/interstellar/umc.cmc.1vrwat5k1ucm5k42q97ioqyq3',
    release_year = coalesce(release_year, 2014)
where kind = 'movie' and label = 'Interstellar' and subtitle = 'Christopher Nolan';

update public.interests
set external_url = 'https://tv.apple.com/de/movie/fight-club/umc.cmc.70dbl3043tb6ealg0u12k1pih',
    release_year = coalesce(release_year, 1999)
where kind = 'movie' and label = 'Fight Club' and subtitle = 'David Fincher';

update public.interests
set external_url = 'https://tv.apple.com/de/movie/inception/umc.cmc.6loas01ow0w4lkatxxloz7a6e',
    release_year = coalesce(release_year, 2010)
where kind = 'movie' and label = 'Inception' and subtitle = 'Christopher Nolan';

update public.interests
set external_url = 'https://tv.apple.com/de/movie/her/umc.cmc.4ky5qbtddgx232de23d3bqr6i',
    release_year = coalesce(release_year, 2014)
where kind = 'movie' and label = 'Her' and subtitle = 'Spike Jonze';

update public.interests
set external_url = 'https://tv.apple.com/de/movie/the-matrix/umc.cmc.af8k9kcq9r1s1qmmdxpq4itn',
    release_year = coalesce(release_year, 1999)
where kind = 'movie' and label = 'The Matrix' and subtitle = 'The Wachowskis';

update public.interests
set external_url = 'https://tv.apple.com/de/movie/eternal-sunshine-of-the-spotless-mind/umc.cmc.4sao10xsyfeqf1t185lhrvo65?l=en',
    release_year = coalesce(release_year, 2004)
where kind = 'movie' and label = 'Eternal Sunshine of the Spotless Mind' and subtitle = 'Michel Gondry';

update public.interests
set external_url = 'https://books.apple.com/de/book/1984/id1602697097'
where kind = 'book' and label = '1984' and subtitle = 'George Orwell';

update public.interests
set external_url = 'https://books.apple.com/de/book/crime-and-punishment/id6555253146'
where kind = 'book' and label = 'Crime and Punishment' and subtitle = 'Fyodor Dostoevsky';

update public.interests
set external_url = 'https://books.apple.com/de/book/mans-search-for-meaning/id689246510'
where kind = 'book' and label = 'Man''s Search for Meaning' and subtitle = 'Viktor E. Frankl';

update public.interests
set external_url = 'https://books.apple.com/de/book/the-alchemist/id972750690?l=en-GB'
where kind = 'book' and label = 'The Alchemist' and subtitle = 'Paulo Coelho';

update public.interests
set external_url = 'https://books.apple.com/de/book/the-little-prince/id1139157775'
where kind = 'book' and label = 'The Little Prince' and subtitle = 'Antoine de Saint-Exupéry';

update public.interests
set external_url = 'https://books.apple.com/de/book/the-stranger/id548150919'
where kind = 'book' and label = 'The Stranger' and subtitle = 'Albert Camus';

commit;
