\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- MEDIUM 01. Genre performance with conditional aggregation.
SELECT
    g.genre_name,
    COUNT(DISTINCT mg.movie_id) AS all_movies,
    COUNT(DISTINCT mg.movie_id) FILTER (
        WHERE mr.movie_id IS NOT NULL
    ) AS rated_movies,
    COUNT(DISTINCT mg.movie_id) FILTER (
        WHERE mr.vote_count >= 1000
    ) AS strongly_rated_movies,
    ROUND(AVG(mr.average_rating), 2) AS avg_rating,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY mr.average_rating
    ) AS median_rating
FROM genres AS g
JOIN movie_genres AS mg
    ON mg.genre_id = g.genre_id
LEFT JOIN movie_ratings AS mr
    ON mr.movie_id = mg.movie_id
GROUP BY
    g.genre_id,
    g.genre_name
ORDER BY all_movies DESC;

-- HARD 01 / SHOWCASE. Top 3 films per genre.
-- RANK keeps ties. The vote threshold prevents tiny samples from winning.
WITH eligible_movies AS (
    SELECT
        g.genre_id,
        g.genre_name,
        m.movie_id,
        m.title,
        m.release_year,
        mr.average_rating,
        mr.vote_count
    FROM genres AS g
    JOIN movie_genres AS mg
        ON mg.genre_id = g.genre_id
    JOIN movies AS m
        ON m.movie_id = mg.movie_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE mr.vote_count >= 1000
), ranked_movies AS (
    SELECT
        genre_name,
        movie_id,
        title,
        release_year,
        average_rating,
        vote_count,
        RANK() OVER (
            PARTITION BY genre_id
            ORDER BY
                average_rating DESC,
                vote_count DESC
        ) AS genre_rank
    FROM eligible_movies
)
SELECT
    genre_name,
    genre_rank,
    title,
    release_year,
    average_rating,
    vote_count
FROM ranked_movies
WHERE genre_rank <= 3
ORDER BY
    genre_name,
    genre_rank,
    title;

-- HARD 02. Most released genre in each decade.
WITH genre_decade_counts AS (
    SELECT
        (m.release_year / 10) * 10 AS decade_start,
        g.genre_id,
        g.genre_name,
        COUNT(DISTINCT m.movie_id) AS movie_count
    FROM movies AS m
    JOIN movie_genres AS mg
        ON mg.movie_id = m.movie_id
    JOIN genres AS g
        ON g.genre_id = mg.genre_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY
        decade_start,
        g.genre_id,
        g.genre_name
), ranked_genres AS (
    SELECT
        decade_start,
        genre_name,
        movie_count,
        DENSE_RANK() OVER (
            PARTITION BY decade_start
            ORDER BY movie_count DESC
        ) AS genre_rank
    FROM genre_decade_counts
)
SELECT
    decade_start,
    decade_start || 's' AS decade,
    genre_name,
    movie_count
FROM ranked_genres
WHERE genre_rank = 1
ORDER BY decade_start;

-- HARD 03 / SHOWCASE. Annual genre share and year-over-year change.
-- Because films can have multiple genres, genre shares do not sum to 100%.
WITH yearly_movie_counts AS (
    SELECT
        release_year,
        COUNT(*) AS all_movie_count
    FROM movies
    WHERE
        release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY release_year
), yearly_genre_counts AS (
    SELECT
        m.release_year,
        g.genre_id,
        g.genre_name,
        COUNT(DISTINCT m.movie_id) AS genre_movie_count
    FROM movies AS m
    JOIN movie_genres AS mg
        ON mg.movie_id = m.movie_id
    JOIN genres AS g
        ON g.genre_id = mg.genre_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
    GROUP BY
        m.release_year,
        g.genre_id,
        g.genre_name
), genre_shares AS (
    SELECT
        ygc.release_year,
        ygc.genre_id,
        ygc.genre_name,
        ygc.genre_movie_count,
        100.0 * ygc.genre_movie_count
            / NULLIF(ymc.all_movie_count, 0) AS genre_share_pct
    FROM yearly_genre_counts AS ygc
    JOIN yearly_movie_counts AS ymc
        ON ymc.release_year = ygc.release_year
), genre_change AS (
    SELECT
        release_year,
        genre_name,
        genre_movie_count,
        genre_share_pct,
        LAG(genre_share_pct) OVER (
            PARTITION BY genre_id
            ORDER BY release_year
        ) AS previous_year_share_pct
    FROM genre_shares
)
SELECT
    release_year,
    genre_name,
    genre_movie_count,
    ROUND(genre_share_pct, 2) AS genre_share_pct,
    ROUND(previous_year_share_pct, 2) AS previous_year_share_pct,
    ROUND(genre_share_pct - previous_year_share_pct, 2)
        AS share_change_pp
