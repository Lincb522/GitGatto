#!/usr/bin/env python3

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Sources" / "GitGatto"
MAP_PATH = ROOT / "docs" / "icon-system" / "reicon-icon-map.json"
ASSET_ROOT = SOURCE_ROOT / "Resources" / "UIIcons"
OUTPUT = ROOT / "docs" / "icon-system" / "reicon-icon-manifest.json"

DIRECT_ICON_ARGUMENT = re.compile(
    r"(?:gattoSymbol|systemImage|systemName|symbol)\s*:\s*\"([^\"]+)\""
)
ICON_PROPERTY = re.compile(r"\bvar\s+(?:systemImage|icon|symbol)\s*:\s*String\s*\{")
ICON_PROPERTY_VALUE = re.compile(r'(?:\A\s*|:\s*(?:return\s+)?|\breturn\s+)"([^"\\]+)"')


def matching_brace(text: str, opening_brace: int) -> int:
    depth = 0
    in_string = False
    escaped = False
    for index in range(opening_brace, len(text)):
        character = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return index
    raise RuntimeError("Unbalanced icon property")
def source_reference_index() -> dict[str, list[str]]:
    references = {}
    for path in SOURCE_ROOT.rglob("*.swift"):
        relative = path.relative_to(ROOT).as_posix()
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for token in set(re.findall(r'"([^"\\]+)"', line)):
                references.setdefault(token, []).append(f"{relative}:{number}")
    return references


def direct_symbols() -> set[str]:
    symbols = set()
    for path in SOURCE_ROOT.rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        symbols.update(DIRECT_ICON_ARGUMENT.findall(source))
        for match in ICON_PROPERTY.finditer(source):
            opening_brace = match.end() - 1
            body = source[opening_brace + 1 : matching_brace(source, opening_brace)]
            symbols.update(ICON_PROPERTY_VALUE.findall(body))
    return symbols


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate or validate bundled UI icon provenance.")
    parser.add_argument("--check", action="store_true", help="Validate without writing the manifest")
    options = parser.parse_args()
    mapping = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    icon_sources = mapping["icons"]

    references = source_reference_index()
    entries = []
    for symbol in sorted(icon_sources):
        asset_name = f"gatto-{symbol.replace('.', '-')}.svg"
        asset_path = ASSET_ROOT / asset_name
        if not asset_path.is_file():
            raise SystemExit(f"Missing GitGatto icon asset: {asset_name}")
        source = icon_sources[symbol]
        provenance = {
            "repository": mapping["source"]["repository"],
            "revision": mapping["source"]["revision"],
            "name": source["name"],
        }
        if "sourceFile" in source:
            provenance.update(
                {
                    "sourceFile": source["sourceFile"],
                    "sourceURL": source["sourceURL"],
                    "sourceSHA256": source["sha256"],
                }
            )
        else:
            provenance.update(
                {
                    "category": source["category"],
                    "weight": source.get("weight", "Outline"),
                }
            )
        entries.append(
            {
                "symbol": symbol,
                "asset": asset_path.relative_to(ROOT).as_posix(),
                "source": provenance,
                "sha256": hashlib.sha256(asset_path.read_bytes()).hexdigest(),
                "sourceRefs": references.get(symbol, []),
            }
        )

    symbols = {entry["symbol"] for entry in entries}
    missing = sorted(direct_symbols() - symbols)
    if missing:
        raise SystemExit("Missing GitGatto icon mappings: " + ", ".join(missing))

    expected_assets = {Path(entry["asset"]).name for entry in entries}
    unexpected = sorted(
        path.name
        for path in ASSET_ROOT.glob("gatto-*.*")
        if path.name not in expected_assets
    )
    if unexpected:
        raise SystemExit("Unexpected GitGatto icon assets: " + ", ".join(unexpected))

    payload = {
        "schemaVersion": 1,
        "generator": "scripts/inventory-icons.py",
        "source": mapping["source"],
        "style": {
            "source": "SVG with a transparent canvas",
            "rendering": "template tint with pixel-aligned point-size 1x/2x/3x representations",
        },
        "count": len(entries),
        "icons": entries,
    }
    if options.check:
        recorded = json.loads(OUTPUT.read_text(encoding="utf-8"))
        # Reference line numbers change with surrounding code; resource identity must not.
        for manifest in (recorded, payload):
            for entry in manifest["icons"]:
                entry.pop("sourceRefs", None)
        if recorded != payload:
            raise SystemExit("Icon manifest is stale; run python3 scripts/inventory-icons.py")
        print(f"{len(entries)} GitGatto icons: mappings, assets and hashes verified")
        return
    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"{len(entries)} GitGatto icons -> {OUTPUT}")


if __name__ == "__main__":
    main()
