\set ON_ERROR_STOP on
\timing on

SET search_path TO movie_analytics, public;

-- PERFORMANCE TEST 01: top rated films.
-- Transactional DROP lets us observe the pre-index plan and then restore the
-- indexes with ROLLBACK, without permanently changing the project database.
BEGIN;
DROP INDEX idx_ratings_rank;
DROP INDEX idx_ratings_vote_count;

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

ROLLBACK;

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

-- PERFORMANCE TEST 02: eligible director aggregation.
BEGIN;
DROP INDEX idx_ratings_vote_count;

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

ROLLBACK;

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
