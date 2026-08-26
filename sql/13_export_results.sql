\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

COPY (
    SELECT
        FLOOR(average_rating * 2) / 2 AS rating_band_start,
        COUNT(*) AS movie_count
    FROM movie_ratings
    GROUP BY rating_band_start
    ORDER BY rating_band_start
) TO '/results/rating_distribution.csv' WITH (FORMAT csv, HEADER true);

COPY (
    SELECT
        g.genre_name,
        COUNT(*) AS movie_count
    FROM genres AS g
    JOIN movie_genres AS mg
        ON mg.genre_id = g.genre_id
    GROUP BY
        g.genre_id,
        g.genre_name
    ORDER BY movie_count DESC
    LIMIT 15
) TO '/results/top_genres.csv' WITH (FORMAT csv, HEADER true);

COPY (
    WITH parameters AS (
        SELECT
            10.0 AS prior_movie_count,
            AVG(average_rating) AS global_mean
        FROM movie_ratings
        WHERE vote_count >= 1000
    ), director_stats AS (
        SELECT
            p.person_id,
            p.person_name,
            COUNT(DISTINCT md.movie_id) AS movie_count,
            AVG(mr.average_rating) AS avg_rating,
            SUM(mr.vote_count) AS total_vote_count
        FROM persons AS p
        JOIN movie_directors AS md
            ON md.person_id = p.person_id
        JOIN movie_ratings AS mr
            ON mr.movie_id = md.movie_id
        WHERE
            p.person_name IS NOT NULL
            AND mr.vote_count >= 1000
        GROUP BY
            p.person_id,
            p.person_name
        HAVING COUNT(DISTINCT md.movie_id) >= 5
    )
    SELECT
        ds.person_name,
        ds.movie_count,
        ROUND(ds.avg_rating, 2) AS avg_rating,
        ROUND((
            ds.movie_count / (ds.movie_count + p.prior_movie_count)
                * ds.avg_rating
            + p.prior_movie_count
                / (ds.movie_count + p.prior_movie_count)
                * p.global_mean
        )::NUMERIC, 3) AS director_score
    FROM director_stats AS ds
    CROSS JOIN parameters AS p
    ORDER BY
        director_score DESC,
        ds.movie_count DESC,
        ds.total_vote_count DESC
    LIMIT 15
) TO '/results/director_ranking.csv' WITH (FORMAT csv, HEADER true);

COPY (
    WITH yearly_movies AS (
        SELECT
            release_year,
            COUNT(*) AS movie_count
        FROM movies
        WHERE release_year BETWEEN 1950 AND 2025
        GROUP BY release_year
    )
    SELECT
        release_year,
        movie_count,
        ROUND(AVG(movie_count) OVER (
            ORDER BY release_year
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2) AS moving_avg_3_years
    FROM yearly_movies
    ORDER BY release_year
) TO '/results/movie_release_trend.csv' WITH (FORMAT csv, HEADER true);
