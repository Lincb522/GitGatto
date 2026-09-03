#!/usr/bin/env python3
"""Restore GitHub language icons from their pinned upstream SVG sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
import urllib.request
from pathlib import Path


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def repository_slug(url: str) -> str:
    marker = "github.com/"
    if marker not in url:
        raise ValueError(f"Unsupported repository URL: {url}")
    return url.split(marker, 1)[1].removesuffix(".git").strip("/")


def source_bytes(
    *,
    source: str,
    upstream_path: str,
    commit: str,
    repository: str,
    source_root: Path | None,
) -> bytes:
    if source_root is not None:
        local_path = source_root / source / upstream_path
        if local_path.is_file():
            return local_path.read_bytes()

    slug = repository_slug(repository)
    url = f"https://raw.githubusercontent.com/{slug}/{commit}/{upstream_path}"
    request = urllib.request.Request(url, headers={"User-Agent": "GitGatto-icon-importer"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def verified_payload(
    entry: dict[str, object],
    *,
    repositories: dict[str, str],
    commits: dict[str, str],
    source_root: Path | None,
) -> bytes:
    source = str(entry["source"])
    commit = str(entry["source_commit"])
    upstream_path = str(entry["upstream_path"])
    expected_digest = str(entry["sha256"])
    if commits[source] != commit:
        raise ValueError(f"Manifest revision mismatch for {source}")
    payload = source_bytes(
        source=source,
        upstream_path=upstream_path,
        commit=commit,
        repository=repositories[source],
        source_root=source_root,
    )
    actual_digest = sha256(payload)
    if actual_digest != expected_digest:
        raise ValueError(
            f"Checksum mismatch for {source}/{upstream_path}: "
            f"expected {expected_digest}, got {actual_digest}"
        )
    return payload


def main() -> None:
    script_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=script_root)
    parser.add_argument(
        "--source-root",
        type=Path,
        help="Optional directory containing pinned source checkouts named by manifest source key.",
    )
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    manifest_path = project_root / "Sources/GitGatto/Resources/GitHubLanguageIcons.json"
    resource_path = project_root / "Sources/GitGatto/Resources/LanguageIcons"
    manifest = json.loads(manifest_path.read_text())
    repositories = manifest["source_repositories"]
    commits = manifest["source_commits"]

    with tempfile.TemporaryDirectory(prefix="gitgatto-language-icons-") as temp_root:
        staged = Path(temp_root) / "LanguageIcons"
        staged.mkdir()
        imported = 0
        for item in manifest["items"]:
            resource_name = item.get("resource_name")
            if not resource_name:
                continue
            payload = verified_payload(
                item,
                repositories=repositories,
                commits=commits,
                source_root=args.source_root,
            )
            (staged / f"{resource_name}.svg").write_bytes(payload)
            imported += 1

        placeholder = manifest["placeholder"]
        payload = verified_payload(
            placeholder,
            repositories=repositories,
            commits=commits,
            source_root=args.source_root,
        )
        (staged / "placeholder.svg").write_bytes(payload)

        expected_files = int(manifest["total_files"])
        actual_files = len(list(staged.glob("*.svg")))
        if imported != int(manifest["direct_icon_count"]) or actual_files != expected_files:
            raise ValueError(
                f"Incomplete import: {imported} direct icons and {actual_files} files; "
                f"expected {manifest['direct_icon_count']} and {expected_files}"
            )

        backup_path = resource_path.with_name(".LanguageIcons.previous")
        if backup_path.exists():
            shutil.rmtree(backup_path)
        if resource_path.exists():
            resource_path.rename(backup_path)
        try:
            shutil.copytree(staged, resource_path)
        except Exception:
            if resource_path.exists():
                shutil.rmtree(resource_path)
            if backup_path.exists():
                backup_path.rename(resource_path)
            raise
        if backup_path.exists():
            shutil.rmtree(backup_path)

    print(f"Imported {imported} direct SVG icons and one shared Octicon placeholder.")


if __name__ == "__main__":
    main()
