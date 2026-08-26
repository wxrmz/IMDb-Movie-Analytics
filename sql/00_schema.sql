\set ON_ERROR_STOP on

-- Recreates the project schemas. Run only against the project database.
BEGIN;

DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS movie_analytics CASCADE;

CREATE SCHEMA staging;
CREATE SCHEMA movie_analytics;

COMMENT ON SCHEMA staging IS
    'Raw IMDb movie-only snapshot. All source columns are loaded as text.';
COMMENT ON SCHEMA movie_analytics IS
    'Typed and normalized tables used by the portfolio analyses.';

-- UNLOGGED staging tables speed up reproducible local imports. They can be
-- rebuilt from the immutable processed snapshot at any time.
CREATE UNLOGGED TABLE staging.title_basics (
    tconst TEXT,
    title_type TEXT,
    primary_title TEXT,
    original_title TEXT,
    is_adult TEXT,
    start_year TEXT,
    end_year TEXT,
    runtime_minutes TEXT,
    genres TEXT
);

CREATE UNLOGGED TABLE staging.title_ratings (
    tconst TEXT,
    average_rating TEXT,
    num_votes TEXT
);

CREATE UNLOGGED TABLE staging.title_crew (
    tconst TEXT,
    directors TEXT,
    writers TEXT
);

CREATE UNLOGGED TABLE staging.title_principals (
    tconst TEXT,
    ordering TEXT,
    nconst TEXT,
    category TEXT,
    job TEXT,
    characters TEXT
);

CREATE UNLOGGED TABLE staging.name_basics (
    nconst TEXT,
    primary_name TEXT,
    birth_year TEXT,
    death_year TEXT,
    primary_profession TEXT,
    known_for_titles TEXT
);

CREATE TABLE movie_analytics.movies (
    movie_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    original_title TEXT,
    release_year SMALLINT,
    runtime_minutes INTEGER,
    CONSTRAINT movies_id_format_chk
        CHECK (movie_id ~ '^tt[0-9]+$'),
    CONSTRAINT movies_release_year_chk
        CHECK (release_year BETWEEN 1870 AND 2100),
    CONSTRAINT movies_runtime_chk
        CHECK (runtime_minutes > 0)
);

COMMENT ON TABLE movie_analytics.movies IS
    'One non-adult IMDb title whose source titleType is movie.';

CREATE TABLE movie_analytics.movie_ratings (
    movie_id TEXT PRIMARY KEY,
    average_rating NUMERIC(3, 1) NOT NULL,
    vote_count BIGINT NOT NULL,
    CONSTRAINT movie_ratings_movie_fk
        FOREIGN KEY (movie_id)
        REFERENCES movie_analytics.movies (movie_id)
        ON DELETE CASCADE,
    CONSTRAINT movie_ratings_rating_chk
        CHECK (average_rating BETWEEN 0 AND 10),
    CONSTRAINT movie_ratings_votes_chk
        CHECK (vote_count >= 0)
);

COMMENT ON TABLE movie_analytics.movie_ratings IS
    'Optional current IMDb aggregate rating for a movie.';

CREATE TABLE movie_analytics.genres (
    genre_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    genre_name TEXT NOT NULL UNIQUE,
    CONSTRAINT genres_name_not_blank_chk
        CHECK (BTRIM(genre_name) <> '')
);

CREATE TABLE movie_analytics.movie_genres (
    movie_id TEXT NOT NULL,
    genre_id SMALLINT NOT NULL,
    PRIMARY KEY (movie_id, genre_id),
    CONSTRAINT movie_genres_movie_fk
        FOREIGN KEY (movie_id)
        REFERENCES movie_analytics.movies (movie_id)
        ON DELETE CASCADE,
    CONSTRAINT movie_genres_genre_fk
        FOREIGN KEY (genre_id)
        REFERENCES movie_analytics.genres (genre_id)
        ON DELETE RESTRICT
);

CREATE TABLE movie_analytics.persons (
    person_id TEXT PRIMARY KEY,
    person_name TEXT,
    birth_year SMALLINT,
    death_year SMALLINT,
    name_missing BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT persons_id_format_chk
        CHECK (person_id ~ '^nm[0-9]+$'),
    CONSTRAINT persons_birth_year_chk
        CHECK (birth_year BETWEEN 1800 AND 2100),
    CONSTRAINT persons_death_year_chk
        CHECK (death_year BETWEEN 1800 AND 2100),
    CONSTRAINT persons_lifespan_chk
        CHECK (
            birth_year IS NULL
            OR death_year IS NULL
            OR death_year >= birth_year
        ),
    CONSTRAINT persons_missing_name_consistency_chk
        CHECK (name_missing = (person_name IS NULL))
);

COMMENT ON COLUMN movie_analytics.persons.name_missing IS
    'TRUE when a referenced nconst has no usable name.basics record.';

CREATE TABLE movie_analytics.principal_categories (
    category_code TEXT PRIMARY KEY,
    CONSTRAINT principal_categories_not_blank_chk
        CHECK (BTRIM(category_code) <> '')
);

CREATE TABLE movie_analytics.movie_directors (
    movie_id TEXT NOT NULL,
    person_id TEXT NOT NULL,
    director_order SMALLINT NOT NULL,
    PRIMARY KEY (movie_id, person_id),
    UNIQUE (movie_id, director_order),
    CONSTRAINT movie_directors_movie_fk
        FOREIGN KEY (movie_id)
        REFERENCES movie_analytics.movies (movie_id)
        ON DELETE CASCADE,
    CONSTRAINT movie_directors_person_fk
        FOREIGN KEY (person_id)
        REFERENCES movie_analytics.persons (person_id)
        ON DELETE RESTRICT,
    CONSTRAINT movie_directors_order_chk
        CHECK (director_order > 0)
);

CREATE TABLE movie_analytics.movie_principals (
    movie_id TEXT NOT NULL,
    credit_order SMALLINT NOT NULL,
    person_id TEXT NOT NULL,
    category_code TEXT NOT NULL,
    job TEXT,
    characters JSONB,
    PRIMARY KEY (movie_id, credit_order),
    CONSTRAINT movie_principals_movie_fk
        FOREIGN KEY (movie_id)
        REFERENCES movie_analytics.movies (movie_id)
        ON DELETE CASCADE,
    CONSTRAINT movie_principals_person_fk
        FOREIGN KEY (person_id)
        REFERENCES movie_analytics.persons (person_id)
        ON DELETE RESTRICT,
    CONSTRAINT movie_principals_category_fk
        FOREIGN KEY (category_code)
        REFERENCES movie_analytics.principal_categories (category_code)
        ON DELETE RESTRICT,
    CONSTRAINT movie_principals_order_chk
        CHECK (credit_order > 0),
    CONSTRAINT movie_principals_characters_array_chk
        CHECK (characters IS NULL OR JSONB_TYPEOF(characters) = 'array')
);

CREATE TABLE movie_analytics.dataset_loads (
    load_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_name TEXT NOT NULL,
    snapshot_date DATE NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    movie_filter TEXT NOT NULL,
    row_counts JSONB NOT NULL,
    CONSTRAINT dataset_loads_source_chk
        CHECK (BTRIM(source_name) <> ''),
    CONSTRAINT dataset_loads_counts_object_chk
        CHECK (JSONB_TYPEOF(row_counts) = 'object')
);

COMMIT;
