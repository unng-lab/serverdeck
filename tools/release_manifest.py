"""Shared version source and desktop release manifest. Standard library only."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import quote, unquote, urljoin

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {"windows-x64": ".msi", "macos-x64": ".dmg", "macos-arm64": ".dmg", "linux-x64": ".deb"}


def version(root=ROOT):
    found = re.search(r"^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$", (root / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    if not found:
        raise ValueError("Stable version+build required in pubspec.yaml")
    return found[1]


def manifest(directory, release_version, notes="", require_all=False):
    assets = {}
    for platform, suffix in PLATFORMS.items():
        name = f"ServerDeck-{release_version}-{platform}{suffix}"
        package = directory / name
        if not package.is_file():
            if require_all:
                raise ValueError(f"Missing {name}")
            continue
        size = package.stat().st_size
        if not 1 <= size <= 1073741824:
            raise ValueError(f"Invalid package size: {name}")
        with package.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        assets[platform] = {"url": "https://github.com/unng-lab/serverdeck/releases/download/" + quote("v" + release_version, safe="") + "/" + quote(name, safe=""), "size": size, "sha256": digest}
    if not assets or len(notes) > 20000:
        raise ValueError("Packages required; notes <=20000 chars")
    return {"schemaVersion": 1, "version": release_version, "notes": notes, "assets": assets}


def isar_library(platform):
    config = ROOT / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    package = next(item for item in packages if item["name"] == "isar_community_flutter_libs")
    uri = urljoin(config.as_uri(), package["rootUri"])
    path = Path(unquote(uri.removeprefix("file://")))
    if __import__("os").name == "nt" and str(path).startswith("\\"):
        path = Path(str(path).lstrip("\\"))
    result = path / platform / ("libisar.dylib" if platform == "macos" else "libisar.so")
    if not result.is_file():
        raise ValueError(f"Isar missing: {result}")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", action="store_true")
    parser.add_argument("--isar-library", choices=["macos", "linux"])
    parser.add_argument("--assets", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--require-all", action="store_true")
    args = parser.parse_args()
    if args.version:
        print(version())
    elif args.isar_library:
        print(isar_library(args.isar_library))
    else:
        if not args.assets or not args.output:
            parser.error("--assets and --output required")
        result = manifest(args.assets, version(), args.notes.read_text(encoding="utf-8") if args.notes else "", args.require_all)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
