\set ON_ERROR_STOP on
\timing on

SET search_path TO movie_analytics, public;

-- PK and UNIQUE constraints already index their key columns. The indexes below
-- support actual filters and reverse-direction joins used by the analyses.

CREATE INDEX IF NOT EXISTS idx_movies_release_year
    ON movies (release_year)
    WHERE release_year IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_movies_runtime
    ON movies (runtime_minutes)
    WHERE runtime_minutes IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ratings_rank
    ON movie_ratings (average_rating DESC, vote_count DESC);

CREATE INDEX IF NOT EXISTS idx_ratings_vote_count
    ON movie_ratings (vote_count DESC);

CREATE INDEX IF NOT EXISTS idx_movie_genres_genre_movie
    ON movie_genres (genre_id, movie_id);

CREATE INDEX IF NOT EXISTS idx_movie_directors_person_movie
    ON movie_directors (person_id, movie_id);

CREATE INDEX IF NOT EXISTS idx_principals_person_movie
    ON movie_principals (person_id, movie_id);

CREATE INDEX IF NOT EXISTS idx_principals_category_movie_person
    ON movie_principals (category_code, movie_id, person_id);

CREATE INDEX IF NOT EXISTS idx_principals_actor_pairs
    ON movie_principals (movie_id, person_id)
    WHERE category_code IN ('actor', 'actress');

ANALYZE;

-- EXPLAIN 01. Top rated films with an evidence threshold.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    m.title,
    mr.average_rating,
    mr.vote_count
FROM movie_ratings AS mr
JOIN movies AS m
    ON m.movie_id = mr.movie_id
WHERE mr.vote_count >= 1000
ORDER BY
    mr.average_rating DESC,
    mr.vote_count DESC
LIMIT 20;

-- EXPLAIN 02. Director filmography lookup uses the reverse FK index.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    md.person_id,
    COUNT(*) AS movie_count,
    AVG(mr.average_rating) AS avg_rating
FROM movie_directors AS md
JOIN movie_ratings AS mr
    ON mr.movie_id = md.movie_id
WHERE mr.vote_count >= 1000
GROUP BY md.person_id
HAVING COUNT(*) >= 5
ORDER BY avg_rating DESC
LIMIT 50;

-- EXPLAIN 03. Actor collaboration self join uses the partial actor index.
EXPLAIN (ANALYZE, BUFFERS)
WITH actor_films AS (
    SELECT DISTINCT
        movie_id,
        person_id
    FROM movie_principals
    WHERE category_code IN ('actor', 'actress')
)
SELECT
    a.person_id AS actor_1_id,
    b.person_id AS actor_2_id,
    COUNT(*) AS films_together
FROM actor_films AS a
JOIN actor_films AS b
    ON b.movie_id = a.movie_id
    AND a.person_id < b.person_id
GROUP BY
    a.person_id,
    b.person_id
HAVING COUNT(*) >= 5
ORDER BY films_together DESC
LIMIT 50;

-- Interpretation guide:
-- Seq Scan reads most or all table pages and can be optimal for broad queries.
-- Index Scan follows an index to selected rows and is useful for selective
-- predicates. Cost is the planner's estimate, while actual time and buffers are
-- observed runtime evidence. Compare plans only on the same warm/cold-cache and
-- hardware conditions; an index does not guarantee a faster plan.
