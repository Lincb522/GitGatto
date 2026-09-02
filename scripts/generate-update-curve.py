#!/usr/bin/env python3
"""Generate the repository update curve from dated CHANGELOG entries."""

from __future__ import annotations

import argparse
import html
import re
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

ENTRY = re.compile(r"^## (\d+\.\d+\.\d+) — (\d{4}-\d{2}-\d{2})$", re.MULTILINE)


def parse_entries(path: Path) -> list[tuple[str, date]]:
    entries = [
        (version, datetime.strptime(day, "%Y-%m-%d").date())
        for version, day in ENTRY.findall(path.read_text(encoding="utf-8"))
    ]
    if not entries:
        raise SystemExit(f"No dated release entries found in {path}")
    return sorted(entries, key=lambda item: (item[1], tuple(map(int, item[0].split(".")))))


def rounded_maximum(value: int, step: int) -> int:
    return max(step, ((value + step - 1) // step) * step)


def render(entries: list[tuple[str, date]]) -> str:
    grouped: dict[date, list[str]] = defaultdict(list)
    for version, day in entries:
        grouped[day].append(version)
    days = sorted(grouped)
    daily = [len(grouped[day]) for day in days]
    cumulative: list[int] = []
    running = 0
    for count in daily:
        running += count
        cumulative.append(running)

    width, height = 1280, 560
    left, right, top, bottom = 92, 88, 108, 92
    chart_width = width - left - right
    chart_height = height - top - bottom
    max_cumulative = rounded_maximum(max(cumulative), 5)
    max_daily = max(daily)
    x_step = chart_width / max(1, len(days) - 1)

    def x(index: int) -> float:
        return left + index * x_step

    def y_total(value: int) -> float:
        return top + chart_height - (value / max_cumulative) * chart_height

    def y_daily(value: int) -> float:
        return top + chart_height - (value / max_daily) * (chart_height * 0.52)

    line_points = " ".join(f"{x(i):.1f},{y_total(value):.1f}" for i, value in enumerate(cumulative))
    area_points = (
        f"{x(0):.1f},{top + chart_height:.1f} "
        + line_points
        + f" {x(len(days) - 1):.1f},{top + chart_height:.1f}"
    )

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
        '<title id="title">GitGatto release activity</title>',
        '<desc id="desc">Daily and cumulative dated version entries from the changelog.</desc>',
        """<style>
            :root { color-scheme: light dark; }
            .bg { fill: #ffffff; }
            .grid { stroke: #dfe4e8; stroke-width: 1; }
            .axis { fill: #66717d; font: 500 14px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .title { fill: #17202a; font: 700 28px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .subtitle { fill: #66717d; font: 500 14px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .value { fill: #17202a; font: 700 14px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
            .bar { fill: #d8eee9; }
            .area { fill: #e85d24; opacity: .08; }
            .curve { fill: none; stroke: #e85d24; stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
            .point { fill: #ffffff; stroke: #e85d24; stroke-width: 4; }
            .legend-line { stroke: #e85d24; stroke-width: 4; stroke-linecap: round; }
            .legend-bar { fill: #9bcfc3; }
            @media (prefers-color-scheme: dark) {
                .bg { fill: #101419; }
                .grid { stroke: #2b333b; }
                .axis, .subtitle { fill: #9ba7b3; }
                .title, .value { fill: #f3f5f7; }
                .bar { fill: #24483f; }
                .area { opacity: .16; }
                .point { fill: #101419; }
                .legend-bar { fill: #62a897; }
            }
        </style>""",
        '<rect class="bg" x="0" y="0" width="1280" height="560" rx="24"/>',
        '<text class="title" x="64" y="54">GitGatto release activity</text>',
        f'<text class="subtitle" x="64" y="80">Dated CHANGELOG entries · {days[0].isoformat()} — {days[-1].isoformat()}</text>',
        '<line class="legend-line" x1="884" y1="52" x2="916" y2="52"/>',
        '<text class="subtitle" x="926" y="57">Cumulative</text>',
        '<rect class="legend-bar" x="1042" y="44" width="24" height="16" rx="4"/>',
        '<text class="subtitle" x="1076" y="57">Daily</text>',
    ]

    for tick in range(0, max_cumulative + 1, 5):
        y = y_total(tick)
        parts.append(f'<line class="grid" x1="{left}" y1="{y:.1f}" x2="{width - right}" y2="{y:.1f}"/>')
        parts.append(f'<text class="axis" x="{left - 18}" y="{y + 5:.1f}" text-anchor="end">{tick}</text>')

    bar_width = min(70, chart_width / max(1, len(days)) * 0.44)
    for i, (day, count, total) in enumerate(zip(days, daily, cumulative)):
        px = x(i)
        py = y_daily(count)
        bar_height = top + chart_height - py
        versions = ", ".join(grouped[day])
        parts.append(
            f'<rect class="bar" x="{px - bar_width / 2:.1f}" y="{py:.1f}" width="{bar_width:.1f}" height="{bar_height:.1f}" rx="8">'
            f'<title>{html.escape(day.isoformat())}: {html.escape(versions)}</title></rect>'
        )
        parts.append(f'<text class="axis" x="{px:.1f}" y="{top + chart_height + 30:.1f}" text-anchor="middle">{day.strftime("%m-%d")}</text>')
        parts.append(f'<text class="axis" x="{px:.1f}" y="{top + chart_height - 10:.1f}" text-anchor="middle">+{count}</text>')

    parts.append(f'<polygon class="area" points="{area_points}"/>')
    parts.append(f'<polyline class="curve" points="{line_points}"/>')
    for i, total in enumerate(cumulative):
        px, py = x(i), y_total(total)
        parts.append(f'<circle class="point" cx="{px:.1f}" cy="{py:.1f}" r="7"/>')
        parts.append(f'<text class="value" x="{px:.1f}" y="{py - 15:.1f}" text-anchor="middle">{total}</text>')

    parts.extend([
        f'<text class="axis" x="{left}" y="{height - 28}" text-anchor="start">Source: dated release headings in CHANGELOG.md</text>',
        f'<text class="axis" x="{width - right}" y="{height - 28}" text-anchor="end">{len(entries)} version entries</text>',
        '</svg>',
    ])
    return "\n".join(parts) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--changelog", type=Path, default=Path("CHANGELOG.md"))
    parser.add_argument("--output", type=Path, default=Path("docs/media/update-curve.svg"))
    args = parser.parse_args()
    entries = parse_entries(args.changelog)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(entries), encoding="utf-8")
    print(f"Wrote {args.output} from {len(entries)} CHANGELOG entries")


if __name__ == "__main__":
    main()
