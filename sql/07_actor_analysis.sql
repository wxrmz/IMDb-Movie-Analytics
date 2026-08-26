\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- Repeated principal rows are possible, so actor-film pairs are deduplicated
-- before every film-level aggregation.

-- MEDIUM 05. Principal actors appearing in at least 10 rated films.
WITH actor_films AS (
    SELECT DISTINCT
        mp.person_id,
        mp.movie_id
    FROM movie_principals AS mp
    WHERE mp.category_code IN ('actor', 'actress')
)
SELECT
    p.person_id,
    p.person_name,
    COUNT(*) AS rated_movie_count,
    ROUND(AVG(mr.average_rating), 2) AS avg_movie_rating,
    ROUND(AVG(mr.vote_count), 0) AS avg_vote_count,
    SUM(mr.vote_count) AS total_vote_count
FROM actor_films AS af
JOIN persons AS p
    ON p.person_id = af.person_id
JOIN movie_ratings AS mr
    ON mr.movie_id = af.movie_id
WHERE
    p.person_name IS NOT NULL
    AND mr.vote_count >= 100
GROUP BY
    p.person_id,
    p.person_name
HAVING COUNT(*) >= 10
ORDER BY
    avg_movie_rating DESC,
    rated_movie_count DESC,
    total_vote_count DESC;

-- HARD 09. Actor ranking with Bayesian shrinkage.
WITH parameters AS (
    SELECT
        15.0 AS prior_movie_count,
        AVG(average_rating) AS global_mean
    FROM movie_ratings
    WHERE vote_count >= 500
), actor_films AS (
    SELECT DISTINCT
        mp.person_id,
        mp.movie_id
    FROM movie_principals AS mp
    WHERE mp.category_code IN ('actor', 'actress')
), actor_stats AS (
    SELECT
        p.person_id,
        p.person_name,
        COUNT(*) AS movie_count,
        AVG(mr.average_rating) AS avg_rating,
        AVG(LN(1 + mr.vote_count)) AS avg_log_votes,
        SUM(mr.vote_count) AS total_votes
    FROM actor_films AS af
    JOIN persons AS p
        ON p.person_id = af.person_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = af.movie_id
    WHERE
        p.person_name IS NOT NULL
        AND mr.vote_count >= 500
    GROUP BY
        p.person_id,
        p.person_name
), scored AS (
    SELECT
        ast.*,
        ast.movie_count / (ast.movie_count + p.prior_movie_count)
            * ast.avg_rating
        + p.prior_movie_count / (ast.movie_count + p.prior_movie_count)
            * p.global_mean AS actor_score
    FROM actor_stats AS ast
    CROSS JOIN parameters AS p
    WHERE ast.movie_count >= 10
)
SELECT
    person_id,
    person_name,
    movie_count,
    ROUND(avg_rating, 2) AS avg_rating,
    total_votes,
    ROUND(actor_score, 3) AS actor_score,
    DENSE_RANK() OVER (
        ORDER BY
            actor_score DESC,
            movie_count DESC,
            avg_log_votes DESC
    ) AS actor_rank
FROM scored
ORDER BY actor_rank
LIMIT 50;

-- HARD 10. Top principal actors by genre.
WITH actor_films AS (
    SELECT DISTINCT
        mp.person_id,
        mp.movie_id
    FROM movie_principals AS mp
    WHERE mp.category_code IN ('actor', 'actress')
), actor_genre_stats AS (
    SELECT
        g.genre_id,
        g.genre_name,
        p.person_id,
        p.person_name,
        COUNT(DISTINCT af.movie_id) AS movie_count,
        AVG(mr.average_rating) AS avg_rating,
        SUM(mr.vote_count) AS total_votes
    FROM actor_films AS af
    JOIN persons AS p
        ON p.person_id = af.person_id
    JOIN movie_genres AS mg
        ON mg.movie_id = af.movie_id
    JOIN genres AS g
        ON g.genre_id = mg.genre_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = af.movie_id
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
        ) AS genre_actor_rank
    FROM actor_genre_stats
    WHERE movie_count >= 5
)
SELECT
    genre_name,
    genre_actor_rank,
    person_name,
    movie_count,
    ROUND(avg_rating, 2) AS avg_rating,
    total_votes
FROM ranked
WHERE genre_actor_rank <= 3
ORDER BY
    genre_name,
    genre_actor_rank;

