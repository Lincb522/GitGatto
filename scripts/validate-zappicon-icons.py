#!/usr/bin/python3
import json
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "icon-system" / "zappicon-icon-manifest.json"


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = [(entry, ROOT / entry["assetPath"]) for entry in manifest["icons"]]
    missing = [str(path.relative_to(ROOT)) for _, path in assets if not path.is_file()]
    if missing:
        raise SystemExit("Missing Zappicon assets:\n" + "\n".join(missing))

    invalid = []
    for entry, path in assets:
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            invalid.append(f"{path.relative_to(ROOT)}: invalid SVG")
            continue
        if root.attrib.get("viewBox") != "0 0 24 24":
            invalid.append(f"{path.relative_to(ROOT)}: expected Zappicon 24x24 keyline")
        if root.find(".//{http://www.w3.org/2000/svg}image") is not None:
            invalid.append(f"{path.relative_to(ROOT)}: embedded raster image")
        if entry.get("zappiconStyle") not in {"Regular", "Filled"}:
            invalid.append(f"{path.relative_to(ROOT)}: unsupported Zappicon style")
        source = path.read_text(encoding="utf-8")
        if "#F1F1F9" in source or "<text" in source:
            invalid.append(f"{path.relative_to(ROOT)}: Figma showcase content")

    if invalid:
        raise SystemExit("Invalid Zappicon assets:\n" + "\n".join(invalid))

    discovered = set((ROOT / "Sources" / "GitGatto" / "Resources" / "UIIcons").glob("gatto-*.svg"))
    expected = {path for _, path in assets}
    unexpected = sorted(path.relative_to(ROOT) for path in discovered - expected)
    if unexpected:
        raise SystemExit("Unexpected UI icon assets:\n" + "\n".join(map(str, unexpected)))

    print(f'Validated {manifest["count"]} Zappicon SVG assets')


if __name__ == "__main__":
    main()
