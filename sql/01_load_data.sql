\set ON_ERROR_STOP on
\timing on

SET search_path TO movie_analytics, public;

-- These paths are available inside the PostgreSQL Docker container. The
-- prepare_imdb_subset.py script creates the five compressed files first.
\copy staging.title_basics FROM PROGRAM 'gzip -dc /data/processed/imdb/title.basics.movies.tsv.gz' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', NULL '\N', QUOTE E'\b')
\copy staging.title_ratings FROM PROGRAM 'gzip -dc /data/processed/imdb/title.ratings.movies.tsv.gz' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', NULL '\N', QUOTE E'\b')
\copy staging.title_crew FROM PROGRAM 'gzip -dc /data/processed/imdb/title.crew.movies.tsv.gz' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', NULL '\N', QUOTE E'\b')
\copy staging.title_principals FROM PROGRAM 'gzip -dc /data/processed/imdb/title.principals.movies.tsv.gz' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', NULL '\N', QUOTE E'\b')
\copy staging.name_basics FROM PROGRAM 'gzip -dc /data/processed/imdb/name.basics.movies.tsv.gz' WITH (FORMAT csv, HEADER true, DELIMITER E'\t', NULL '\N', QUOTE E'\b')

BEGIN;

INSERT INTO movies (
    movie_id,
    title,
    original_title,
    release_year,
    runtime_minutes
)
SELECT
    tconst,
    primary_title,
    NULLIF(original_title, ''),
    CASE
        WHEN start_year ~ '^[0-9]{4}$'
            AND start_year::INTEGER BETWEEN 1870 AND 2100
        THEN start_year::SMALLINT
    END,
    CASE
        WHEN runtime_minutes ~ '^[0-9]+$'
            AND runtime_minutes::BIGINT BETWEEN 1 AND 2147483647
        THEN runtime_minutes::INTEGER
    END
FROM staging.title_basics
WHERE
    title_type = 'movie'
    AND is_adult = '0'
    AND tconst ~ '^tt[0-9]+$'
    AND primary_title IS NOT NULL
ON CONFLICT (movie_id) DO NOTHING;

INSERT INTO movie_ratings (
    movie_id,
    average_rating,
    vote_count
)
SELECT
    sr.tconst,
    sr.average_rating::NUMERIC(3, 1),
    sr.num_votes::BIGINT
FROM staging.title_ratings AS sr
JOIN movies AS m
    ON m.movie_id = sr.tconst
WHERE
    sr.average_rating ~ '^[0-9]+([.][0-9]+)?$'
    AND sr.average_rating::NUMERIC BETWEEN 0 AND 10
    AND sr.num_votes ~ '^[0-9]+$'
ON CONFLICT (movie_id) DO UPDATE
SET
    average_rating = EXCLUDED.average_rating,
    vote_count = EXCLUDED.vote_count;

INSERT INTO genres (genre_name)
SELECT DISTINCT
    BTRIM(source_genre.genre_name)
FROM staging.title_basics AS sb
CROSS JOIN LATERAL
    REGEXP_SPLIT_TO_TABLE(sb.genres, ',') AS source_genre (genre_name)
WHERE
    sb.genres IS NOT NULL
    AND BTRIM(source_genre.genre_name) <> ''
ON CONFLICT (genre_name) DO NOTHING;

INSERT INTO movie_genres (movie_id, genre_id)
SELECT DISTINCT
    m.movie_id,
    g.genre_id
FROM staging.title_basics AS sb
JOIN movies AS m
    ON m.movie_id = sb.tconst
CROSS JOIN LATERAL
    REGEXP_SPLIT_TO_TABLE(sb.genres, ',') AS source_genre (genre_name)
JOIN genres AS g
    ON g.genre_name = BTRIM(source_genre.genre_name)
WHERE sb.genres IS NOT NULL
ON CONFLICT (movie_id, genre_id) DO NOTHING;

WITH typed_names AS (
    SELECT
        nconst,
        NULLIF(primary_name, '') AS person_name,
        CASE
            WHEN birth_year ~ '^[0-9]{4}$'
                AND birth_year::INTEGER BETWEEN 1800 AND 2100
            THEN birth_year::SMALLINT
        END AS birth_year,
        CASE
            WHEN death_year ~ '^[0-9]{4}$'
                AND death_year::INTEGER BETWEEN 1800 AND 2100
            THEN death_year::SMALLINT
        END AS death_year
    FROM staging.name_basics
    WHERE nconst ~ '^nm[0-9]+$'
), cleaned_names AS (
    SELECT
        nconst,
        person_name,
        birth_year,
        CASE
            WHEN birth_year IS NOT NULL
                AND death_year IS NOT NULL
                AND death_year < birth_year
            THEN NULL
            ELSE death_year
        END AS death_year
    FROM typed_names
)
INSERT INTO persons (
    person_id,
    person_name,
    birth_year,
    death_year,
    name_missing
)
SELECT
    nconst,
    person_name,
    birth_year,
    death_year,
    person_name IS NULL
