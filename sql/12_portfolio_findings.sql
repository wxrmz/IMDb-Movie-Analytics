\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- F01. Largest genres in the complete catalog.
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
LIMIT 10;

-- F02. Highest-rated substantial genres.
SELECT
    g.genre_name,
    COUNT(*) AS rated_movie_count,
    ROUND(AVG(mr.average_rating), 2) AS avg_rating
FROM genres AS g
JOIN movie_genres AS mg
    ON mg.genre_id = g.genre_id
JOIN movie_ratings AS mr
    ON mr.movie_id = mg.movie_id
WHERE mr.vote_count >= 1000
GROUP BY
    g.genre_id,
    g.genre_name
HAVING COUNT(*) >= 100
ORDER BY avg_rating DESC
LIMIT 10;

-- F03. Top films using the normalized Movie Score.
WITH eligible_movies AS (
    SELECT
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
        PERCENT_RANK() OVER (ORDER BY average_rating) AS rating_score,
        PERCENT_RANK() OVER (ORDER BY LN(1 + vote_count)) AS attention_score
    FROM eligible_movies
)
SELECT
    title,
    release_year,
    average_rating,
    vote_count,
    ROUND((0.70 * rating_score + 0.30 * attention_score)::NUMERIC, 4)
        AS movie_score
FROM normalized
ORDER BY
    movie_score DESC,
    average_rating DESC,
    vote_count DESC
LIMIT 10;

-- F04. Most frequent principal-actor collaborations.
WITH actor_films AS (
    SELECT DISTINCT
        movie_id,
        person_id
    FROM movie_principals
    WHERE category_code IN ('actor', 'actress')
), pairs AS (
    SELECT
        a.person_id AS actor_1_id,
        b.person_id AS actor_2_id,
        COUNT(*) AS films_together,
        AVG(mr.average_rating) AS avg_rating
    FROM actor_films AS a
    JOIN actor_films AS b
        ON b.movie_id = a.movie_id
        AND a.person_id < b.person_id
    JOIN movie_ratings AS mr
        ON mr.movie_id = a.movie_id
    WHERE mr.vote_count >= 100
    GROUP BY
        a.person_id,
        b.person_id
)
SELECT
    p1.person_name AS actor_1,
    p2.person_name AS actor_2,
    pairs.films_together,
    ROUND(pairs.avg_rating, 2) AS avg_movie_rating
FROM pairs
JOIN persons AS p1
    ON p1.person_id = pairs.actor_1_id
JOIN persons AS p2
    ON p2.person_id = pairs.actor_2_id
WHERE
    p1.person_name IS NOT NULL
    AND p2.person_name IS NOT NULL
ORDER BY
    pairs.films_together DESC,
    avg_movie_rating DESC
LIMIT 10;

-- F05. Relationship between rating and rating activity.
SELECT
    COUNT(*) AS movie_count,
    ROUND(CORR(average_rating, vote_count)::NUMERIC, 4)
        AS raw_vote_correlation,
    ROUND(CORR(average_rating, LN(1 + vote_count))::NUMERIC, 4)
        AS log_vote_correlation
FROM movie_ratings
WHERE vote_count >= 100;

-- F06. Release-volume change between the last two complete five-year windows.
SELECT
    COUNT(*) FILTER (WHERE release_year BETWEEN 2011 AND 2015)
        AS movies_2011_2015,
    COUNT(*) FILTER (WHERE release_year BETWEEN 2016 AND 2020)
        AS movies_2016_2020,
    ROUND(
        100.0 * (
            COUNT(*) FILTER (WHERE release_year BETWEEN 2016 AND 2020)
            - COUNT(*) FILTER (WHERE release_year BETWEEN 2011 AND 2015)
        ) / NULLIF(
            COUNT(*) FILTER (WHERE release_year BETWEEN 2011 AND 2015),
            0
        ),
        2
    ) AS change_pct
FROM movies;