-- HARD 11 / SHOWCASE. Actor collaborations using a self join.
WITH actor_films AS (
    SELECT DISTINCT
        movie_id,
        person_id
    FROM movie_principals
    WHERE category_code IN ('actor', 'actress')
), collaboration_pairs AS (
    SELECT
        actor_a.person_id AS actor_1_id,
        actor_b.person_id AS actor_2_id,
        COUNT(*) AS films_together,
        AVG(mr.average_rating) AS avg_movie_rating,
        SUM(mr.vote_count) AS total_movie_votes
    FROM actor_films AS actor_a
    JOIN actor_films AS actor_b
        ON actor_b.movie_id = actor_a.movie_id
        AND actor_a.person_id < actor_b.person_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = actor_a.movie_id
    WHERE mr.vote_count >= 100
    GROUP BY
        actor_a.person_id,
        actor_b.person_id
)
SELECT
    p1.person_name AS actor_1,
    p2.person_name AS actor_2,
    cp.films_together,
    ROUND(cp.avg_movie_rating, 2) AS avg_movie_rating,
    cp.total_movie_votes
FROM collaboration_pairs AS cp
JOIN persons AS p1
    ON p1.person_id = cp.actor_1_id
JOIN persons AS p2
    ON p2.person_id = cp.actor_2_id
WHERE
    cp.films_together >= 5
    AND p1.person_name IS NOT NULL
    AND p2.person_name IS NOT NULL
ORDER BY
    cp.films_together DESC,
    avg_movie_rating DESC,
    actor_1,
    actor_2
LIMIT 100;

-- MEDIUM 06. Actor genre breadth.
WITH actor_films AS (
    SELECT DISTINCT
        movie_id,
        person_id
    FROM movie_principals
    WHERE category_code IN ('actor', 'actress')
)
SELECT
    p.person_id,
    p.person_name,
    COUNT(DISTINCT af.movie_id) AS movie_count,
    COUNT(DISTINCT mg.genre_id) AS genre_count,
    STRING_AGG(DISTINCT g.genre_name, ', ' ORDER BY g.genre_name)
        AS represented_genres
FROM actor_films AS af
JOIN persons AS p
    ON p.person_id = af.person_id
JOIN movie_genres AS mg
    ON mg.movie_id = af.movie_id
JOIN genres AS g
    ON g.genre_id = mg.genre_id
WHERE p.person_name IS NOT NULL
GROUP BY
    p.person_id,
    p.person_name
HAVING COUNT(DISTINCT af.movie_id) >= 20
ORDER BY
    genre_count DESC,
    movie_count DESC
LIMIT 100;

-- HARD 12. Change in an actor's rated-film average by decade.
WITH actor_films AS (
    SELECT DISTINCT
        movie_id,
        person_id
    FROM movie_principals
    WHERE category_code IN ('actor', 'actress')
), actor_decade_stats AS (
    SELECT
        af.person_id,
        (m.release_year / 10) * 10 AS decade_start,
        COUNT(*) AS movie_count,
        AVG(mr.average_rating) AS avg_rating
    FROM actor_films AS af
    JOIN movies AS m
        ON m.movie_id = af.movie_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = af.movie_id
    WHERE
        m.release_year BETWEEN 1900
        AND EXTRACT(YEAR FROM CURRENT_DATE)
        AND mr.vote_count >= 100
    GROUP BY
        af.person_id,
        decade_start
), with_previous AS (
    SELECT
        *,
        LAG(avg_rating) OVER (
            PARTITION BY person_id
            ORDER BY decade_start
        ) AS previous_decade_avg
    FROM actor_decade_stats
    WHERE movie_count >= 3
)
SELECT
    p.person_name,
    w.decade_start || 's' AS decade,
    w.movie_count,
    ROUND(w.avg_rating, 2) AS avg_rating,
    ROUND(w.previous_decade_avg, 2) AS previous_decade_avg,
    ROUND(w.avg_rating - w.previous_decade_avg, 2) AS rating_change
FROM with_previous AS w
JOIN persons AS p
    ON p.person_id = w.person_id
WHERE
    w.previous_decade_avg IS NOT NULL
    AND p.person_name IS NOT NULL
ORDER BY
    ABS(w.avg_rating - w.previous_decade_avg) DESC,
    p.person_name
LIMIT 100;
