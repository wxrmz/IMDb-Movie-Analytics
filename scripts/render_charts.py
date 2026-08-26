"""Render static portfolio PNGs from SQL-exported CSV files.

All metrics are calculated in PostgreSQL by sql/13_export_results.sql. This
script only formats the reviewed result tables into portable images.
"""

from __future__ import annotations

import csv
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs/results"
IMAGES = ROOT / "images"
WIDTH = 1600
HEIGHT = 900

INK = "#172033"
MUTED = "#667085"
GRID = "#D9DEE8"
BLUE = "#3769C8"
BLUE_LIGHT = "#DCE7FA"
GOLD = "#C49324"
ORANGE = "#D76B32"
WHITE = "#FFFFFF"
PANEL = "#F7F9FC"


def font(size: int, bold: bool = False):
    candidates = [
        Path("C:/Windows/Fonts/seguisb.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


TITLE = font(42, bold=True)
SUBTITLE = font(24)
LABEL = font(22)
SMALL = font(18)
VALUE = font(20, bold=True)
BOX_TITLE = font(22, bold=True)
BOX_TEXT = font(17)


def canvas(title: str, subtitle: str):
    image = Image.new("RGB", (WIDTH, HEIGHT), WHITE)
    draw = ImageDraw.Draw(image)
    draw.text((80, 52), title, fill=INK, font=TITLE)
    draw.text((80, 112), subtitle, fill=MUTED, font=SUBTITLE)
    draw.line((80, 158, WIDTH - 80, 158), fill=GRID, width=2)
    return image, draw


def footer(draw: ImageDraw.ImageDraw, note: str):
    draw.line((80, HEIGHT - 72, WIDTH - 80, HEIGHT - 72), fill=GRID, width=1)
    draw.text((80, HEIGHT - 52), note, fill=MUTED, font=SMALL)


def read_csv(name: str) -> list[dict[str, str]]:
    with (RESULTS / name).open("r", encoding="utf-8", newline="") as source:
        return list(csv.DictReader(source))


def horizontal_bars(
    rows: list[dict[str, str]],
    label_key: str,
    value_key: str,
    title: str,
    subtitle: str,
    output: str,
    value_format=lambda value: f"{value:,.0f}",
):
    image, draw = canvas(title, subtitle)
    left = 360
    right = WIDTH - 120
    top = 195
    bottom = HEIGHT - 105
    values = [float(row[value_key]) for row in rows]
    max_value = max(values) if values else 1
    row_height = (bottom - top) / max(len(rows), 1)

    for index, (row, value) in enumerate(zip(rows, values)):
        y = top + index * row_height
        bar_height = max(16, row_height * 0.58)
        label = row[label_key]
        if len(label) > 29:
            label = label[:27] + "…"
        draw.text((left - 18, y + bar_height / 2), label, fill=INK, font=LABEL, anchor="rm")
        draw.rectangle(
            (left, y, left + (right - left) * value / max_value, y + bar_height),
            fill=BLUE,
        )
        draw.text(
            (left + (right - left) * value / max_value + 10, y + bar_height / 2),
            value_format(value),
            fill=INK,
            font=VALUE,
            anchor="lm",
        )

    footer(draw, "Source: IMDb snapshot 2026-08-22; calculations: PostgreSQL")
    image.save(IMAGES / output, optimize=True)


def rating_histogram():
    rows = read_csv("rating_distribution.csv")
    image, draw = canvas(
        "IMDb rating distribution",
        "Rated movie population; half-point bins on the 0–10 scale",
    )
    left, right = 120, WIDTH - 90
    top, bottom = 205, HEIGHT - 125
    values = [int(row["movie_count"]) for row in rows]
    labels = [float(row["rating_band_start"]) for row in rows]
    max_value = max(values)

    for tick in range(0, 6):
        value = max_value * tick / 5
        y = bottom - (bottom - top) * tick / 5
        draw.line((left, y, right, y), fill=GRID, width=1)
        draw.text((left - 14, y), f"{value:,.0f}", fill=MUTED, font=SMALL, anchor="rm")

    slot = (right - left) / len(rows)
    for index, (label, value) in enumerate(zip(labels, values)):
        x1 = left + index * slot + 3
        x2 = left + (index + 1) * slot - 3
        y = bottom - (bottom - top) * value / max_value
        draw.rectangle((x1, y, x2, bottom), fill=BLUE, outline=INK, width=1)
        if index % 2 == 0:
            draw.text(((x1 + x2) / 2, bottom + 14), f"{label:g}", fill=MUTED, font=SMALL, anchor="ma")

    draw.line((left, bottom, right, bottom), fill=INK, width=2)
    draw.text(((left + right) / 2, bottom + 50), "Rating band start", fill=INK, font=LABEL, anchor="ma")
    footer(draw, "Source: IMDb snapshot 2026-08-22; n = all movies with a rating record")
    image.save(IMAGES / "rating_distribution.png", optimize=True)


def release_trend():
    rows = read_csv("movie_release_trend.csv")
    years = [int(row["release_year"]) for row in rows]
    raw = [float(row["movie_count"]) for row in rows]
    moving = [float(row["moving_avg_3_years"]) for row in rows]
    image, draw = canvas(
        "Movie releases by year",
        "IMDb catalog count and three-year moving average, 1950–2025",
    )
    left, right = 120, WIDTH - 90
    top, bottom = 205, HEIGHT - 125
    max_value = max(raw)

    for tick in range(0, 6):
        value = max_value * tick / 5
        y = bottom - (bottom - top) * tick / 5
        draw.line((left, y, right, y), fill=GRID, width=1)
        draw.text((left - 14, y), f"{value:,.0f}", fill=MUTED, font=SMALL, anchor="rm")

    def points(values):
        return [
            (
                left + (right - left) * (year - years[0]) / (years[-1] - years[0]),
                bottom - (bottom - top) * value / max_value,
            )
            for year, value in zip(years, values)
        ]

    draw.line(points(raw), fill=BLUE_LIGHT, width=4)
    draw.line(points(moving), fill=BLUE, width=6)
    for year in range(1950, 2026, 10):
        x = left + (right - left) * (year - years[0]) / (years[-1] - years[0])
        draw.text((x, bottom + 18), str(year), fill=MUTED, font=SMALL, anchor="ma")

    draw.line((left, bottom, right, bottom), fill=INK, width=2)
    draw.line((1120, 180, 1170, 180), fill=BLUE_LIGHT, width=5)
    draw.text((1182, 180), "Annual count", fill=MUTED, font=SMALL, anchor="lm")
    draw.line((1320, 180, 1370, 180), fill=BLUE, width=6)
    draw.text((1382, 180), "3-year average", fill=INK, font=SMALL, anchor="lm")
    footer(draw, "Source: IMDb snapshot 2026-08-22; future announced titles excluded")
    image.save(IMAGES / "movie_release_trend.png", optimize=True)


def er_diagram():
    image, draw = canvas(
        "IMDb movie analytics — relational model",
        "Clean PostgreSQL schema; staging tables omitted for readability",
    )
    boxes = {
        "movies": (610, 300, 990, 540, ["PK movie_id", "title", "release_year", "runtime_minutes"]),
        "ratings": (1050, 190, 1460, 370, ["PK/FK movie_id", "average_rating", "vote_count"]),
        "genres": (90, 190, 440, 335, ["PK genre_id", "UK genre_name"]),
        "movie_genres": (90, 420, 440, 585, ["PK/FK movie_id", "PK/FK genre_id"]),
        "directors": (1080, 440, 1480, 615, ["PK/FK movie_id", "PK/FK person_id", "director_order"]),
        "principals": (570, 590, 1015, 820, ["PK/FK movie_id", "PK credit_order", "FK person_id", "FK category_code"]),
        "persons": (90, 640, 440, 800, ["PK person_id", "person_name", "name_missing"]),
    }

    connectors = [
        ("movies", "ratings"),
        ("movies", "movie_genres"),
        ("genres", "movie_genres"),
        ("movies", "directors"),
        ("persons", "directors"),
        ("movies", "principals"),
        ("persons", "principals"),
    ]

    centers = {}
    for name, (x1, y1, x2, y2, _) in boxes.items():
        centers[name] = ((x1 + x2) / 2, (y1 + y2) / 2)
    for source, target in connectors:
        draw.line((*centers[source], *centers[target]), fill=GOLD, width=5)

    display = {
        "movies": "movies",
        "ratings": "movie_ratings",
        "genres": "genres",
        "movie_genres": "movie_genres",
        "directors": "movie_directors",
        "principals": "movie_principals",
        "persons": "persons",
    }
    for name, (x1, y1, x2, y2, fields) in boxes.items():
        draw.rounded_rectangle((x1, y1, x2, y2), radius=18, fill=PANEL, outline=INK, width=3)
        draw.rectangle((x1, y1, x2, y1 + 50), fill=BLUE)
        draw.text(((x1 + x2) / 2, y1 + 25), display[name], fill=WHITE, font=BOX_TITLE, anchor="mm")
        for index, field in enumerate(fields):
            draw.text((x1 + 24, y1 + 72 + index * 31), field, fill=INK, font=BOX_TEXT)

    footer(draw, "PK = primary key; FK = foreign key; normalized PostgreSQL schema")
    image.save(IMAGES / "er_diagram.png", optimize=True)


def main():
    IMAGES.mkdir(parents=True, exist_ok=True)
    required = [
        "rating_distribution.csv",
        "top_genres.csv",
        "director_ranking.csv",
        "movie_release_trend.csv",
    ]
    missing = [name for name in required if not (RESULTS / name).is_file()]
    if missing:
        raise FileNotFoundError(
            f"Missing SQL exports: {missing}. Run sql/13_export_results.sql first."
        )

    rating_histogram()
    horizontal_bars(
        read_csv("top_genres.csv"),
        "genre_name",
        "movie_count",
        "Top genres by catalogued movie count",
        "Top 15 IMDb genres; multi-genre films contribute to each listed genre",
        "top_genres.png",
    )
    horizontal_bars(
        read_csv("director_ranking.csv"),
        "person_name",
        "director_score",
        "Director ranking",
        "Bayesian-style score; ≥5 films and ≥1,000 votes per eligible film",
        "director_ranking.png",
        value_format=lambda value: f"{value:.3f}",
    )
    release_trend()
    er_diagram()


if __name__ == "__main__":
    main()
