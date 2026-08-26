\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- EDA01. Dataset overview and analytical coverage.
SELECT
    COUNT(*) AS movie_count,
    MIN(release_year) AS min_release_year,
    MAX(release_year) AS max_release_year,
    COUNT(DISTINCT release_year) AS represented_years,
    COUNT(*) FILTER (WHERE release_year IS NULL) AS movies_without_year,
    COUNT(*) FILTER (WHERE runtime_minutes IS NULL) AS movies_without_runtime
FROM movies;

SELECT
    (SELECT COUNT(*) FROM genres) AS genre_count,
    (SELECT COUNT(*) FROM persons) AS referenced_person_count,
    (SELECT COUNT(DISTINCT person_id) FROM movie_directors) AS director_count,
    (SELECT COUNT(DISTINCT person_id)
     FROM movie_principals
     WHERE category_code IN ('actor', 'actress')) AS principal_actor_count;

-- Countries and original languages are unavailable in the selected IMDb files.
-- The project documents this limitation instead of inferring them from titles.

-- EDA02. Movies by year. Future announced titles are excluded.
SELECT
    release_year,
    COUNT(*) AS movie_count
FROM movies
WHERE
    release_year IS NOT NULL
    AND release_year <= EXTRACT(YEAR FROM CURRENT_DATE)
GROUP BY release_year
ORDER BY release_year;

-- EDA03. Rating distribution in half-point bands.
SELECT
    FLOOR(average_rating * 2) / 2 AS rating_band_start,
    COUNT(*) AS movie_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS movie_share_pct
FROM movie_ratings
GROUP BY rating_band_start
ORDER BY rating_band_start;

-- EDA04. Runtime summary with median and quartiles.
SELECT
    ROUND(AVG(runtime_minutes), 2) AS avg_runtime,
    PERCENTILE_CONT(0.25) WITHIN GROUP (
        ORDER BY runtime_minutes
    ) AS q1_runtime,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY runtime_minutes
    ) AS median_runtime,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
        ORDER BY runtime_minutes
    ) AS q3_runtime,
    MIN(runtime_minutes) AS min_runtime,
    MAX(runtime_minutes) AS max_runtime
FROM movies
WHERE runtime_minutes IS NOT NULL;

-- EDA05. Top genres by distinct movie count.
SELECT
    g.genre_name,
    COUNT(DISTINCT mg.movie_id) AS movie_count,
    ROUND(
        100.0 * COUNT(DISTINCT mg.movie_id)
        / (SELECT COUNT(*) FROM movies),
        2
    ) AS catalog_share_pct
FROM genres AS g
JOIN movie_genres AS mg
    ON mg.genre_id = g.genre_id
GROUP BY
    g.genre_id,
    g.genre_name
ORDER BY
    movie_count DESC,
    g.genre_name;

-- EDA06. Principal-credit category mix.
SELECT
    category_code,
    COUNT(*) AS credit_count,
    COUNT(DISTINCT movie_id) AS represented_movies,
    COUNT(DISTINCT person_id) AS represented_people
FROM movie_principals
GROUP BY category_code
ORDER BY credit_count DESC;

-- EDA07. Rating and vote-count summary. Median is safer than the mean for the
-- highly skewed vote-count distribution.
SELECT
    COUNT(*) AS rated_movies,
    ROUND(AVG(average_rating), 2) AS avg_rating,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY average_rating
    ) AS median_rating,
    ROUND(AVG(vote_count), 2) AS avg_vote_count,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY vote_count
    ) AS median_vote_count,
    MAX(vote_count) AS max_vote_count
FROM movie_ratings;
