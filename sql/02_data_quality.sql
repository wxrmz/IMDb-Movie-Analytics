\set ON_ERROR_STOP on
\timing on

SET search_path TO movie_analytics, staging, public;

-- DQ01. Row counts and the latest load audit.
SELECT
    load_id,
    source_name,
    snapshot_date,
    loaded_at,
    movie_filter,
    row_counts
FROM dataset_loads
ORDER BY load_id DESC
LIMIT 1;

-- DQ02. NULL profile for the clean movie catalog.
SELECT
    COUNT(*) AS movie_count,
    COUNT(*) FILTER (WHERE release_year IS NULL) AS release_year_nulls,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE release_year IS NULL) / COUNT(*),
        2
    ) AS release_year_null_pct,
    COUNT(*) FILTER (WHERE runtime_minutes IS NULL) AS runtime_nulls,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE runtime_minutes IS NULL) / COUNT(*),
        2
    ) AS runtime_null_pct,
    COUNT(*) FILTER (WHERE mr.movie_id IS NULL) AS rating_nulls,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE mr.movie_id IS NULL) / COUNT(*),
        2
    ) AS rating_null_pct
FROM movies AS m
LEFT JOIN movie_ratings AS mr
    ON mr.movie_id = m.movie_id;

-- DQ03. IMDb does not provide budget, revenue, or popularity in this source.
-- These measures are documented as unavailable rather than represented by
-- misleading zero-filled columns.

-- DQ04. Candidate-key duplicates in staging. Clean-table PKs prevent them.
SELECT
    'title_basics.tconst' AS tested_key,
    COUNT(*) AS duplicated_key_groups
FROM (
    SELECT tconst
    FROM staging.title_basics
    GROUP BY tconst
    HAVING COUNT(*) > 1
) AS duplicates

UNION ALL

SELECT
    'title_ratings.tconst',
    COUNT(*)
FROM (
    SELECT tconst
    FROM staging.title_ratings
    GROUP BY tconst
    HAVING COUNT(*) > 1
) AS duplicates

UNION ALL

SELECT
    'title_principals.(tconst,ordering)',
    COUNT(*)
FROM (
    SELECT tconst, ordering
    FROM staging.title_principals
    GROUP BY tconst, ordering
    HAVING COUNT(*) > 1
) AS duplicates;

-- DQ05. Same title and year are possible remakes or collisions, not automatic
-- duplicates. Review the largest groups before making any removal decision.
SELECT
    title,
    release_year,
    COUNT(*) AS movie_count,
    ARRAY_AGG(movie_id ORDER BY movie_id) AS movie_ids
FROM movies
GROUP BY
    title,
    release_year
HAVING COUNT(*) > 1
ORDER BY
    movie_count DESC,
    title
LIMIT 50;

-- DQ06. Impossible values in the clean model should return zero rows because
-- CHECK constraints reject them.
SELECT
    COUNT(*) FILTER (
        WHERE average_rating < 0 OR average_rating > 10
    ) AS invalid_ratings,
    COUNT(*) FILTER (WHERE vote_count < 0) AS negative_vote_counts
FROM movie_ratings;

SELECT
    COUNT(*) FILTER (WHERE runtime_minutes <= 0) AS nonpositive_runtimes,
    COUNT(*) FILTER (
        WHERE release_year < 1870 OR release_year > 2100
    ) AS invalid_release_years
FROM movies;

-- DQ07. Future years may describe announced titles. Do not delete them; exclude
-- them explicitly from historical trend analyses.
SELECT
    release_year,
    COUNT(*) AS movie_count
FROM movies
WHERE release_year > EXTRACT(YEAR FROM CURRENT_DATE)
GROUP BY release_year
ORDER BY release_year;

