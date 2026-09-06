#!/usr/bin/env python3
"""Build a versioned Neo modpack archive and its update manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "pack.json"
DIST = ROOT / "dist"
VERSION_PATTERN = re.compile(r"^[0-9A-Za-z][0-9A-Za-z._-]*$")
ALREADY_COMPRESSED = {
    ".7z", ".avi", ".gif", ".gz", ".jar", ".jpeg", ".jpg", ".mp3",
    ".mp4", ".ogg", ".png", ".rar", ".webm", ".webp", ".xz", ".zip",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def iter_files(path: Path):
    if path.is_file():
        yield path
        return
    if path.is_dir():
        yield from sorted(item for item in path.rglob("*") if item.is_file())


def collect_files(config: dict) -> list[tuple[Path, str, str]]:
    collected: list[tuple[Path, str, str]] = []
    destinations: set[str] = set()

    for source_name in config["managed_paths"]:
        source = ROOT / source_name
        for file_path in iter_files(source):
            relative = file_path.relative_to(ROOT).as_posix()
            if relative in destinations:
                raise RuntimeError(f"Ruta duplicada en el paquete: {relative}")
            destinations.add(relative)
            collected.append((file_path, relative, "managed"))

    for source_name in config.get("preference_files", []):
        source = ROOT / source_name
        if not source.is_file():
            continue
        destination = f".neo/defaults/{source_name}"
        collected.append((source, destination, "preference_default"))

    return collected


def build(version: str) -> tuple[Path, Path]:
    if not VERSION_PATTERN.fullmatch(version):
        raise ValueError("La versión solo puede contener letras, números, puntos, guiones y guiones bajos.")

    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    files = collect_files(config)
    if not any(destination.startswith("mods/") for _, destination, _ in files):
        raise RuntimeError("No se encontraron mods; se canceló la publicación.")

    DIST.mkdir(exist_ok=True)
    safe_name = re.sub(r"[^0-9A-Za-z._-]+", "-", config["name"]).strip("-")
    archive_name = f"{safe_name}-{version}.zip"
    archive_path = DIST / archive_name
    manifest_path = DIST / "manifest.json"

    file_manifest = []
    for source, destination, category in files:
        file_manifest.append({
            "path": destination,
            "size": source.stat().st_size,
            "sha256": sha256(source),
            "category": category,
        })

    pack_manifest = {
        "schema_version": config["schema_version"],
        "name": config["name"],
        "version": version,
        "minecraft_version": config["minecraft_version"],
        "loader": config["loader"],
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "files": file_manifest,
    }

    with tempfile.NamedTemporaryFile(dir=DIST, suffix=".zip.tmp", delete=False) as temp:
        temporary_archive = Path(temp.name)

    try:
        with zipfile.ZipFile(temporary_archive, "w", allowZip64=True) as archive:
            for source, destination, _ in files:
                compression = zipfile.ZIP_STORED if source.suffix.lower() in ALREADY_COMPRESSED else zipfile.ZIP_DEFLATED
                archive.write(source, destination, compress_type=compression, compresslevel=6)
            archive.writestr(
                ".neo/pack-manifest.json",
                json.dumps(pack_manifest, ensure_ascii=False, indent=2) + "\n",
                compress_type=zipfile.ZIP_DEFLATED,
                compresslevel=6,
            )
        temporary_archive.replace(archive_path)
    finally:
        temporary_archive.unlink(missing_ok=True)

    tag = f"v{version}"
    release_manifest = {
        **{key: value for key, value in pack_manifest.items() if key != "files"},
        "archive": {
            "filename": archive_name,
            "size": archive_path.stat().st_size,
            "sha256": sha256(archive_path),
            "url": f"https://github.com/{config['repository']}/releases/download/{tag}/{archive_name}",
        },
        "file_count": len(file_manifest),
    }
    manifest_path.write_text(
        json.dumps(release_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return archive_path, manifest_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Genera el ZIP publicable del modpack Neo.")
    parser.add_argument("version", nargs="?", help="Versión de la publicación, por ejemplo 1.0.0")
    args = parser.parse_args()
    version = args.version or input("Versión del modpack (ej. 1.0.0): ").strip()

    try:
        archive, manifest = build(version)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Paquete:   {archive}")
    print(f"Manifiesto: {manifest}")
    print(f"SHA-256:   {sha256(archive)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
