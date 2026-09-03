#!/usr/bin/env python3

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "docs" / "icon-system" / "reicon-icon-map.json"
ASSET_ROOT = ROOT / "Sources" / "GitGatto" / "Resources" / "UIIcons"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import pinned Reicon SVG paths into GitGatto.")
    parser.add_argument(
        "--reicon-root",
        type=Path,
        required=True,
        help="Path to a checkout of https://github.com/Lincb522/reicon",
    )
    return parser.parse_args()


def svg_document(fragment: str, view_box: str) -> str:
    body = re.sub(r"currentColor", "#000000", fragment, flags=re.IGNORECASE)
    body = re.sub(r'fill="white"', 'fill="#000000"', body, flags=re.IGNORECASE)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="{view_box}">{body}</svg>'
    )


def imported_svg(source: dict, dataset: dict, view_box: str) -> str:
    if source_file := source.get("sourceFile"):
        path = ROOT / source_file
        payload = path.read_bytes()
        actual_hash = hashlib.sha256(payload).hexdigest()
        if actual_hash != source["sha256"]:
            raise SystemExit(
                f"Reicon source hash mismatch for {source['name']}: "
                f"expected {source['sha256']}, found {actual_hash}"
            )
        return payload.decode("utf-8")

    category = source["category"]
    name = source["name"]
    weight = source.get("weight", "Outline")
    try:
        fragment = dataset["categories"][category]["icons"][name]["weights"][weight]["code"]
    except KeyError as error:
        raise SystemExit(f"Missing Reicon source: {category}/{name}/{weight}") from error
    return svg_document(fragment, view_box)


def validate_svg(path: Path) -> None:
    root = ET.fromstring(path.read_text(encoding="utf-8"))
    if root.tag.rsplit("}", 1)[-1] != "svg":
        raise RuntimeError(f"Expected SVG root for {path.name}")
    if not root.attrib.get("viewBox"):
        raise RuntimeError(f"Missing viewBox for {path.name}")


def main() -> None:
    args = arguments()
    mapping = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    reicon_root = args.reicon_root.expanduser().resolve()
    dataset_path = reicon_root / "data" / "icon-data.json"
    dataset = json.loads(dataset_path.read_text(encoding="utf-8"))

    expected_revision = mapping["source"]["revision"]
    git_head = subprocess.check_output(
        ["git", "-C", str(reicon_root), "rev-parse", "HEAD"],
        text=True,
    ).strip()
    if git_head != expected_revision:
        raise SystemExit(
            f"Reicon revision mismatch: expected {expected_revision}, found {git_head}"
        )

    view_box = mapping["rendering"]["viewBox"]
    icons = mapping["icons"]

    with tempfile.TemporaryDirectory(prefix="gitgatto-reicon-") as temporary:
        output_root = Path(temporary)
        for symbol, source in sorted(icons.items()):
            output = output_root / f"gatto-{symbol.replace('.', '-')}.svg"
            output.write_text(imported_svg(source, dataset, view_box), encoding="utf-8")
            validate_svg(output)

        expected_names = {path.name for path in output_root.glob("gatto-*.svg")}
        if len(expected_names) != len(icons):
            raise SystemExit("Reicon import did not produce one asset per semantic icon")

        ASSET_ROOT.mkdir(parents=True, exist_ok=True)
        for old_asset in [*ASSET_ROOT.glob("gatto-*.png"), *ASSET_ROOT.glob("gatto-*.svg")]:
            if old_asset.name not in expected_names:
                old_asset.unlink()
        for output in output_root.glob("gatto-*.svg"):
            shutil.copy2(output, ASSET_ROOT / output.name)

    print(f"Imported {len(icons)} Reicon assets into {ASSET_ROOT}")


if __name__ == "__main__":
    main()
