"""Create a compact IMDb movie-only snapshot for PostgreSQL loading.

The official files contain films, series, episodes, shorts, games, and other
title types. This script streams the compressed snapshot and retains only
non-adult `movie` titles plus their related ratings, crew, principals, and
people. It does not alter source values or perform analytical calculations.
"""

from __future__ import annotations

import csv
import gzip
import json
import sys
from datetime import date
from pathlib import Path


FILES = {
    "title.basics.tsv.gz": "title.basics.movies.tsv.gz",
    "title.ratings.tsv.gz": "title.ratings.movies.tsv.gz",
    "title.crew.tsv.gz": "title.crew.movies.tsv.gz",
    "title.principals.tsv.gz": "title.principals.movies.tsv.gz",
    "name.basics.tsv.gz": "name.basics.movies.tsv.gz",
}


def filtered_copy(
    source_path: Path,
    destination_path: Path,
    keep,
    collect=None,
) -> tuple[int, int, list[str]]:
    read_count = 0
    write_count = 0
    with gzip.open(source_path, "rt", encoding="utf-8", newline="") as source:
        reader = csv.reader(source, delimiter="\t", quoting=csv.QUOTE_NONE)
        header = next(reader)
        with gzip.open(
            destination_path,
            "wt",
            encoding="utf-8",
            newline="",
            compresslevel=1,
        ) as destination:
            destination.write("\t".join(header) + "\n")
            for values in reader:
                read_count += 1
                if read_count % 5_000_000 == 0:
                    print(
                        f"{source_path.name}: read {read_count:,}, "
                        f"kept {write_count:,}",
                        file=sys.stderr,
                    )
                row = dict(zip(header, values, strict=True))
                if not keep(row):
                    continue
                destination.write("\t".join(values) + "\n")
                write_count += 1
                if collect is not None:
                    collect(row)
    return read_count, write_count, header


def split_ids(value: str) -> list[str]:
    if value in ("", r"\N"):
        return []
    return [item for item in value.split(",") if item]


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    source_dir = Path(
        sys.argv[1] if len(sys.argv) > 1 else project_root / "data/raw/imdb"
    ).resolve()
    destination_dir = Path(
        sys.argv[2]
        if len(sys.argv) > 2
        else project_root / "data/processed/imdb"
    ).resolve()
    destination_dir.mkdir(parents=True, exist_ok=True)

    missing = [name for name in FILES if not (source_dir / name).is_file()]
    if missing:
        raise FileNotFoundError(f"Missing IMDb source files: {missing}")

    manifest: dict[str, object] = {
        "prepared_on": date.today().isoformat(),
        "filter": "titleType = movie AND isAdult = 0",
        "source_directory": str(source_dir),
        "destination_directory": str(destination_dir),
        "files": {},
    }

    movie_ids: set[str] = set()

    def collect_movie(row: dict[str, str]) -> None:
        movie_ids.add(row["tconst"])

    source_name = "title.basics.tsv.gz"
    destination_name = FILES[source_name]
    result = filtered_copy(
        source_dir / source_name,
        destination_dir / destination_name,
        lambda row: row["titleType"] == "movie" and row["isAdult"] == "0",
        collect_movie,
    )
    manifest["files"][destination_name] = {
        "source_rows": result[0],
        "processed_rows": result[1],
        "columns": result[2],
    }
    print(f"Selected movies: {len(movie_ids):,}", file=sys.stderr)

    for source_name in ("title.ratings.tsv.gz",):
        destination_name = FILES[source_name]
        result = filtered_copy(
            source_dir / source_name,
            destination_dir / destination_name,
            lambda row: row["tconst"] in movie_ids,
        )
        manifest["files"][destination_name] = {
            "source_rows": result[0],
            "processed_rows": result[1],
            "columns": result[2],
        }

    required_people: set[str] = set()

    def collect_crew(row: dict[str, str]) -> None:
        required_people.update(split_ids(row["directors"]))

    source_name = "title.crew.tsv.gz"
    destination_name = FILES[source_name]
    result = filtered_copy(
        source_dir / source_name,
        destination_dir / destination_name,
        lambda row: row["tconst"] in movie_ids,
        collect_crew,
    )
    manifest["files"][destination_name] = {
        "source_rows": result[0],
        "processed_rows": result[1],
        "columns": result[2],
    }

    def collect_principal(row: dict[str, str]) -> None:
        required_people.add(row["nconst"])

    source_name = "title.principals.tsv.gz"
    destination_name = FILES[source_name]
    result = filtered_copy(
        source_dir / source_name,
        destination_dir / destination_name,
        lambda row: row["tconst"] in movie_ids,
        collect_principal,
    )
    manifest["files"][destination_name] = {
        "source_rows": result[0],
        "processed_rows": result[1],
        "columns": result[2],
    }

    source_name = "name.basics.tsv.gz"
    destination_name = FILES[source_name]
    result = filtered_copy(
        source_dir / source_name,
        destination_dir / destination_name,
        lambda row: row["nconst"] in required_people,
    )
    manifest["files"][destination_name] = {
        "source_rows": result[0],
        "processed_rows": result[1],
        "columns": result[2],
    }
    manifest["distinct_required_people"] = len(required_people)

    manifest_path = destination_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote manifest: {manifest_path}", file=sys.stderr)


if __name__ == "__main__":
    csv.field_size_limit(sys.maxsize)
    main()
