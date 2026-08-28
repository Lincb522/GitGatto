#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "icon-system" / "imagegen-icon-manifest.json"


def metadata(path: Path) -> dict[str, str]:
    output = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    values = {}
    for line in output.splitlines():
        if ":" in line:
            key, value = line.strip().split(":", 1)
            values[key] = value.strip()
    return values


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = [(entry, ROOT / entry["assetPath"]) for entry in manifest["icons"]]
    missing = [str(path.relative_to(ROOT)) for _, path in assets if not path.is_file()]
    if missing:
        raise SystemExit("Missing imagegen icons:\n" + "\n".join(missing))

    invalid = []
    for _, path in assets:
        values = metadata(path)
        if (
            values.get("pixelWidth") != "256"
            or values.get("pixelHeight") != "256"
            or values.get("hasAlpha") != "yes"
        ):
            invalid.append(str(path.relative_to(ROOT)))
    if invalid:
        raise SystemExit("Icons must be 256x256 PNG files with alpha:\n" + "\n".join(invalid))

    print(f'Validated {manifest["count"]} generated UI icons')


if __name__ == "__main__":
    main()
