"""Stream a compact quality profile for the raw IMDb non-commercial datasets.

The script intentionally avoids pandas and loads only identifiers needed for
cross-file integrity checks. It is preparation/QA code; project analytics stay
in PostgreSQL.
"""

from __future__ import annotations

import csv
import gzip
import json
import re
import sys
from collections import Counter
from datetime import date
from pathlib import Path


NULL = r"\N"
TITLE_ID = re.compile(r"^tt\d+$")
PERSON_ID = re.compile(r"^nm\d+$")


def rows(path: Path):
    with gzip.open(path, "rt", encoding="utf-8", newline="") as source:
        reader = csv.reader(source, delimiter="\t", quoting=csv.QUOTE_NONE)
        header = next(reader)
        for row_number, values in enumerate(reader, start=1):
            if row_number % 5_000_000 == 0:
                print(f"{path.name}: {row_number:,} rows", file=sys.stderr)
            row = dict(zip(header, values, strict=True))
            yield header, row


def as_int(value: str):
    if value in ("", NULL):
        return None
    try:
        return int(value)
    except ValueError:
        return None


def as_float(value: str):
    if value in ("", NULL):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def split_ids(value: str) -> list[str]:
    if value in ("", NULL):
        return []
    return [item for item in value.split(",") if item]


def main() -> None:
    root = Path(
        sys.argv[1] if len(sys.argv) > 1 else "data/raw/imdb"
    ).resolve()
    paths = {
        "basics": root / "title.basics.tsv.gz",
        "ratings": root / "title.ratings.tsv.gz",
        "crew": root / "title.crew.tsv.gz",
        "principals": root / "title.principals.tsv.gz",
        "names": root / "name.basics.tsv.gz",
    }

    missing_files = [str(path) for path in paths.values() if not path.is_file()]
    if missing_files:
        raise FileNotFoundError(f"Missing required files: {missing_files}")

    profile: dict[str, object] = {
        "profile_date": date.today().isoformat(),
        "source_directory": str(root),
        "files": {
            key: {"name": path.name, "compressed_bytes": path.stat().st_size}
            for key, path in paths.items()
        },
    }

    movie_ids: set[str] = set()
    movie_genres = Counter()
    title_types = Counter()
    basics = Counter()
    basics_header: list[str] = []
    min_year = None
    max_year = None

    for header, row in rows(paths["basics"]):
        basics_header = header
        basics["all_rows"] += 1
        title_types[row["titleType"]] += 1
        if row["titleType"] != "movie" or row["isAdult"] != "0":
            continue

        basics["project_movie_rows"] += 1
        movie_id = row["tconst"]
        if not TITLE_ID.fullmatch(movie_id):
            basics["malformed_tconst"] += 1
        if movie_id in movie_ids:
            basics["duplicate_tconst"] += 1
        movie_ids.add(movie_id)

        year = as_int(row["startYear"])
        if year is None:
            basics["missing_or_invalid_start_year"] += 1
        else:
            min_year = year if min_year is None else min(min_year, year)
            max_year = year if max_year is None else max(max_year, year)
            if year < 1870 or year > date.today().year:
                basics["outside_historical_year_range"] += 1

        runtime = as_int(row["runtimeMinutes"])
        if runtime is None:
            basics["missing_or_invalid_runtime"] += 1
        elif runtime <= 0:
            basics["nonpositive_runtime"] += 1
        elif runtime > 600:
            basics["runtime_over_600_minutes"] += 1

        genres = split_ids(row["genres"])
        if not genres:
            basics["missing_genres"] += 1
        movie_genres.update(genres)

    profile["basics"] = {
        **basics,
        "header": basics_header,
        "distinct_project_movie_ids": len(movie_ids),
        "min_start_year": min_year,
        "max_start_year": max_year,
        "title_types": dict(title_types.most_common()),
        "genres": dict(movie_genres.most_common()),
    }
    print(f"Project movies selected: {len(movie_ids):,}", file=sys.stderr)

    rating_movie_ids: set[str] = set()
    ratings = Counter()
    ratings_header: list[str] = []
    min_rating = None
    max_rating = None
    max_votes = None

    for header, row in rows(paths["ratings"]):
        ratings_header = header
        ratings["all_rows"] += 1
        movie_id = row["tconst"]
        if movie_id not in movie_ids:
            continue
        ratings["project_movie_rows"] += 1
        if movie_id in rating_movie_ids:
            ratings["duplicate_tconst"] += 1
        rating_movie_ids.add(movie_id)

        rating = as_float(row["averageRating"])
        votes = as_int(row["numVotes"])
        if rating is None:
            ratings["missing_or_invalid_rating"] += 1
        else:
            min_rating = rating if min_rating is None else min(min_rating, rating)
            max_rating = rating if max_rating is None else max(max_rating, rating)
            if not 0 <= rating <= 10:
                ratings["rating_outside_0_10"] += 1
        if votes is None:
            ratings["missing_or_invalid_votes"] += 1
        else:
            max_votes = votes if max_votes is None else max(max_votes, votes)
            if votes < 0:
                ratings["negative_votes"] += 1
            if votes < 10:
                ratings["votes_under_10"] += 1
            if votes >= 1_000:
                ratings["votes_at_least_1000"] += 1

    profile["ratings"] = {
        **ratings,
        "header": ratings_header,
        "distinct_rated_project_movies": len(rating_movie_ids),
        "project_movie_coverage_pct": round(
            100 * len(rating_movie_ids) / len(movie_ids), 2
        ),
        "min_rating": min_rating,
        "max_rating": max_rating,
        "max_votes": max_votes,
    }

    crew_movie_ids: set[str] = set()
    director_ids: set[str] = set()
    crew = Counter()
    crew_header: list[str] = []

    for header, row in rows(paths["crew"]):
        crew_header = header
        crew["all_rows"] += 1
        movie_id = row["tconst"]
        if movie_id not in movie_ids:
            continue
        crew["project_movie_rows"] += 1
        if movie_id in crew_movie_ids:
            crew["duplicate_tconst"] += 1
        crew_movie_ids.add(movie_id)

        directors = split_ids(row["directors"])
        writers = split_ids(row["writers"])
        if not directors:
            crew["movies_without_directors"] += 1
        if not writers:
            crew["movies_without_writers"] += 1
        crew["director_relationship_rows"] += len(directors)
        crew["writer_relationship_rows"] += len(writers)
        for person_id in directors:
            if not PERSON_ID.fullmatch(person_id):
                crew["malformed_director_nconst"] += 1
            director_ids.add(person_id)

    profile["crew"] = {
        **crew,
        "header": crew_header,
        "distinct_project_movies": len(crew_movie_ids),
        "project_movie_coverage_pct": round(
            100 * len(crew_movie_ids) / len(movie_ids), 2
        ),
        "distinct_directors": len(director_ids),
    }

    principal_movie_ids: set[str] = set()
    principal_person_ids: set[str] = set()
    principal_categories = Counter()
    principals = Counter()
    principals_header: list[str] = []
    current_movie = None
    current_orderings: set[str] = set()
    current_person_categories: set[tuple[str, str]] = set()

    for header, row in rows(paths["principals"]):
        principals_header = header
        principals["all_rows"] += 1
        movie_id = row["tconst"]
        if movie_id not in movie_ids:
            continue
        principals["project_movie_rows"] += 1
        principal_movie_ids.add(movie_id)
        person_id = row["nconst"]
        category = row["category"]
        principal_categories[category] += 1
        principal_person_ids.add(person_id)
        if not PERSON_ID.fullmatch(person_id):
            principals["malformed_nconst"] += 1

        if movie_id != current_movie:
            current_movie = movie_id
            current_orderings.clear()
            current_person_categories.clear()
        ordering = row["ordering"]
        if ordering in current_orderings:
            principals["duplicate_movie_ordering_adjacent"] += 1
        current_orderings.add(ordering)
        person_category = (person_id, category)
        if person_category in current_person_categories:
            principals["duplicate_movie_person_category_adjacent"] += 1
        current_person_categories.add(person_category)

    profile["principals"] = {
        **principals,
        "header": principals_header,
        "distinct_project_movies": len(principal_movie_ids),
        "project_movie_coverage_pct": round(
            100 * len(principal_movie_ids) / len(movie_ids), 2
        ),
        "distinct_principal_people": len(principal_person_ids),
        "categories": dict(principal_categories.most_common()),
    }

    principal_person_ids.update(director_ids)
    required_people = len(principal_person_ids)
    names = Counter()
    names_header: list[str] = []
    matched_person_ids: set[str] = set()

    for header, row in rows(paths["names"]):
        names_header = header
        names["all_rows"] += 1
        person_id = row["nconst"]
        if person_id not in principal_person_ids:
            continue
        names["required_person_rows"] += 1
        if person_id in matched_person_ids:
            names["duplicate_required_nconst"] += 1
        matched_person_ids.add(person_id)
        if row["primaryName"] in ("", NULL):
            names["missing_primary_name"] += 1

    profile["names"] = {
        **names,
        "header": names_header,
        "distinct_required_people": required_people,
        "distinct_matched_people": len(matched_person_ids),
        "unmatched_required_people": required_people - len(matched_person_ids),
        "required_people_coverage_pct": round(
            100 * len(matched_person_ids) / required_people, 2
        ),
    }

    json.dump(profile, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    csv.field_size_limit(sys.maxsize)
    main()
