#!/usr/bin/env python3
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "icon-system" / "image2-icon-manifest.json"
CATALOG = ROOT / "Sources" / "GitGatto" / "Resources" / "Assets.xcassets" / "GattoIcons"
SIZES = ((24, "1x"), (48, "2x"), (72, "3x"))


def dimensions(path: Path) -> tuple[int, int]:
    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    values = {}
    for line in result.splitlines():
        if ":" in line:
            key, value = line.strip().split(":", 1)
            values[key] = value.strip()
    return int(values["pixelWidth"]), int(values["pixelHeight"])


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    masters = [(entry, ROOT / entry["master"]) for entry in manifest["icons"]]
    missing = [str(path.relative_to(ROOT)) for _, path in masters if not path.is_file()]
    if missing:
        raise SystemExit("Missing image2 masters:\n" + "\n".join(missing))
    invalid = [
        str(path.relative_to(ROOT))
        for _, path in masters
        if dimensions(path) != (256, 256)
    ]
    if invalid:
        raise SystemExit("Masters must be 256x256 PNG files:\n" + "\n".join(invalid))

    with tempfile.TemporaryDirectory(prefix="gitgatto-icons-") as temporary:
        staged_catalog = Path(temporary) / "GattoIcons"
        staged_catalog.mkdir(parents=True)
        (staged_catalog / "Contents.json").write_text(
            json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
            encoding="utf-8",
        )
        for entry, master in masters:
            imageset = staged_catalog / f'{entry["assetID"]}.imageset'
            imageset.mkdir()
            images = []
            for pixels, scale in SIZES:
                filename = f'{entry["assetID"]}@{scale}.png'
                subprocess.run(
                    ["sips", "-s", "format", "png", "-z", str(pixels), str(pixels), str(master), "--out", str(imageset / filename)],
                    check=True,
                    stdout=subprocess.DEVNULL,
                )
                images.append({"filename": filename, "idiom": "universal", "scale": scale})
            contents = {
                "images": images,
                "info": {"author": "xcode", "version": 1},
                "properties": {"template-rendering-intent": "template"},
            }
            (imageset / "Contents.json").write_text(
                json.dumps(contents, indent=2) + "\n",
                encoding="utf-8",
            )
        if CATALOG.exists():
            shutil.rmtree(CATALOG)
        shutil.copytree(staged_catalog, CATALOG)
    print(f'Installed {manifest["count"]} image2 icons into {CATALOG.relative_to(ROOT)}')


if __name__ == "__main__":
    main()
