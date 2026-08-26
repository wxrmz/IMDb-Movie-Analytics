\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- MEDIUM 07. Decade summary. The top genre is calculated separately to avoid
-- multiplying movies that have several genres.
WITH decade_metrics AS (
    SELECT
        (m.release_year / 10) * 10 AS decade_start,
        COUNT(DISTINCT m.movie_id) AS movie_count,
        ROUND(AVG(mr.average_rating), 2) AS avg_rating,
        ROUND(AVG(m.runtime_minutes), 2) AS avg_runtime,
        ROUND(AVG(mr.vote_count), 0) AS avg_vote_count
    FROM movies AS m
    LEFT JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE m.release_year BETWEEN 1900 AND 2029
    GROUP BY decade_start
), genre_counts AS (
    SELECT
        (m.release_year / 10) * 10 AS decade_start,
        g.genre_name,
        COUNT(DISTINCT m.movie_id) AS genre_movie_count,
        ROW_NUMBER() OVER (
            PARTITION BY (m.release_year / 10) * 10
            ORDER BY
                COUNT(DISTINCT m.movie_id) DESC,
                g.genre_name
        ) AS genre_row_number
    FROM movies AS m
    JOIN movie_genres AS mg
        ON mg.movie_id = m.movie_id
    JOIN genres AS g
        ON g.genre_id = mg.genre_id
    WHERE m.release_year BETWEEN 1900 AND 2029
    GROUP BY
        decade_start,
        g.genre_name
)
SELECT
    dm.decade_start || 's' AS decade,
    dm.movie_count,
    dm.avg_rating,
    dm.avg_runtime,
    dm.avg_vote_count,
    gc.genre_name AS top_genre,
    gc.genre_movie_count AS top_genre_movie_count
FROM decade_metrics AS dm
LEFT JOIN genre_counts AS gc
    ON gc.decade_start = dm.decade_start
    AND gc.genre_row_number = 1
ORDER BY dm.decade_start;

-- HARD 13. Three-year moving average of movie releases.
WITH yearly_movies AS (
    SELECT
        release_year,
        COUNT(*) AS movie_count
    FROM movies
    WHERE
        release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY release_year
)
SELECT
    release_year,
    movie_count,
    ROUND(
        AVG(movie_count) OVER (
            ORDER BY release_year
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS moving_avg_3_years
FROM yearly_movies
ORDER BY release_year;

-- HARD 14. Year-over-year release growth.
WITH yearly_movies AS (
    SELECT
        release_year,
        COUNT(*) AS movie_count
    FROM movies
    WHERE
        release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY release_year
), with_previous AS (
    SELECT
        release_year,
        movie_count,
        LAG(movie_count) OVER (
            ORDER BY release_year
        ) AS previous_year_count
    FROM yearly_movies
)
SELECT
    release_year,
    movie_count,
    previous_year_count,
    movie_count - previous_year_count AS absolute_change,
    ROUND(
        100.0 * (movie_count - previous_year_count)
        / NULLIF(previous_year_count, 0),
        2
    ) AS percentage_change
FROM with_previous
ORDER BY release_year;

-- HARD 15. Cumulative number of catalogued films over time.
WITH yearly_movies AS (
    SELECT
        release_year,
        COUNT(*) AS movie_count
    FROM movies
    WHERE
        release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY release_year
)
SELECT
    release_year,
    movie_count,
    SUM(movie_count) OVER (
        ORDER BY release_year
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_movie_count,
    COUNT(*) OVER () AS represented_year_count
FROM yearly_movies
ORDER BY release_year;

-- MEDIUM 08. Rating and vote-count trends by decade.
SELECT
    (m.release_year / 10) * 10 AS decade_start,
    COUNT(*) AS rated_movie_count,
    ROUND(AVG(mr.average_rating), 2) AS avg_rating,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY mr.average_rating
    ) AS median_rating,
    ROUND(AVG(mr.vote_count), 0) AS avg_vote_count,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY mr.vote_count
    ) AS median_vote_count
FROM movies AS m
JOIN movie_ratings AS mr
    ON mr.movie_id = m.movie_id
WHERE
    m.release_year BETWEEN 1900
    AND EXTRACT(YEAR FROM CURRENT_DATE)
GROUP BY decade_start
ORDER BY decade_start;

-- HARD 16. Correlation between rating and attention.
-- The logarithm reduces vote-count skew. Correlation does not imply causation.
SELECT
    COUNT(*) AS movie_count,
    ROUND(CORR(average_rating, vote_count)::NUMERIC, 4)
        AS rating_votes_correlation,
    ROUND(CORR(average_rating, LN(1 + vote_count))::NUMERIC, 4)
        AS rating_log_votes_correlation
FROM movie_ratings
WHERE vote_count >= 100;

-- HARD 17. Best-rated and most-voted movie in every year and whether they match.
WITH ranked_movies AS (
    SELECT
        m.release_year,
        m.movie_id,
        m.title,
        mr.average_rating,
        mr.vote_count,
        ROW_NUMBER() OVER (
            PARTITION BY m.release_year
            ORDER BY
                mr.average_rating DESC,
                mr.vote_count DESC,
                m.movie_id
        ) AS rating_row_number,
        ROW_NUMBER() OVER (
            PARTITION BY m.release_year
            ORDER BY
                mr.vote_count DESC,
                mr.average_rating DESC,
                m.movie_id
        ) AS votes_row_number
    FROM movies AS m
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
        AND mr.vote_count >= 1000
), yearly_winners AS (
    SELECT
        release_year,
        MAX(movie_id) FILTER (WHERE rating_row_number = 1)
            AS top_rating_movie_id,
        MAX(title) FILTER (WHERE rating_row_number = 1)
            AS top_rating_movie,
        MAX(movie_id) FILTER (WHERE votes_row_number = 1)
            AS top_votes_movie_id,
        MAX(title) FILTER (WHERE votes_row_number = 1)
            AS top_votes_movie
    FROM ranked_movies
    GROUP BY release_year
)
SELECT
    release_year,
    top_rating_movie,
    top_votes_movie,
    top_rating_movie_id = top_votes_movie_id AS same_movie
FROM yearly_winners
ORDER BY release_year;
