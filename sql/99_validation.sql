\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

DO $$
DECLARE
    movie_count BIGINT;
    orphan_count BIGINT;
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO movie_count FROM movies;
    IF movie_count < 100000 THEN
        RAISE EXCEPTION 'Unexpectedly small movie table: % rows', movie_count;
    END IF;

    SELECT COUNT(*)
    INTO orphan_count
    FROM movie_principals AS mp
    LEFT JOIN movies AS m
        ON m.movie_id = mp.movie_id
    LEFT JOIN persons AS p
        ON p.person_id = mp.person_id
    WHERE m.movie_id IS NULL OR p.person_id IS NULL;

    IF orphan_count <> 0 THEN
        RAISE EXCEPTION 'movie_principals has % orphan rows', orphan_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_count
    FROM movie_ratings
    WHERE
        average_rating NOT BETWEEN 0 AND 10
        OR vote_count < 0;

    IF invalid_count <> 0 THEN
        RAISE EXCEPTION 'movie_ratings has % invalid rows', invalid_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_count
    FROM movie_principals
    WHERE
        characters IS NOT NULL
        AND JSONB_TYPEOF(characters) <> 'array';

    IF invalid_count <> 0 THEN
        RAISE EXCEPTION 'movie_principals has % invalid character payloads',
            invalid_count;
    END IF;
END
$$;

SELECT
    'movies' AS table_name,
    COUNT(*) AS row_count
FROM movies

UNION ALL

SELECT 'movie_ratings', COUNT(*) FROM movie_ratings

UNION ALL

SELECT 'genres', COUNT(*) FROM genres

UNION ALL

SELECT 'movie_genres', COUNT(*) FROM movie_genres

UNION ALL

SELECT 'persons', COUNT(*) FROM persons

UNION ALL

SELECT 'movie_directors', COUNT(*) FROM movie_directors

UNION ALL

SELECT 'movie_principals', COUNT(*) FROM movie_principals
ORDER BY table_name;
