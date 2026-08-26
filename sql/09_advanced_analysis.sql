\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- HARD 18 / SHOWCASE. Under-discovered movies within their release decade.
-- Definition: at least 100 votes, top quartile rating, but bottom half attention
-- among eligible films in the same decade. This is a relative metric, not an
-- objective statement about a film's quality or commercial success.
WITH eligible_movies AS (
    SELECT
        m.movie_id,
        m.title,
        m.release_year,
        (m.release_year / 10) * 10 AS decade_start,
        mr.average_rating,
        mr.vote_count
    FROM movies AS m
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
        AND mr.vote_count >= 100
), percentiles AS (
    SELECT
        *,
        PERCENT_RANK() OVER (
            PARTITION BY decade_start
            ORDER BY average_rating
        ) AS rating_percentile,
        PERCENT_RANK() OVER (
            PARTITION BY decade_start
            ORDER BY vote_count
        ) AS attention_percentile
    FROM eligible_movies
)
SELECT
    title,
    release_year,
    average_rating,
    vote_count,
    ROUND((100 * rating_percentile)::NUMERIC, 1) AS rating_percentile,
    ROUND((100 * attention_percentile)::NUMERIC, 1) AS attention_percentile
FROM percentiles
WHERE
    rating_percentile >= 0.75
    AND attention_percentile <= 0.50
ORDER BY
    rating_percentile DESC,
    attention_percentile,
    vote_count DESC
LIMIT 100;

-- HARD 19. Metric-defined overexposed movies.
-- High attention plus a rating in the bottom half of same-decade peers.
WITH eligible_movies AS (
    SELECT
        m.movie_id,
        m.title,
        m.release_year,
        (m.release_year / 10) * 10 AS decade_start,
        mr.average_rating,
        mr.vote_count
    FROM movies AS m
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
        AND mr.vote_count >= 100
), percentiles AS (
    SELECT
        *,
        PERCENT_RANK() OVER (
            PARTITION BY decade_start
            ORDER BY average_rating
        ) AS rating_percentile,
        PERCENT_RANK() OVER (
            PARTITION BY decade_start
            ORDER BY vote_count
        ) AS attention_percentile
    FROM eligible_movies
)
SELECT
    title,
    release_year,
    average_rating,
    vote_count,
    ROUND((100 * rating_percentile)::NUMERIC, 1) AS rating_percentile,
    ROUND((100 * attention_percentile)::NUMERIC, 1) AS attention_percentile
FROM percentiles
WHERE
    attention_percentile >= 0.75
    AND rating_percentile <= 0.50
ORDER BY
    attention_percentile DESC,
    rating_percentile,
    vote_count DESC
LIMIT 100;

-- HARD 20. Custom Movie Score.
-- Rating and log(votes) are converted to percentiles before combination, so
-- unlike raw addition they share a common 0-1 scale. Rating receives 70% weight
-- and attention receives 30%.
WITH eligible_movies AS (
    SELECT
        m.movie_id,
        m.title,
        m.release_year,
        mr.average_rating,
        mr.vote_count
    FROM movies AS m
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE mr.vote_count >= 1000
), normalized AS (
    SELECT
        *,
        PERCENT_RANK() OVER (
            ORDER BY average_rating
        ) AS rating_score,
        PERCENT_RANK() OVER (
            ORDER BY LN(1 + vote_count)
        ) AS attention_score
    FROM eligible_movies
), scored AS (
    SELECT
        *,
        0.70 * rating_score + 0.30 * attention_score AS movie_score
    FROM normalized
)
SELECT
    DENSE_RANK() OVER (
        ORDER BY
            movie_score DESC,
            average_rating DESC,
            vote_count DESC
    ) AS movie_rank,
    title,
    release_year,
    average_rating,
    vote_count,
    ROUND(movie_score::NUMERIC, 4) AS movie_score
FROM scored
ORDER BY movie_rank
LIMIT 20;

