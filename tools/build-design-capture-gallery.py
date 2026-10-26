#!/usr/bin/env python3
"""Build an offline review gallery from a capture directory's records.jsonl.

Usage: python tools/build-design-capture-gallery.py <absolute-capture-directory>
       [--output-dir <absolute-directory>] [--group-by screen|frame]
       [--no-contact-sheets]

Pillow is needed only for contact sheets (enabled by default). These artifacts
are review aids; generating them does not establish visual acceptance.
"""

from __future__ import annotations

import argparse
import html
import json
import math
import os
import sys
from collections import defaultdict
from pathlib import Path, PurePosixPath, PureWindowsPath
from urllib.parse import quote, urlsplit


def positive_number(value: object, label: str) -> int | float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value <= 0
    ):
        raise ValueError(f"{label} must be a finite positive number")
    return value


def contained_file(root: Path, name: str) -> Path:
    """Resolve only a local, relative file without traversal or symlink escape."""
    normalized = name.replace("\\", "/")
    parsed = urlsplit(normalized)
    if (
        not normalized
        or parsed.scheme
        or parsed.netloc
        or PurePosixPath(normalized).is_absolute()
        or PureWindowsPath(normalized).drive
        or ".." in PurePosixPath(normalized).parts
    ):
        raise ValueError(f"file path must be relative and inside capture directory: {name!r}")
    path = (root / normalized).resolve()
    if not path.is_relative_to(root) or not path.is_file():
        raise ValueError(f"file is missing or outside capture directory: {name!r}")
    return path


