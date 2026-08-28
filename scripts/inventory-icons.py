#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "Sources" / "GitGatto"
OUTPUT = ROOT / "docs" / "icon-system" / "imagegen-icon-manifest.json"

STRING = re.compile(r'"([a-z0-9]+(?:\.[a-z0-9]+)*|[a-z]+)"')
ICON_MEMBER = re.compile(r'\b(?:var|func)\s+(?:icon|systemImage|symbol|statusSymbol|iconName)\b')
LOCALIZATION_PREFIXES = (
    "about.", "action.", "ai.", "changes.", "codex.", "conflict.",
    "diagnostics.", "error.", "github.", "legal.", "nav.", "repository.",
    "settings.", "stash.", "sync.", "update.", "worktree."
)
NON_ICONS = {
    "approved", "available", "cancelled", "checking", "comment", "completed",
    "current", "failed", "merge", "neutral", "rebase", "revert", "running",
    "skipped", "success", "unknown", "conflict.txt",
    "c", "cpp", "gif", "go", "h", "jpeg", "jpg", "js", "json", "jsx",
    "m", "md", "mm", "plist", "png", "py", "rs", "rst", "svg", "swift",
    "toml", "ts", "tsx", "txt", "webp", "yaml", "yml"
}


def category(symbol: str) -> str:
    if symbol.startswith(("arrow", "chevron", "point.")):
        return "navigation"
    if symbol.startswith(("checkmark", "exclamationmark", "xmark", "info", "circle", "record", "lock")):
        return "status"
    if symbol.startswith(("doc", "folder", "archivebox", "shippingbox", "tray", "internaldrive", "externaldrive", "photo")):
        return "files"
    if symbol.startswith(("person", "bubble", "text.bubble", "building", "location", "globe", "house", "star", "link")):
        return "people-and-web"
    if symbol in {"terminal", "curlybraces.square", "stethoscope", "clock.arrow.circlepath", "clock.badge.checkmark", "rectangle.split.2x1"}:
        return "git-and-code"
    return "actions-and-tools"


def extract() -> dict[str, set[str]]:
    symbols: dict[str, set[str]] = {}
    for path in SOURCE_ROOT.rglob("*.swift"):
        lines = path.read_text(encoding="utf-8").splitlines()
        relative = path.relative_to(ROOT).as_posix()
        for index, line in enumerate(lines):
            candidates: set[str] = set()
            if (
                "systemName:" in line
                or "systemImage:" in line
                or "gattoSymbol:" in line
                or "GattoIcon(" in line
            ):
                block = "\n".join(lines[max(0, index - 1): min(len(lines), index + 5)])
                candidates.update(STRING.findall(block))
            if ICON_MEMBER.search(line):
                depth = 0
                started = False
                block_lines: list[str] = []
                for current in range(index, min(len(lines), index + 50)):
                    block_lines.append(lines[current])
                    depth += lines[current].count("{") - lines[current].count("}")
                    started = started or "{" in lines[current]
                    if started and depth <= 0:
                        break
                candidates.update(STRING.findall("\n".join(block_lines)))
            for value in candidates:
                if value in NON_ICONS or value.startswith(LOCALIZATION_PREFIXES):
                    continue
                if value.endswith((".title", ".body")):
                    continue
                symbols.setdefault(value, set()).add(f"{relative}:{index + 1}")
    return symbols


def main() -> None:
    symbols = extract()
    entries = []
    for source_symbol in sorted(symbols):
        asset_id = "gatto-" + source_symbol.replace(".", "-")
        entries.append({
            "sourceSymbol": source_symbol,
            "assetID": asset_id,
            "category": category(source_symbol),
            "assetPath": f"Sources/GitGatto/Resources/UIIcons/{asset_id}.png",
            "sourceRefs": sorted(symbols[source_symbol]),
        })
    payload = {
        "schemaVersion": 1,
        "generator": "scripts/inventory-icons.py",
        "source": "SwiftUI systemName/systemImage references and icon properties",
        "imageGenerator": "built-in imagegen",
        "style": {
            "canvas": "256x256 transparent PNG master",
            "delivery": ["24x24@1x", "48x48@2x", "72x72@3x"],
            "stroke": "dark single-color contour, rounded caps and joins, consistent optical weight",
            "shape": "friendly geometric, softly asymmetric, compact silhouette, 24 px readable",
            "accent": "none in template master; application tint supplies theme and state color",
            "avoid": [
                "SF Symbols geometry", "Apple-native proportions", "background tile", "gradient",
                "shadow", "3D", "text", "letters", "watermark", "blur", "hairline detail"
            ]
        },
        "count": len(entries),
        "icons": entries
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(entries)} icons -> {OUTPUT}")


if __name__ == "__main__":
    main()
