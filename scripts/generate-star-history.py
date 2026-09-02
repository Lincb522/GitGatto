#!/usr/bin/env python3
"""Generate the README Star History chart from GitHub stargazer timestamps."""

from __future__ import annotations

import argparse
import html
import json
import subprocess
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path


def gh_json(arguments: list[str]) -> object:
    result = subprocess.run(
        ["gh", "api", *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def load_repository(repository: str) -> tuple[date, list[date]]:
    metadata = gh_json([f"repos/{repository}"])
    if not isinstance(metadata, dict) or not isinstance(metadata.get("created_at"), str):
        raise SystemExit("GitHub repository metadata did not include created_at")

    pages = gh_json([
        "-H",
        "Accept: application/vnd.github.star+json",
        f"repos/{repository}/stargazers",
        "--paginate",
        "--slurp",
    ])
    if not isinstance(pages, list):
        raise SystemExit("GitHub stargazer response was not a page list")

    starred: list[date] = []
    for page in pages:
        if not isinstance(page, list):
            continue
        for item in page:
            timestamp = item.get("starred_at") if isinstance(item, dict) else None
            if isinstance(timestamp, str):
                starred.append(datetime.fromisoformat(timestamp.replace("Z", "+00:00")).date())

    created = datetime.fromisoformat(metadata["created_at"].replace("Z", "+00:00")).date()
    return created, sorted(starred)


def date_range(start: date, end: date) -> list[date]:
    return [start + timedelta(days=offset) for offset in range((end - start).days + 1)]


def render(repository: str, created: date, starred: list[date]) -> str:
    end = max(datetime.now(timezone.utc).date(), starred[-1] if starred else created)
    days = date_range(created, end)
    daily = Counter(starred)
    cumulative: list[int] = []
    total = 0
    for day in days:
        total += daily[day]
        cumulative.append(total)

    width, height = 1280, 560
    left, right, top, bottom = 92, 76, 112, 88
    chart_width = width - left - right
    chart_height = height - top - bottom
    maximum = max(1, max(cumulative, default=0))
    y_max = max(5, ((maximum + 4) // 5) * 5)
    x_step = chart_width / max(1, len(days) - 1)

    def x(index: int) -> float:
        return left + index * x_step

    def y(value: int) -> float:
        return top + chart_height - (value / y_max) * chart_height

    line_points = " ".join(f"{x(index):.1f},{y(value):.1f}" for index, value in enumerate(cumulative))
    area_points = (
        f"{x(0):.1f},{top + chart_height:.1f} "
        f"{line_points} "
        f"{x(len(days) - 1):.1f},{top + chart_height:.1f}"
    )
    title = html.escape(f"{repository} Star History")

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
        f'<title id="title">{title}</title>',
        f'<desc id="desc">{len(starred)} GitHub stars from {created.isoformat()} through {end.isoformat()}.</desc>',
        """<style>
            :root { color-scheme: light dark; }
            .background { fill: #ffffff; }
            .grid { stroke: #e4e8eb; stroke-width: 1; }
            .axis { fill: #68727d; font: 500 14px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .title { fill: #161c22; font: 700 28px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .subtitle { fill: #68727d; font: 500 14px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .area { fill: #e85d24; opacity: .10; }
            .curve { fill: none; stroke: #e85d24; stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
            .point { fill: #ffffff; stroke: #e85d24; stroke-width: 4; }
            .total { fill: #161c22; font: 700 22px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            @media (prefers-color-scheme: dark) {
                .background { fill: #101419; }
                .grid { stroke: #2b333b; }
                .axis, .subtitle { fill: #9ba7b3; }
                .title, .total { fill: #f4f6f8; }
                .area { opacity: .18; }
                .point { fill: #101419; }
            }
        </style>""",
        '<rect class="background" width="1280" height="560" rx="24"/>',
        f'<text class="title" x="64" y="54">{title}</text>',
        f'<text class="subtitle" x="64" y="81">GitHub stargazers · {created.isoformat()} — {end.isoformat()}</text>',
        f'<text class="total" x="1216" y="58" text-anchor="end">★ {len(starred)}</text>',
    ]

    step = 5 if y_max >= 10 else 1
    for value in range(0, y_max + 1, step):
        py = y(value)
        parts.append(f'<line class="grid" x1="{left}" y1="{py:.1f}" x2="{width - right}" y2="{py:.1f}"/>')
        parts.append(f'<text class="axis" x="{left - 18}" y="{py + 5:.1f}" text-anchor="end">{value}</text>')

    parts.append(f'<polygon class="area" points="{area_points}"/>')
    parts.append(f'<polyline class="curve" points="{line_points}"/>')

    changed_indices = [index for index, day in enumerate(days) if daily[day] > 0]
    if changed_indices:
        for index in changed_indices:
            value = cumulative[index]
            parts.append(f'<circle class="point" cx="{x(index):.1f}" cy="{y(value):.1f}" r="7"><title>{days[index].isoformat()}: {value} stars</title></circle>')

    label_indices = sorted({0, len(days) - 1, len(days) // 2})
    for index in label_indices:
        parts.append(f'<text class="axis" x="{x(index):.1f}" y="{top + chart_height + 32:.1f}" text-anchor="middle">{days[index].strftime("%m-%d")}</text>')

    parts.extend([
        f'<text class="axis" x="{left}" y="{height - 28}" text-anchor="start">Source: GitHub Stargazers API</text>',
        f'<text class="axis" x="{width - right}" y="{height - 28}" text-anchor="end">Updated {end.isoformat()} UTC</text>',
        '</svg>',
    ])
    return "\n".join(parts) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", default="Lincb522/GitGatto")
    parser.add_argument("--output", type=Path, default=Path("docs/media/star-history.svg"))
    args = parser.parse_args()

    created, starred = load_repository(args.repository)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(args.repository, created, starred), encoding="utf-8")
    print(f"Wrote {args.output} with {len(starred)} stars")


if __name__ == "__main__":
    main()