def read_records(root: Path) -> list[dict]:
    manifest = contained_file(root, "records.jsonl")
    records = []
    for line_number, line in enumerate(manifest.read_text(encoding="utf-8-sig").splitlines(), 1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
            if not isinstance(record, dict):
                raise ValueError("record must be a JSON object")
            for key in ("screenId", "theme", "png"):
                if not isinstance(record.get(key), str) or not record[key].strip():
                    raise ValueError(f"{key} must be a nonempty string")
            frame = record.get("frame")
            if not isinstance(frame, dict):
                raise ValueError("frame must be an object with width and height")
            positive_number(frame.get("width"), "frame.width")
            positive_number(frame.get("height"), "frame.height")
            positive_number(record.get("scale"), "scale")
            limitations = record.get("limitations", [])
            if not isinstance(limitations, list) or any(
                not isinstance(item, str) for item in limitations
            ):
                raise ValueError("limitations must be an array of strings")
            png = contained_file(root, record["png"])
            if png.suffix.lower() != ".png":
                raise ValueError("png must refer to a .png file")
            with png.open("rb") as source:
                if source.read(8) != b"\x89PNG\r\n\x1a\n":
                    raise ValueError(f"invalid PNG signature: {record['png']!r}")
            records.append({**record, "_path": png})
        except (ValueError, OSError) as error:
            raise ValueError(f"records.jsonl:{line_number}: {error}") from error
    if not records:
        raise ValueError("records.jsonl contains no capture records")
    return records


def frame_label(record: dict) -> str:
    frame = record["frame"]
    return f"{frame['width']:g}x{frame['height']:g}"


def caption(record: dict) -> list[str]:
    view = record.get("view", record.get("variant", "unspecified"))
    limitations = record.get("limitations", [])
    return [
        record["screenId"],
        f"File: {record['png']}",
        f"Frame: {frame_label(record)} | theme: {record['theme']} | scale: {record['scale']:g}",
        f"View: {view} | state: {record.get('state', 'unspecified')}",
        f"Stage: {record.get('captureStage', 'unspecified')} | task: {record.get('captureTask', 'unspecified')}",
        f"Group: {record.get('group', 'unspecified')}",
        *([f"Limitation: {item}" for item in limitations] if limitations else ["Limitations: none supplied."]),
    ]


def local_url(path: Path, output: Path) -> str:
    try:
        relative = os.path.relpath(path, output).replace(os.sep, "/")
        return quote(relative, safe="/")
    except ValueError:  # Different Windows drives cannot have a relative URL.
        return path.as_uri()


def writable_artifact(output: Path, name: str) -> Path:
    path = output / name
    if path.is_symlink():
        raise ValueError(f"refusing to overwrite output symlink: {path}")
    return path


def contact_sheets(groups: list[tuple[str, list[dict]]], output: Path) -> list[Path]:
    try:
        from PIL import Image, ImageDraw, ImageFont, ImageOps
    except ImportError as error:
        raise ValueError("Pillow is required for contact sheets; install it or use --no-contact-sheets") from error

    # Prefer a system font with Cyrillic coverage; repository webfonts may be subsets.
    font_paths = [
        Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts/arial.ttf",
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path(__file__).resolve().parents[1] / "assets/fonts/NotoSans-Regular.ttf",
    ]
    font_path = next((path for path in font_paths if path.is_file()), None)
    font = ImageFont.truetype(str(font_path), 18) if font_path else ImageFont.load_default(size=18)
    line_height = 27
    cell_width, thumb_height, gap, padding = 720, 800, 16, 14
    text_width = cell_width - 2 * padding

    def wrap(text: str, max_width: int = text_width) -> list[str]:
        lines, current = [], ""
        for word in text.split():
            candidate = f"{current} {word}" if current else word
            if font.getlength(candidate) <= max_width:
                current = candidate
                continue
            if current:
                lines.append(current)
                current = ""
            # Split only words that cannot fit on an otherwise empty line.
            for character in word:
                if current and font.getlength(current + character) > max_width:
                    lines.append(current)
                    current = ""
                current += character
        return [*lines, current]

    sheets = []
    for group_number, (title, captures) in enumerate(groups, 1):
        for page, offset in enumerate(range(0, len(captures), 8), 1):
            batch = captures[offset : offset + 8]
            labels = [[line for part in caption(record) for line in wrap(part)] for record in batch]
            row_heights = [
                thumb_height + 3 * padding + line_height * max(len(label) for label in labels[index : index + 2])
                for index in range(0, len(batch), 2)
            ]
            width = 2 * cell_width + 3 * gap
            heading = wrap(f"{title} | page {page} | THUMBNAIL OVERVIEW ONLY; open original PNG for exact review", width - 2 * gap)
            heading_height = len(heading) * line_height + 2 * padding
            height = heading_height + sum(row_heights) + (len(row_heights) + 1) * gap
            sheet = Image.new("RGB", (width, height), "#e8ecf0")
            draw = ImageDraw.Draw(sheet)
            for index, line in enumerate(heading):
                draw.text((gap, padding + index * line_height), line, font=font, fill="#172131")
            y = heading_height + gap
            for index, (record, label) in enumerate(zip(batch, labels)):
                row, column = divmod(index, 2)
                x = gap + column * (cell_width + gap)
                draw.rectangle((x, y, x + cell_width, y + row_heights[row]), fill="white")
                with Image.open(record["_path"]) as source:
                    if source.format != "PNG":
                        raise ValueError(f"not a PNG image: {record['_path']}")
                    thumbnail = ImageOps.contain(source.convert("RGBA"), (text_width, thumb_height))
                    sheet.paste(thumbnail, (x + padding + (text_width - thumbnail.width) // 2, y + padding), thumbnail)
                for line_number, line in enumerate(label):
                    draw.text((x + padding, y + thumb_height + 2 * padding + line_number * line_height), line, font=font, fill="#172131")
                if column == 1 or index == len(batch) - 1:
                    y += row_heights[row] + gap
            path = writable_artifact(output, f"contact-{group_number:03d}-{page:02d}.jpg")
            sheet.save(path, "JPEG", quality=90)
            sheets.append(path)
    return sheets


def write_gallery(groups: list[tuple[str, list[dict]]], sheets: list[Path], output: Path) -> Path:
    escape = html.escape
    parts = ["""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Design capture review gallery</title><style>
body{font:16px/1.5 system-ui,sans-serif;margin:0;background:#edf0f4;color:#172131}main{max-width:1600px;margin:auto;padding:24px}
a{color:#1355a0}nav{display:flex;flex-wrap:wrap;gap:8px 18px;margin:20px 0}section{scroll-margin-top:16px;margin:32px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,350px),1fr));gap:20px}figure{margin:0;background:white;border:1px solid #bec7d2;border-radius:8px;overflow:hidden}
.preview{display:flex;height:340px;align-items:flex-start;justify-content:center;overflow:auto;background:#d8dee7;padding:8px}.preview img{max-width:100%;max-height:100%;object-fit:contain;object-position:top}
figcaption{padding:16px;overflow-wrap:anywhere}figcaption p{margin:0 0 8px}ul{padding-left:22px}details{margin-top:12px}pre{font:12px/1.5 monospace;white-space:pre-wrap;overflow-wrap:anywhere}
.notice{padding:14px 18px;border-left:4px solid #ad6500;background:#fff5dd}h2{font-size:22px}
</style></head><body><main><h1>Design capture review gallery</h1>
<p class="notice">User review artifact only. Gallery generation and thumbnail contact sheets do not establish visual acceptance.
Open each original PNG for exact pixel review. Captures retain their recorded limitations.</p>"""]
    count = sum(len(captures) for _, captures in groups)
    parts.append(f"<p>{count} captures in {len(groups)} groups. All content is local; no network dependencies.</p>")
    if sheets:
        parts.append("<details><summary>Thumbnail contact sheets</summary><nav>")
        for sheet in sheets:
            parts.append(f'<a href="{escape(local_url(sheet, output), quote=True)}">{escape(sheet.name)}</a>')
        parts.append("</nav></details>")
    parts.append("<nav aria-label='Capture groups'>")
    for number, (title, _) in enumerate(groups, 1):
        parts.append(f'<a href="#group-{number}">{escape(title)}</a>')
    parts.append("</nav>")
    for number, (title, captures) in enumerate(groups, 1):
        parts.append(f'<section id="group-{number}"><h2>{escape(title)} ({len(captures)})</h2><div class="grid">')
        for record in captures:
            url = escape(local_url(record["_path"], output), quote=True)
            lines = caption(record)
            parts.append(f'<figure><a class="preview" href="{url}"><img loading="lazy" src="{url}" alt="{escape(lines[0], quote=True)}"></a><figcaption>')
            parts.append(f"<p><strong>{escape(lines[0])}</strong></p>")
            for line in lines[1:6]:
                parts.append(f"<p>{escape(line)}</p>")
            limitations = record.get("limitations", [])
            if limitations:
                parts.append("<details open><summary>Recorded limitations</summary><ul>")
                parts.extend(f"<li>{escape(item)}</li>" for item in limitations)
                parts.append("</ul></details>")
            else:
                parts.append("<p>Recorded limitations: none supplied.</p>")
            metadata = {key: value for key, value in record.items() if key != "_path"}
            parts.append(f'<p><a href="{url}">Open original PNG</a></p><details><summary>Full capture metadata</summary><pre>{escape(json.dumps(metadata, ensure_ascii=False, indent=2))}</pre></details></figcaption></figure>')
        parts.append("</div></section>")
    parts.append("</main></body></html>\n")
    gallery = writable_artifact(output, "gallery.html")
    gallery.write_text("\n".join(parts), encoding="utf-8")
    return gallery


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("capture_directory", type=Path)
    parser.add_argument("--output-dir", type=Path, help="defaults to the capture directory")
    parser.add_argument("--group-by", choices=("screen", "frame"), default="screen")
    parser.add_argument("--no-contact-sheets", action="store_true", help="generate only HTML; requires no Pillow")
    args = parser.parse_args()
    try:
        if not args.capture_directory.is_absolute():
            raise ValueError("capture directory must be an absolute path")
        root = args.capture_directory.resolve()
        if not root.is_dir():
            raise ValueError(f"capture directory does not exist: {root}")
        output = args.output_dir if args.output_dir is not None else root
        if not output.is_absolute():
            raise ValueError("output directory must be an absolute path")
        output = output.resolve()
        records = read_records(root)
        grouped = defaultdict(list)
        for record in records:
            key = record["screenId"] if args.group_by == "screen" else f"{frame_label(record)} | {record['theme']} | scale {record['scale']:g}"
            grouped[key].append(record)
        groups = sorted(grouped.items())
        for _, captures in groups:
            captures.sort(key=lambda record: (record["screenId"], record["frame"]["width"], record["frame"]["height"], record["theme"], record["scale"], str(record.get("captureStage", "")), str(record.get("variant", "")), record["png"]))
        output.mkdir(parents=True, exist_ok=True)
        sheets = [] if args.no_contact_sheets else contact_sheets(groups, output)
        gallery = write_gallery(groups, sheets, output)
        print(f"Wrote {gallery} ({len(records)} captures, {len(sheets)} contact sheets).")
        print("Review artifact only; visual acceptance requires separate review.")
        return 0
    except (ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
