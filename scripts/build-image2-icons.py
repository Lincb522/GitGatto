#!/usr/bin/env python3

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "icon-system" / "image2-all-icons"
DESTINATION = ROOT / "Sources" / "GitGatto" / "Resources" / "UIIcons"

GRID_4_COLUMNS = [174, 349, 524, 699]
GRID_4_ROWS = [87, 204, 320, 436]
SAFE_AREA = 196
ALPHA_FLOOR = 48
ALPHA_CEILING = 208
BATCH_8_POSITIONS = [
    (145, 109), (291, 109), (437, 109), (581, 109), (726, 109),
    (145, 227), (291, 227), (437, 227), (581, 227), (726, 227),
    (145, 338), (291, 338), (437, 338), (581, 338),
    (145, 445), (291, 445),
]

CORE_POSITIONS = [
    (144, 111), (289, 111), (436, 111), (581, 111), (726, 111),
    (144, 260), (289, 260), (436, 260), (581, 260), (726, 260),
    (144, 409), (289, 409), (436, 409), (581, 409), (726, 409),
]
CORE_SYMBOLS = [
    "square-grid-2x2",
    "arrow-down-app",
    "square-stack-3d-up",
    "archivebox",
    "clock-arrow-circlepath",
    "history-file",
    "arrow-triangle-branch",
    "rectangle-split-2x1",
    "stethoscope",
    "sparkles",
    None,
    None,
    None,
    "ai-translation",
    "gearshape",
]


def background_level(image: Image.Image) -> int:
    histogram = image.histogram()
    return max(range(220, 256), key=histogram.__getitem__)


def clarify_alpha(alpha: Image.Image) -> Image.Image:
    span = ALPHA_CEILING - ALPHA_FLOOR
    return alpha.point(
        [
            max(0, min(255, round((value - ALPHA_FLOOR) * 255 / span)))
            for value in range(256)
        ]
    )


def normalize_template_icon(alpha: Image.Image) -> Image.Image:
    alpha = clarify_alpha(alpha)
    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError("No visible icon content")

    mark = alpha.crop(bounds)
    scale = min(SAFE_AREA / mark.width, SAFE_AREA / mark.height)
    output_size = (
        max(1, round(mark.width * scale)),
        max(1, round(mark.height * scale)),
    )
    mark = clarify_alpha(mark.resize(output_size, Image.Resampling.LANCZOS))

    output = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    ink = Image.new("RGBA", output_size, (0, 0, 0, 255))
    ink.putalpha(mark)
    output.alpha_composite(
        ink,
        ((256 - output_size[0]) // 2, (256 - output_size[1]) // 2),
    )
    return output


def render_icon(
    sheet: Image.Image,
    center: tuple[int, int],
    cell_half_size: tuple[int, int],
) -> Image.Image:
    center_x, center_y = center
    half_width, half_height = cell_half_size
    cell = sheet.crop(
        (
            center_x - half_width,
            center_y - half_height,
            center_x + half_width,
            center_y + half_height,
        )
    )

    paper = background_level(sheet)
    denominator = max(1, paper - 90)
    alpha = cell.point(
        [
            0
            if (value := max(0, min(255, round((paper - gray - 1) * 255 / denominator)))) < 8
            else value
            for gray in range(256)
        ]
    )

    try:
        return normalize_template_icon(alpha)
    except RuntimeError as error:
        raise RuntimeError(f"No icon found at {center}") from error


def write_icon(name: str, image: Image.Image) -> None:
    image.save(DESTINATION / f"gatto-{name}.png", optimize=True)


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))
    expected = set()

    for group in manifest:
        batch = group["batch"]
        sheet = Image.open(SOURCE / f"batch-{batch}-sheet.png").convert("L")
        positions = (
            [(x, y) for y in GRID_4_ROWS for x in GRID_4_COLUMNS]
            if batch != 8
            else BATCH_8_POSITIONS
        )
        half_size = (88, 58) if batch != 8 else (66, 55)
        for name, center in zip(group["icons"], positions, strict=True):
            write_icon(name, render_icon(sheet, center, half_size))
            expected.add(f"gatto-{name}.png")

    core_sheet = Image.open(SOURCE / "core-agent-monochrome.png").convert("L")
    for name, center in zip(CORE_SYMBOLS, CORE_POSITIONS, strict=True):
        if name is not None:
            write_icon(name, render_icon(core_sheet, center, (64, 55)))

    supplemental = json.loads((SOURCE / "supplemental.json").read_text(encoding="utf-8"))
    for item in supplemental:
        source = Image.open(SOURCE / item["source"]).convert("RGBA")
        normalize_template_icon(source.getchannel("A")).save(
            DESTINATION / item["asset"],
            optimize=True,
        )
        expected.add(item["asset"])

    for path in DESTINATION.glob("gatto-*.png"):
        if path.name not in expected:
            path.unlink()

    actual = {path.name for path in DESTINATION.glob("gatto-*.png")}
    if actual != expected:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        raise RuntimeError(f"Icon output mismatch; missing={missing}, unexpected={unexpected}")

    print(f"Generated {len(actual)} GitGatto UI icons in {DESTINATION}")


if __name__ == "__main__":
    main()