FROM cleaned_names
ON CONFLICT (person_id) DO UPDATE
SET
    person_name = EXCLUDED.person_name,
    birth_year = EXCLUDED.birth_year,
    death_year = EXCLUDED.death_year,
    name_missing = EXCLUDED.name_missing;

-- Keep valid credits even when name.basics lacks the referenced nconst.
WITH referenced_people AS (
    SELECT sp.nconst AS person_id
    FROM staging.title_principals AS sp
    WHERE sp.nconst ~ '^nm[0-9]+$'

    UNION

    SELECT BTRIM(source_director.person_id)
    FROM staging.title_crew AS sc
    CROSS JOIN LATERAL
        REGEXP_SPLIT_TO_TABLE(sc.directors, ',') AS source_director (person_id)
    WHERE
        sc.directors IS NOT NULL
        AND BTRIM(source_director.person_id) ~ '^nm[0-9]+$'
)
INSERT INTO persons (person_id, person_name, name_missing)
SELECT
    rp.person_id,
    NULL,
    TRUE
FROM referenced_people AS rp
LEFT JOIN persons AS p
    ON p.person_id = rp.person_id
WHERE p.person_id IS NULL
ON CONFLICT (person_id) DO NOTHING;

INSERT INTO principal_categories (category_code)
SELECT DISTINCT
    category
FROM staging.title_principals
WHERE category IS NOT NULL AND BTRIM(category) <> ''
ON CONFLICT (category_code) DO NOTHING;

INSERT INTO movie_directors (
    movie_id,
    person_id,
    director_order
)
SELECT DISTINCT ON (m.movie_id, source_director.person_id)
    m.movie_id,
    source_director.person_id,
    source_director.director_order::SMALLINT
FROM staging.title_crew AS sc
JOIN movies AS m
    ON m.movie_id = sc.tconst
CROSS JOIN LATERAL
    UNNEST(STRING_TO_ARRAY(sc.directors, ','))
    WITH ORDINALITY AS source_director (person_id, director_order)
JOIN persons AS p
    ON p.person_id = source_director.person_id
WHERE sc.directors IS NOT NULL
ORDER BY
    m.movie_id,
    source_director.person_id,
    source_director.director_order
ON CONFLICT (movie_id, person_id) DO NOTHING;

INSERT INTO movie_principals (
    movie_id,
    credit_order,
    person_id,
    category_code,
    job,
    characters
)
SELECT
    m.movie_id,
    sp.ordering::SMALLINT,
    sp.nconst,
    sp.category,
    NULLIF(sp.job, ''),
    CASE
        WHEN sp.characters IS NULL THEN NULL
        ELSE sp.characters::JSONB
    END
FROM staging.title_principals AS sp
JOIN movies AS m
    ON m.movie_id = sp.tconst
JOIN persons AS p
    ON p.person_id = sp.nconst
JOIN principal_categories AS pc
    ON pc.category_code = sp.category
WHERE
    sp.ordering ~ '^[0-9]+$'
    AND sp.ordering::INTEGER BETWEEN 1 AND 32767
ON CONFLICT (movie_id, credit_order) DO NOTHING;

INSERT INTO dataset_loads (
    source_name,
    snapshot_date,
    movie_filter,
    row_counts
)
SELECT
    'IMDb Non-Commercial Datasets',
    DATE '2026-08-22',
    'titleType = movie AND isAdult = 0',
    JSONB_BUILD_OBJECT(
        'movies', (SELECT COUNT(*) FROM movies),
        'ratings', (SELECT COUNT(*) FROM movie_ratings),
        'genres', (SELECT COUNT(*) FROM genres),
        'movie_genres', (SELECT COUNT(*) FROM movie_genres),
        'persons', (SELECT COUNT(*) FROM persons),
        'movie_directors', (SELECT COUNT(*) FROM movie_directors),
        'movie_principals', (SELECT COUNT(*) FROM movie_principals)
    );

COMMIT;

ANALYZE movie_analytics.movies;
ANALYZE movie_analytics.movie_ratings;
ANALYZE movie_analytics.genres;
ANALYZE movie_analytics.movie_genres;
ANALYZE movie_analytics.persons;
ANALYZE movie_analytics.movie_directors;
ANALYZE movie_analytics.movie_principals;

SELECT row_counts
FROM dataset_loads
ORDER BY load_id DESC
LIMIT 1;