-- HARD 21. Similar films for one target movie.
-- Similarity combines genre Jaccard overlap, rating distance, release-year
-- distance, and runtime distance. Change target_movie_id in params.
WITH params AS (
    SELECT 'tt0111161'::TEXT AS target_movie_id
), target AS (
    SELECT
        m.movie_id,
        m.title,
        m.release_year,
        m.runtime_minutes,
        mr.average_rating,
        COUNT(mg.genre_id)::INTEGER AS genre_count
    FROM movies AS m
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    JOIN movie_genres AS mg
        ON mg.movie_id = m.movie_id
    JOIN params AS p
        ON p.target_movie_id = m.movie_id
    GROUP BY
        m.movie_id,
        m.title,
        m.release_year,
        m.runtime_minutes,
        mr.average_rating
), target_genres AS (
    SELECT mg.genre_id
    FROM movie_genres AS mg
    JOIN params AS p
        ON p.target_movie_id = mg.movie_id
), candidate_features AS (
    SELECT
        m.movie_id,
        m.title,
        m.release_year,
        m.runtime_minutes,
        mr.average_rating,
        COUNT(mg.genre_id)::INTEGER AS genre_count
    FROM movies AS m
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    JOIN movie_genres AS mg
        ON mg.movie_id = m.movie_id
    WHERE mr.vote_count >= 1000
    GROUP BY
        m.movie_id,
        m.title,
        m.release_year,
        m.runtime_minutes,
        mr.average_rating
), genre_overlaps AS (
    SELECT
        mg.movie_id,
        COUNT(*)::INTEGER AS overlap_count
    FROM movie_genres AS mg
    JOIN target_genres AS tg
        ON tg.genre_id = mg.genre_id
    GROUP BY mg.movie_id
), candidates AS (
    SELECT
        c.movie_id,
        c.title,
        c.release_year,
        c.runtime_minutes,
        c.average_rating,
        COALESCE(go.overlap_count, 0)::NUMERIC
            / NULLIF(c.genre_count + t.genre_count - COALESCE(go.overlap_count, 0), 0)
                AS genre_jaccard,
        ABS(c.average_rating - t.average_rating) AS rating_distance,
        ABS(c.release_year - t.release_year) AS year_distance,
        ABS(c.runtime_minutes - t.runtime_minutes) AS runtime_distance
    FROM candidate_features AS c
    CROSS JOIN target AS t
    LEFT JOIN genre_overlaps AS go
        ON go.movie_id = c.movie_id
    WHERE
        c.movie_id <> t.movie_id
        AND c.release_year IS NOT NULL
        AND t.release_year IS NOT NULL
        AND c.runtime_minutes IS NOT NULL
        AND t.runtime_minutes IS NOT NULL
), scored AS (
    SELECT
        *,
        0.55 * genre_jaccard
        + 0.25 * (1 - LEAST(rating_distance / 10.0, 1))
        + 0.10 * (1 - LEAST(year_distance / 50.0, 1))
        + 0.10 * (1 - LEAST(runtime_distance / 180.0, 1))
            AS similarity_score
    FROM candidates
)
SELECT
    title,
    release_year,
    runtime_minutes,
    average_rating,
    ROUND(genre_jaccard, 3) AS genre_jaccard,
    ROUND(similarity_score, 3) AS similarity_score
FROM scored
ORDER BY
    similarity_score DESC,
    title
LIMIT 20;

-- HARD 22. Compare each film with its genre's rating average without collapsing
-- the original movie rows. Multi-genre films appear once per genre.
SELECT
    g.genre_name,
    m.title,
    m.release_year,
    mr.average_rating,
    ROUND(
        AVG(mr.average_rating) OVER (
            PARTITION BY g.genre_id
        ),
        2
    ) AS genre_avg_rating,
    ROUND(
        mr.average_rating
        - AVG(mr.average_rating) OVER (
            PARTITION BY g.genre_id
        ),
        2
    ) AS difference_from_genre_avg,
    COUNT(*) OVER (
        PARTITION BY g.genre_id
    ) AS genre_rated_movie_count
FROM genres AS g
JOIN movie_genres AS mg
    ON mg.genre_id = g.genre_id
JOIN movies AS m
    ON m.movie_id = mg.movie_id
JOIN movie_ratings AS mr
    ON mr.movie_id = m.movie_id
WHERE mr.vote_count >= 1000
ORDER BY
    g.genre_name,
    difference_from_genre_avg DESC;

-- HARD 23. Rating quartiles within each decade using NTILE.
WITH rated_movies AS (
    SELECT
        m.title,
        m.release_year,
        (m.release_year / 10) * 10 AS decade_start,
        mr.average_rating,
        mr.vote_count,
        NTILE(4) OVER (
            PARTITION BY (m.release_year / 10) * 10
            ORDER BY mr.average_rating
        ) AS rating_quartile
    FROM movies AS m
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
        AND mr.vote_count >= 100
)
SELECT
    decade_start || 's' AS decade,
    rating_quartile,
    COUNT(*) AS movie_count,
    ROUND(AVG(average_rating), 2) AS avg_rating,
    ROUND(AVG(vote_count), 0) AS avg_vote_count
FROM rated_movies
GROUP BY
    decade_start,
    rating_quartile
ORDER BY
    decade_start,
    rating_quartile;

-- HARD 24. Top film per genre and decade using ROW_NUMBER.
WITH ranked AS (
    SELECT
        g.genre_name,
        (m.release_year / 10) * 10 AS decade_start,
        m.title,
        mr.average_rating,
        mr.vote_count,
        ROW_NUMBER() OVER (
            PARTITION BY
                g.genre_id,
                (m.release_year / 10) * 10
            ORDER BY
                mr.average_rating DESC,
                mr.vote_count DESC,
                m.movie_id
        ) AS movie_row_number
    FROM genres AS g
    JOIN movie_genres AS mg
        ON mg.genre_id = g.genre_id
    JOIN movies AS m
        ON m.movie_id = mg.movie_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
        AND mr.vote_count >= 1000
)
SELECT
    genre_name,
    decade_start || 's' AS decade,
    title,
    average_rating,
    vote_count
FROM ranked
WHERE movie_row_number = 1
ORDER BY
    genre_name,
    decade_start;