FROM genre_change
ORDER BY
    genre_name,
    release_year;

-- HARD 04. Long-term genre direction: compare two complete five-year windows.
WITH windowed_genres AS (
    SELECT
        g.genre_name,
        CASE
            WHEN m.release_year BETWEEN 2011 AND 2015 THEN '2011-2015'
            WHEN m.release_year BETWEEN 2016 AND 2020 THEN '2016-2020'
        END AS period,
        COUNT(DISTINCT m.movie_id) AS genre_movie_count
    FROM movies AS m
    JOIN movie_genres AS mg
        ON mg.movie_id = m.movie_id
    JOIN genres AS g
        ON g.genre_id = mg.genre_id
    WHERE m.release_year BETWEEN 2011 AND 2020
    GROUP BY
        g.genre_name,
        period
), period_totals AS (
    SELECT
        CASE
            WHEN release_year BETWEEN 2011 AND 2015 THEN '2011-2015'
            WHEN release_year BETWEEN 2016 AND 2020 THEN '2016-2020'
        END AS period,
        COUNT(*) AS all_movie_count
    FROM movies
    WHERE release_year BETWEEN 2011 AND 2020
    GROUP BY period
), shares AS (
    SELECT
        wg.genre_name,
        wg.period,
        100.0 * wg.genre_movie_count / NULLIF(pt.all_movie_count, 0)
            AS share_pct
    FROM windowed_genres AS wg
    JOIN period_totals AS pt
        ON pt.period = wg.period
)
SELECT
    genre_name,
    ROUND(MAX(share_pct) FILTER (WHERE period = '2011-2015'), 2)
        AS share_2011_2015,
    ROUND(MAX(share_pct) FILTER (WHERE period = '2016-2020'), 2)
        AS share_2016_2020,
    ROUND(
        MAX(share_pct) FILTER (WHERE period = '2016-2020')
        - MAX(share_pct) FILTER (WHERE period = '2011-2015'),
        2
    ) AS share_change_pp
FROM shares
GROUP BY genre_name
ORDER BY share_change_pp DESC NULLS LAST;

-- MEDIUM 02. Rating gap between a genre and the complete rated population.
WITH global_rating AS (
    SELECT AVG(average_rating) AS global_avg_rating
    FROM movie_ratings
    WHERE vote_count >= 100
)
SELECT
    g.genre_name,
    COUNT(*) AS movie_count,
    ROUND(AVG(mr.average_rating), 2) AS genre_avg_rating,
    ROUND(AVG(mr.average_rating) - gr.global_avg_rating, 2)
        AS difference_from_global
FROM genres AS g
JOIN movie_genres AS mg
    ON mg.genre_id = g.genre_id
JOIN movie_ratings AS mr
    ON mr.movie_id = mg.movie_id
CROSS JOIN global_rating AS gr
WHERE mr.vote_count >= 100
GROUP BY
    g.genre_id,
    g.genre_name,
    gr.global_avg_rating
HAVING COUNT(*) >= 100
ORDER BY difference_from_global DESC;