-- DQ08. Runtime outliers using IQR rather than an arbitrary hard cutoff.
WITH runtime_quartiles AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (
            ORDER BY runtime_minutes
        ) AS q1,
        PERCENTILE_CONT(0.50) WITHIN GROUP (
            ORDER BY runtime_minutes
        ) AS median,
        PERCENTILE_CONT(0.75) WITHIN GROUP (
            ORDER BY runtime_minutes
        ) AS q3
    FROM movies
    WHERE runtime_minutes IS NOT NULL
), bounds AS (
    SELECT
        q1,
        median,
        q3,
        q1 - 1.5 * (q3 - q1) AS lower_bound,
        q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM runtime_quartiles
)
SELECT
    b.q1,
    b.median,
    b.q3,
    b.lower_bound,
    b.upper_bound,
    COUNT(*) FILTER (
        WHERE m.runtime_minutes > b.upper_bound
    ) AS high_outlier_count
FROM movies AS m
CROSS JOIN bounds AS b
GROUP BY
    b.q1,
    b.median,
    b.q3,
    b.lower_bound,
    b.upper_bound;

-- DQ09. Inspect extreme runtimes. Long festival compilations and serial films
-- may be legitimate, so the query surfaces records without deleting them.
SELECT
    movie_id,
    title,
    release_year,
    runtime_minutes
FROM movies
WHERE runtime_minutes > 600
ORDER BY runtime_minutes DESC
LIMIT 100;

-- DQ10. Referential integrity checks. Expected result: all zeros.
SELECT
    (SELECT COUNT(*)
     FROM movie_ratings AS mr
     LEFT JOIN movies AS m ON m.movie_id = mr.movie_id
     WHERE m.movie_id IS NULL) AS orphan_ratings,
    (SELECT COUNT(*)
     FROM movie_genres AS mg
     LEFT JOIN movies AS m ON m.movie_id = mg.movie_id
     LEFT JOIN genres AS g ON g.genre_id = mg.genre_id
     WHERE m.movie_id IS NULL OR g.genre_id IS NULL) AS orphan_genres,
    (SELECT COUNT(*)
     FROM movie_directors AS md
     LEFT JOIN movies AS m ON m.movie_id = md.movie_id
     LEFT JOIN persons AS p ON p.person_id = md.person_id
     WHERE m.movie_id IS NULL OR p.person_id IS NULL) AS orphan_directors,
    (SELECT COUNT(*)
     FROM movie_principals AS mp
     LEFT JOIN movies AS m ON m.movie_id = mp.movie_id
     LEFT JOIN persons AS p ON p.person_id = mp.person_id
     WHERE m.movie_id IS NULL OR p.person_id IS NULL) AS orphan_principals;

-- DQ11. Coverage by analytical domain.
SELECT
    COUNT(*) AS all_movies,
    COUNT(mr.movie_id) AS rated_movies,
    COUNT(*) FILTER (WHERE mr.vote_count >= 1000) AS ranking_eligible_movies,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM movie_directors AS md
            WHERE md.movie_id = m.movie_id
        )
    ) AS movies_with_directors,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM movie_principals AS mp
            WHERE mp.movie_id = m.movie_id
                AND mp.category_code IN ('actor', 'actress')
        )
    ) AS movies_with_principal_actors
FROM movies AS m
LEFT JOIN movie_ratings AS mr
    ON mr.movie_id = m.movie_id;

-- DQ12. Rating evidence: low-vote ratings are valid but unreliable for ranking.
SELECT
    CASE
        WHEN vote_count < 10 THEN '01: <10'
        WHEN vote_count < 100 THEN '02: 10-99'
        WHEN vote_count < 1000 THEN '03: 100-999'
        WHEN vote_count < 10000 THEN '04: 1k-9,999'
        ELSE '05: 10k+'
    END AS vote_band,
    COUNT(*) AS movie_count,
    ROUND(AVG(average_rating), 2) AS avg_rating
FROM movie_ratings
GROUP BY vote_band
ORDER BY vote_band;

-- Recommended remediation policy:
-- 1. Preserve unknown values as NULL.
-- 2. Never delete title collisions using title alone.
-- 3. Keep future announced films, but exclude them from historical trends.
-- 4. Use explicit vote thresholds for rankings.
-- 5. Quarantine or manually review extreme runtimes before any correction.
