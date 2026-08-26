\set ON_ERROR_STOP on

SET search_path TO movie_analytics, public;

-- EASY 01. Top 10 highly rated films with enough rating evidence.
-- Concepts: SELECT, JOIN, WHERE, ORDER BY, LIMIT.
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
ORDER BY
    mr.average_rating DESC,
    mr.vote_count DESC,
    m.title
LIMIT 10;

-- EASY 02. Most common genres.
-- Concepts: JOIN, COUNT, GROUP BY, ORDER BY.
SELECT
    g.genre_name,
    COUNT(*) AS movie_count
FROM genres AS g
JOIN movie_genres AS mg
    ON mg.genre_id = g.genre_id
GROUP BY
    g.genre_id,
    g.genre_name
ORDER BY
    movie_count DESC,
    g.genre_name
LIMIT 10;

-- EASY 03. Average rating by genre with a meaningful sample requirement.
-- Concepts: multiple JOINs, AVG, HAVING.
SELECT
    g.genre_name,
    COUNT(*) AS rated_movie_count,
    ROUND(AVG(mr.average_rating), 2) AS avg_rating
FROM genres AS g
JOIN movie_genres AS mg
    ON mg.genre_id = g.genre_id
JOIN movie_ratings AS mr
    ON mr.movie_id = mg.movie_id
WHERE mr.vote_count >= 100
GROUP BY
    g.genre_id,
    g.genre_name
HAVING COUNT(*) >= 100
ORDER BY
    avg_rating DESC,
    rated_movie_count DESC;

-- EASY 04. Number of historical movie releases by year.
-- Concepts: WHERE, GROUP BY, COUNT.
SELECT
    release_year,
    COUNT(*) AS movie_count
FROM movies
WHERE
    release_year BETWEEN 1900 AND EXTRACT(YEAR FROM CURRENT_DATE)
GROUP BY release_year
ORDER BY release_year;

-- EASY 05. Longest films after excluding extreme values above 10 hours.
-- Concepts: NULL handling, WHERE, ORDER BY, LIMIT.
SELECT
    movie_id,
    title,
    release_year,
    runtime_minutes
FROM movies
WHERE runtime_minutes BETWEEN 1 AND 600
ORDER BY
    runtime_minutes DESC,
    title
LIMIT 20;
