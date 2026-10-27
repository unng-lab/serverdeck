#!/usr/bin/env python3
"""Read-only, offline checks for the canonical design reference.

`implemented` records a screen's source provenance. Neither that flag nor a
successful validation establishes acceptance of the running application.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath, PureWindowsPath
from urllib.parse import unquote, urlsplit


REPO = Path(__file__).resolve().parents[1]
EXPECTED_NAV = {"Серверы", "ПО", "Журналы", "Задания", "Настройки"}
EXPECTED_WIDTHS = {360, 390, 800, 1100}
SCREEN_MAP = "specs/003-design-system/screen-map.md"
TOKEN_SOURCE = "docs/brandbook/tokens/serverdeck.tokens.json"
TOKEN_SHA256 = "294B3FE4F7ADCB1319F89FC4A2EB2872C8BA84A81CD05CCDA610D9895DA8A2D0"
REFERENCE_FILES = {
    "docs/design/README.md",
    "docs/design/DESIGN.md",
    "docs/design/OFL.txt",
    "assets/brand/fonts/OFL.txt",
    TOKEN_SOURCE,
}
FONT_ASSETS = {
    "assets/fonts/NotoSans-Regular.ttf",
    "assets/fonts/NotoSans-SemiBold.ttf",
    "assets/fonts/NotoSansMono-Regular.ttf",
}
LOGO_ASSETS = {
    f"assets/logos/{kind}-{theme}.svg"
    for kind in ("logo", "mark")
    for theme in ("dark", "light")
}


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def invalid_constant(value: str) -> None:
    raise ValueError(f"non-JSON numeric constant: {value}")


DECODER = json.JSONDecoder(
    object_pairs_hook=unique_object, parse_constant=invalid_constant
)


class ReferenceHTML(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.elements: list[tuple[str, dict]] = []
        self.scripts: list[str] = []
        self.styles: list[str] = []
        self.active: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.elements.append((tag, dict(attrs)))
        if tag in ("script", "style"):
            self.active = tag
            (self.scripts if tag == "script" else self.styles).append("")

    def handle_endtag(self, tag: str) -> None:
        if tag == self.active:
            self.active = None

    def handle_data(self, data: str) -> None:
        if self.active == "script":
            self.scripts[-1] += data
        elif self.active == "style":
            self.styles[-1] += data


def embedded_json(scripts: list[str], name: str) -> object:
    pattern = re.compile(r"\bwindow\." + re.escape(name) + r"\s*=\s*")
    assignments = [
        (script, match.end())
        for script in scripts
        for match in pattern.finditer(script)
    ]
    if len(assignments) != 1:
        raise ValueError(f"expected one window.{name} assignment; found {len(assignments)}")
    script, start = assignments[0]
    value, end = DECODER.raw_decode(script, start)
    if script[end:].lstrip() and not script[end:].lstrip().startswith(";"):
        raise ValueError(f"window.{name} must be a JSON literal followed by a semicolon")
    return value


def is_data_url(value: object, *, image: bool = False) -> bool:
    if not isinstance(value, str):
        return False
    header, separator, payload = value.partition(",")
    return bool(
        separator
        and payload.strip()
        and header.startswith("data:image/" if image else "data:")
    )


def markdown_link_paths(text: str, document: Path, repo: Path) -> set[Path]:
    paths = set()
    for destination in re.findall(r"\[[^\]]*\]\(\s*(<[^>]+>|[^\s)]+)\s*\)", text):
        destination = destination.strip("<>")
        parts = urlsplit(destination)
        path = unquote(parts.path).replace("\\", "/")
        if parts.scheme or parts.netloc or not path or PureWindowsPath(path).drive:
            continue
        target = (document.parent / path).resolve()
        if target.is_relative_to(repo.resolve()):
            paths.add(target)
    return paths


def validate_screen_map(
    repo: Path, text: str, screens: object, errors: list[str]
) -> dict:
    rows = []
    classification = None
    for line in text.splitlines():
        if re.match(r"^#{1,6}\s", line):
            heading = re.match(r"^## (Existing35|Concepts63):", line)
            classification = (
                {"Existing35": "origin", "Concepts63": "concept"}[heading[1]]
                if heading else None
            )
        if not line.strip().startswith("|"):
            continue
        cells = re.split(r"(?<!\\)\|", line.strip().strip("|"))
        screen_id = re.fullmatch(r"\s*`([^`]+)`(?:\s+—.*)?\s*", cells[0])
        if screen_id:
            rows.append((screen_id[1], classification, line))
    ids = [screen_id for screen_id, _, _ in rows]
    duplicates = sorted(key for key, count in Counter(ids).items() if count > 1)
    if duplicates:
        errors.append(f"{SCREEN_MAP}: duplicate screen IDs: " + ", ".join(duplicates))
    if len(rows) != 98 or len(set(ids)) != 98:
        errors.append(
            f"{SCREEN_MAP}: expected 98 rows with unique IDs; "
            f"found {len(rows)} rows and {len(set(ids))} unique IDs"
        )
    counts = Counter(kind for _, kind, _ in rows)
    if counts["origin"] != 35 or counts["concept"] != 63 or counts[None]:
        errors.append(f"{SCREEN_MAP}: expected 35 origin rows and 63 concept rows in their sections")
    manifest = {
        screen["id"]: screen
        for screen in screens if isinstance(screen, dict) and isinstance(screen.get("id"), str)
    } if isinstance(screens, list) else {}
    if set(ids) != set(manifest):
        missing = sorted(set(manifest) - set(ids))
        extra = sorted(set(ids) - set(manifest))
        errors.append(f"{SCREEN_MAP}: IDs differ from screens.json; missing={missing}, extra={extra}")
    owners_retained = True
    for screen_id, kind, row in rows:
        screen = manifest.get(screen_id)
        if screen is None:
            continue
        expected = "origin" if screen.get("implemented") is True else "concept"
        if kind != expected:
            errors.append(f"{SCREEN_MAP}: {screen_id}: expected {expected} classification")
        if kind == "concept" and "`concept; not-runtime-accepted`" not in row:
            errors.append(f"{SCREEN_MAP}: {screen_id}: concept must remain not-runtime-accepted")
        source = screen.get("source")
        if not isinstance(source, str):
            continue
        links = markdown_link_paths(row, repo / SCREEN_MAP, repo)
        missing = [
            part.strip().replace("\\", "/")
            for part in source.split(";")
            if (repo / part.strip().replace("\\", "/")).resolve() not in links
        ]
        if missing:
            owners_retained = False
            errors.append(f"{SCREEN_MAP}: {screen_id}: missing source owner links: {', '.join(missing)}")
    return {
        "rows": len(rows), "unique_ids": len(set(ids)),
        "origins": counts["origin"], "concepts": counts["concept"],
        "source_owners_retained": owners_retained,
    }


def validate_reference(
    repo: Path,
    manifest_text: str,
    html: str,
    related_texts: dict[str, str] | None = None,
    *,
    screen_map_text: str | None = None,
    reference_files: dict[str, bytes] | None = None,
) -> dict:
    errors: list[str] = []
    result = {"ok": False, "scope": "static_reference_only"}
    if reference_files is None:
        reference_files = {
            path: (repo / path).read_bytes()
            for path in REFERENCE_FILES if (repo / path).is_file()
        }
    missing_files = sorted(REFERENCE_FILES - reference_files.keys())
    for path in missing_files:
        errors.append(f"{path}: required reference file is missing")
    result["reference_files"] = len(REFERENCE_FILES) - len(missing_files)
    design_license = reference_files.get("docs/design/OFL.txt")
    bundled_license = reference_files.get("assets/brand/fonts/OFL.txt")
    license_matches = design_license is not None and design_license == bundled_license
    result["license_matches"] = license_matches
    if design_license is not None and bundled_license is not None and not license_matches:
        errors.append("docs/design/OFL.txt: differs from assets/brand/fonts/OFL.txt")
    tokens = reference_files.get(TOKEN_SOURCE)
    if tokens is not None:
        digest = hashlib.sha256(tokens).hexdigest().upper()
        result["tokens"] = {"source": TOKEN_SOURCE, "sha256": digest}
        if digest != TOKEN_SHA256:
            errors.append(f"{TOKEN_SOURCE}: SHA-256 differs from the T001 canonical snapshot")
    for path in ("docs/design/README.md", "docs/design/DESIGN.md"):
        if path in reference_files:
            text = reference_files[path].decode("utf-8-sig")
            if (repo / TOKEN_SOURCE).resolve() not in markdown_link_paths(text, repo / path, repo):
                errors.append(f"{path}: missing Markdown link to canonical token source {TOKEN_SOURCE}")
    if screen_map_text is None:
        map_path = repo / SCREEN_MAP
        if map_path.is_file():
            screen_map_text = map_path.read_text(encoding="utf-8-sig")
        else:
            errors.append(f"{SCREEN_MAP}: required screen map is missing")
    texts = {
        "screens.json": manifest_text,
        "ServerDeck-design.html": html,
        SCREEN_MAP: screen_map_text or "",
        **(related_texts or {}),
    }
    for filename, text in texts.items():
        if re.search(r"\b[A-Za-z]:[/\\]", text):
            errors.append(f"{filename}: machine-specific absolute drive path found")
    try:
        screens = DECODER.decode(manifest_text)
    except ValueError as error:
        screens = None
        errors.append(f"screens.json: invalid JSON ({error})")
    source_files: set[str] = set()
    ids: list[str] = []
    nav: set[str] = set()
    implemented = 0
    if not isinstance(screens, list):
        errors.append("screens.json: root must be a JSON array")
    else:
        result["screens"] = len(screens)
        if len(screens) != 98:
            errors.append(f"screens.json: expected 98 screens; found {len(screens)}")
        for index, screen in enumerate(screens, 1):
            context = f"screen[{index}]"
            if not isinstance(screen, dict):
                errors.append(f"{context}: must be a JSON object")
                continue
            screen_id = screen.get("id")
            if not isinstance(screen_id, str) or not screen_id.strip():
                errors.append(f"{context}: id must be a nonempty string")
            else:
                ids.append(screen_id)
                context = screen_id
            section = screen.get("nav")
            if not isinstance(section, str) or section not in EXPECTED_NAV:
                errors.append(f"{context}: nav must name one of the five main sections")
            else:
                nav.add(section)
            if type(screen.get("implemented")) is not bool:
                errors.append(f"{context}: implemented must be a JSON boolean (source provenance)")
            elif screen["implemented"]:
                implemented += 1
            source = screen.get("source")
            if not isinstance(source, str) or not source.strip():
                errors.append(f"{context}: source must contain repository-relative file paths")
                continue
            for part in source.split(";"):
                path = part.strip().replace("\\", "/")
                relative = PurePosixPath(path)
                if (
                    not path
                    or relative.is_absolute()
                    or PureWindowsPath(path).drive
                    or ".." in relative.parts
                    or ":" in path
                ):
                    errors.append(f"{context}: source entry must be a repository-relative path")
                    continue
                target = (repo / path).resolve()
                if not target.is_relative_to(repo.resolve()) or not target.is_file():
                    errors.append(f"{context}: source file is missing or outside repository: {path}")
                else:
                    source_files.add(path)
        duplicates = sorted(key for key, count in Counter(ids).items() if count > 1)
        if duplicates:
            errors.append("screens.json: duplicate screen IDs: " + ", ".join(duplicates))
        if len(set(ids)) != 98:
            errors.append(f"screens.json: expected 98 unique nonempty IDs; found {len(set(ids))}")
        if nav != EXPECTED_NAV:
            errors.append("screens.json: not all five main navigation sections are represented")
        result.update(
            unique_ids=len(set(ids)),
            nav_sections=len(nav),
            source_files=len(source_files),
        )
        result["source_provenance"] = {
            "implemented": implemented,
            "planned": len(screens) - implemented,
        }
        if implemented != 35 or len(screens) - implemented != 63:
            errors.append(
                "screens.json: expected 35 implemented origins and 63 planned concepts; "
                f"found {implemented} implemented origins and "
                f"{len(screens) - implemented} planned concepts"
            )

    if screen_map_text is not None:
        result["screen_map"] = validate_screen_map(repo, screen_map_text, screens, errors)

    document = ReferenceHTML()
    document.feed(html)
    document.close()
    try:
        embedded = embedded_json(document.scripts, "SERVERDECK_SCREENS")
        matches = screens is not None and json.dumps(
            embedded, sort_keys=True
        ) == json.dumps(screens, sort_keys=True)
        result["embedded_manifest_matches"] = matches
        if not matches:
            errors.append("ServerDeck-design.html: embedded manifest differs from screens.json")
    except ValueError as error:
        errors.append(f"ServerDeck-design.html: {error}")

    widths = [
        attrs.get("data-width")
        for tag, attrs in document.elements
        if tag == "button" and "data-width" in attrs
    ]
    if Counter(widths) != Counter(str(width) for width in EXPECTED_WIDTHS):
        errors.append("ServerDeck-design.html: expected exactly four width buttons: 360, 390, 800, 1100")
    else:
        result["width_controls"] = sorted(EXPECTED_WIDTHS)
    theme_buttons = [
        attrs
        for tag, attrs in document.elements
        if tag == "button" and attrs.get("id") == "theme-button"
    ]
    css = "\n".join(document.styles)
    dark_default = any(
        tag == "html" and attrs.get("data-theme") == "dark"
        for tag, attrs in document.elements
    )
    light_selector = re.search(r"\[data-theme\s*=\s*['\"]?light['\"]?\s*\]", css)
    if (
        len(theme_buttons) != 1
        or not dark_default
        or not light_selector
        or not re.search(r":root\s*\{", css)
    ):
        errors.append("ServerDeck-design.html: expected a theme button, default dark palette and light palette")
    else:
        result["themes"] = 2

    try:
        assets = embedded_json(document.scripts, "SERVERDECK_ASSETS")
        if not isinstance(assets, dict):
            raise ValueError("window.SERVERDECK_ASSETS must be a JSON object")
        for path in sorted(FONT_ASSETS | LOGO_ASSETS):
            if not is_data_url(assets.get(path), image=path in LOGO_ASSETS):
                errors.append(f"ServerDeck-design.html: missing embedded data URL for {path}")
        faces = re.findall(r"@font-face\s*\{([^}]+)\}", css, re.IGNORECASE)
        font_urls = [
            url.strip(" \t\r\n'\"")
            for face in faces
            for url in re.findall(r"url\(([^)]+)\)", face, re.IGNORECASE)
        ]
        font_assets = [assets.get(path) for path in FONT_ASSETS]
        if (
            len(faces) != 3
            or len(font_urls) != 3
            or not all(is_data_url(url) for url in font_urls)
        ):
            errors.append("ServerDeck-design.html: all three @font-face sources must be embedded data URLs")
        elif all(is_data_url(url) for url in font_assets) and Counter(font_urls) != Counter(font_assets):
            errors.append("ServerDeck-design.html: CSS font data URLs differ from embedded font assets")
        result.update(embedded_fonts=len(FONT_ASSETS), embedded_logos=len(LOGO_ASSETS))
    except ValueError as error:
        errors.append(f"ServerDeck-design.html: {error}")
    result.update(ok=not errors, errors=errors)
    return result


def main() -> int:
    try:
        design = REPO / "docs" / "design"
        result = validate_reference(
            REPO,
            (design / "screens.json").read_text(encoding="utf-8-sig"),
            (design / "ServerDeck-design.html").read_text(encoding="utf-8-sig"),
            {
                filename: (design / filename).read_text(encoding="utf-8-sig")
                for filename in ("README.md", "DESIGN.md")
                if (design / filename).is_file()
            },
        )
    except (OSError, ValueError) as error:
        result = {"ok": False, "scope": "static_reference_only", "errors": [str(error)]}
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
