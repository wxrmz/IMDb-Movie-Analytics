\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

CREATE OR REPLACE VIEW v_movie_details AS
WITH movie_genre_lists AS (
    SELECT
        mg.movie_id,
        STRING_AGG(g.genre_name, ', ' ORDER BY g.genre_name) AS genres
    FROM movie_genres AS mg
    JOIN genres AS g
        ON g.genre_id = mg.genre_id
    GROUP BY mg.movie_id
), movie_director_lists AS (
    SELECT
        md.movie_id,
        STRING_AGG(
            COALESCE(p.person_name, p.person_id),
            ', '
            ORDER BY md.director_order
        ) AS directors
    FROM movie_directors AS md
    JOIN persons AS p
        ON p.person_id = md.person_id
    GROUP BY md.movie_id
)
SELECT
    m.movie_id,
    m.title,
    m.original_title,
    m.release_year,
    m.runtime_minutes,
    mr.average_rating,
    mr.vote_count,
    mdl.directors,
    mgl.genres
FROM movies AS m
LEFT JOIN movie_ratings AS mr
    ON mr.movie_id = m.movie_id
LEFT JOIN movie_director_lists AS mdl
    ON mdl.movie_id = m.movie_id
LEFT JOIN movie_genre_lists AS mgl
    ON mgl.movie_id = m.movie_id;

COMMENT ON VIEW v_movie_details IS
    'One row per movie with optional rating and readable genre/director lists.';

CREATE OR REPLACE VIEW v_director_stats AS
SELECT
    p.person_id,
    p.person_name,
    COUNT(DISTINCT md.movie_id) AS movie_count,
    COUNT(DISTINCT mr.movie_id) AS rated_movie_count,
    ROUND(AVG(mr.average_rating), 2) AS avg_rating,
    MIN(mr.average_rating) AS min_rating,
    MAX(mr.average_rating) AS max_rating,
    ROUND(STDDEV_SAMP(mr.average_rating), 2) AS rating_stddev,
    SUM(mr.vote_count) AS total_vote_count
FROM persons AS p
JOIN movie_directors AS md
    ON md.person_id = p.person_id
LEFT JOIN movie_ratings AS mr
    ON mr.movie_id = md.movie_id
GROUP BY
    p.person_id,
    p.person_name;

COMMENT ON VIEW v_director_stats IS
    'Reusable director filmography, rating, dispersion, and vote statistics.';

CREATE OR REPLACE VIEW v_actor_stats AS
WITH actor_films AS (
    SELECT DISTINCT
        person_id,
        movie_id
    FROM movie_principals
    WHERE category_code IN ('actor', 'actress')
)
SELECT
    p.person_id,
    p.person_name,
    COUNT(*) AS movie_count,
    COUNT(mr.movie_id) AS rated_movie_count,
    ROUND(AVG(mr.average_rating), 2) AS avg_rating,
    SUM(mr.vote_count) AS total_vote_count
FROM actor_films AS af
JOIN persons AS p
    ON p.person_id = af.person_id
LEFT JOIN movie_ratings AS mr
    ON mr.movie_id = af.movie_id
GROUP BY
    p.person_id,
    p.person_name;

COMMENT ON VIEW v_actor_stats IS
    'Deduplicated principal actor filmography and aggregate rating statistics.';
