\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- MEDIUM 03. Directors with at least five rated films.
WITH director_stats AS (
    SELECT
        p.person_id,
        p.person_name,
        COUNT(DISTINCT m.movie_id) AS movie_count,
        ROUND(AVG(mr.average_rating), 2) AS avg_rating,
        ROUND(AVG(mr.vote_count), 0) AS avg_vote_count,
        SUM(mr.vote_count) AS total_vote_count
    FROM persons AS p
    JOIN movie_directors AS md
        ON md.person_id = p.person_id
    JOIN movies AS m
        ON m.movie_id = md.movie_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE
        p.person_name IS NOT NULL
        AND mr.vote_count >= 100
    GROUP BY
        p.person_id,
        p.person_name
)
SELECT
    person_id,
    person_name,
    movie_count,
    avg_rating,
    avg_vote_count,
    total_vote_count
FROM director_stats
WHERE movie_count >= 5
ORDER BY
    avg_rating DESC,
    movie_count DESC,
    total_vote_count DESC;

-- HARD 05 / SHOWCASE. Bayesian-style director ranking.
-- R is the director's mean film rating, C is the eligible global mean,
-- v is film count, and m=10 is the reliability prior:
-- score = v/(v+m)*R + m/(v+m)*C.
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
), scored_directors AS (
    SELECT
        ds.*,
        (
            ds.movie_count / (ds.movie_count + p.prior_movie_count)
        ) * ds.avg_rating
        + (
            p.prior_movie_count / (ds.movie_count + p.prior_movie_count)
        ) * p.global_mean AS director_score
    FROM director_stats AS ds
    CROSS JOIN parameters AS p
    WHERE ds.movie_count >= 5
)
SELECT
    person_id,
    person_name,
    movie_count,
    ROUND(avg_rating, 2) AS avg_rating,
    total_vote_count,
    ROUND(director_score, 3) AS director_score,
    DENSE_RANK() OVER (
        ORDER BY
            director_score DESC,
            movie_count DESC,
            total_vote_count DESC
    ) AS director_rank
FROM scored_directors
ORDER BY director_rank
LIMIT 50;

-- HARD 06. Stable directors: high average with low rating dispersion.
WITH director_consistency AS (
    SELECT
        p.person_id,
        p.person_name,
        COUNT(DISTINCT md.movie_id) AS movie_count,
        AVG(mr.average_rating) AS avg_rating,
        MIN(mr.average_rating) AS min_rating,
        MAX(mr.average_rating) AS max_rating,
        STDDEV_SAMP(mr.average_rating) AS rating_stddev
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
)
SELECT
    person_id,
    person_name,
    movie_count,
    ROUND(avg_rating, 2) AS avg_rating,
    min_rating,
    max_rating,
    ROUND(rating_stddev, 2) AS rating_stddev
FROM director_consistency
WHERE
    movie_count >= 5
    AND avg_rating >= 6.5
ORDER BY
    rating_stddev ASC,
    avg_rating DESC,
    movie_count DESC;

-- HARD 07. A director's film sequence with LAG and LEAD.
WITH director_films AS (
    SELECT
        p.person_id,
        p.person_name,
        m.movie_id,
        m.title,
        m.release_year,
        mr.average_rating,
        LAG(mr.average_rating) OVER (
            PARTITION BY p.person_id
            ORDER BY
                m.release_year,
                m.movie_id
        ) AS previous_film_rating,
        LEAD(mr.average_rating) OVER (
            PARTITION BY p.person_id
            ORDER BY
                m.release_year,
                m.movie_id
        ) AS next_film_rating
    FROM persons AS p
    JOIN movie_directors AS md
        ON md.person_id = p.person_id
    JOIN movies AS m
        ON m.movie_id = md.movie_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = m.movie_id
    WHERE
        p.person_name IS NOT NULL
        AND m.release_year IS NOT NULL
        AND mr.vote_count >= 100
)
SELECT
    person_name,
    title,
    release_year,
    average_rating,
    previous_film_rating,
    ROUND(average_rating - previous_film_rating, 1) AS change_from_previous,
    next_film_rating
FROM director_films
WHERE previous_film_rating IS NOT NULL
ORDER BY
    person_name,
    release_year,
    movie_id;

-- MEDIUM 04. Director hit rate using conditional aggregation.
SELECT
    p.person_id,
    p.person_name,
    COUNT(DISTINCT md.movie_id) AS rated_movie_count,
    COUNT(DISTINCT md.movie_id) FILTER (
        WHERE mr.average_rating >= 7.0 AND mr.vote_count >= 1000
    ) AS high_rated_movie_count,
    ROUND(
        100.0 * COUNT(DISTINCT md.movie_id) FILTER (
            WHERE mr.average_rating >= 7.0 AND mr.vote_count >= 1000
        ) / NULLIF(COUNT(DISTINCT md.movie_id), 0),
        2
    ) AS high_rated_share_pct
FROM persons AS p
JOIN movie_directors AS md
    ON md.person_id = p.person_id
JOIN movie_ratings AS mr
    ON mr.movie_id = md.movie_id
WHERE
    p.person_name IS NOT NULL
    AND mr.vote_count >= 100
GROUP BY
    p.person_id,
    p.person_name
HAVING COUNT(DISTINCT md.movie_id) >= 10
ORDER BY
    high_rated_share_pct DESC,
    rated_movie_count DESC;

-- HARD 08. Best directors within each genre.
WITH director_genre_stats AS (
    SELECT
        g.genre_id,
        g.genre_name,
        p.person_id,
        p.person_name,
        COUNT(DISTINCT md.movie_id) AS movie_count,
        AVG(mr.average_rating) AS avg_rating,
        SUM(mr.vote_count) AS total_votes
    FROM genres AS g
    JOIN movie_genres AS mg
        ON mg.genre_id = g.genre_id
    JOIN movie_directors AS md
        ON md.movie_id = mg.movie_id
    JOIN persons AS p
        ON p.person_id = md.person_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = md.movie_id
    WHERE
        p.person_name IS NOT NULL
        AND mr.vote_count >= 500
    GROUP BY
        g.genre_id,
        g.genre_name,
        p.person_id,
        p.person_name
), ranked AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY genre_id
            ORDER BY
                avg_rating DESC,
                movie_count DESC,
                total_votes DESC
        ) AS genre_director_rank
    FROM director_genre_stats
    WHERE movie_count >= 3
)
SELECT
    genre_name,
    genre_director_rank,
    person_name,
    movie_count,
    ROUND(avg_rating, 2) AS avg_rating,
    total_votes
FROM ranked
WHERE genre_director_rank <= 3
ORDER BY
    genre_name,
    genre_director_rank;
