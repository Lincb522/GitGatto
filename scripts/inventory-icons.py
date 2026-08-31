#!/usr/bin/env python3

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Sources" / "GitGatto"
DESIGN_ROOT = ROOT / "docs" / "icon-system" / "image2-all-icons"
ASSET_ROOT = SOURCE_ROOT / "Resources" / "UIIcons"
OUTPUT = ROOT / "docs" / "icon-system" / "image2-icon-manifest.json"

DIRECT_ICON_ARGUMENT = re.compile(
    r"(?:gattoSymbol|systemImage|systemName|symbol)\s*:\s*\"([^\"]+)\""
)
CORE_OVERRIDES = {
    "ai.translation",
    "archivebox",
    "arrow.down.app",
    "arrow.triangle.branch",
    "clock.arrow.circlepath",
    "gearshape",
    "history.file",
    "rectangle.split.2x1",
    "sparkles",
    "square.grid.2x2",
    "square.stack.3d.up",
    "stethoscope",
}


def source_references(symbol: str) -> list[str]:
    token = f'"{symbol}"'
    references = []
    for path in SOURCE_ROOT.rglob("*.swift"):
        relative = path.relative_to(ROOT).as_posix()
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(),
            start=1,
        ):
            if token in line:
                references.append(f"{relative}:{line_number}")
    return references


def direct_symbols() -> set[str]:
    symbols = set()
    for path in SOURCE_ROOT.rglob("*.swift"):
        symbols.update(DIRECT_ICON_ARGUMENT.findall(path.read_text(encoding="utf-8")))
    return symbols


def main() -> None:
    groups = json.loads((DESIGN_ROOT / "manifest.json").read_text(encoding="utf-8"))
    supplemental = json.loads(
        (DESIGN_ROOT / "supplemental.json").read_text(encoding="utf-8")
    )
    design_sources = {
        name.replace("-", "."): f"batch-{group['batch']}-sheet.png"
        for group in groups
        for name in group["icons"]
    }
    design_sources.update(
        {item["symbol"]: item["source"] for item in supplemental}
    )
    design_sources.update(
        {symbol: "core-agent-monochrome.png" for symbol in CORE_OVERRIDES}
    )

    entries = []
    for symbol in sorted(design_sources):
        asset_name = f"gatto-{symbol.replace('.', '-')}.png"
        asset_path = ASSET_ROOT / asset_name
        if not asset_path.is_file():
            raise SystemExit(f"Missing GitGatto icon asset: {asset_name}")
        entries.append(
            {
                "symbol": symbol,
                "asset": asset_path.relative_to(ROOT).as_posix(),
                "designSource": (
                    DESIGN_ROOT / design_sources[symbol]
                ).relative_to(ROOT).as_posix(),
                "sha256": hashlib.sha256(asset_path.read_bytes()).hexdigest(),
                "sourceRefs": source_references(symbol),
            }
        )

    symbols = {entry["symbol"] for entry in entries}
    missing = sorted(direct_symbols() - symbols)
    if missing:
        raise SystemExit("Missing GitGatto icon mappings: " + ", ".join(missing))

    expected_assets = {Path(entry["asset"]).name for entry in entries}
    unexpected = sorted(
        path.name
        for path in ASSET_ROOT.glob("gatto-*.png")
        if path.name not in expected_assets
    )
    if unexpected:
        raise SystemExit("Unexpected GitGatto icon assets: " + ", ".join(unexpected))

    payload = {
        "schemaVersion": 1,
        "generator": "scripts/inventory-icons.py",
        "designTool": "Infinite Canvas / Image 2",
        "style": {
            "canvas": "256x256 RGBA",
            "rendering": "template tint with point-size 1x/2x/3x raster representations",
        },
        "count": len(entries),
        "icons": entries,
    }
    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"{len(entries)} GitGatto icons -> {OUTPUT}")


if __name__ == "__main__":
    main()
