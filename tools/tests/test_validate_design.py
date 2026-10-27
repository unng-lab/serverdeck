"""Exercise static reference invariants without editing canonical files."""

import importlib.util
import json
from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "validate_design", REPO / "tools" / "validate-design.py"
)
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class DesignReferenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        design = REPO / "docs" / "design"
        cls.manifest_text = (design / "screens.json").read_text(encoding="utf-8-sig")
        cls.html = (design / "ServerDeck-design.html").read_text(encoding="utf-8-sig")
        cls.related_texts = {
            name: (design / name).read_text(encoding="utf-8-sig")
            for name in ("README.md", "DESIGN.md")
        }
        cls.screen_map = (REPO / VALIDATOR.SCREEN_MAP).read_text(encoding="utf-8-sig")
        cls.reference_files = {
            path: (REPO / path).read_bytes() for path in VALIDATOR.REFERENCE_FILES
        }

    def validate(self, **overrides):
        arguments = {
            "manifest_text": self.manifest_text,
            "html": self.html,
            "related_texts": self.related_texts,
            "screen_map_text": self.screen_map,
            "reference_files": self.reference_files,
        }
        arguments.update(overrides)
        return VALIDATOR.validate_reference(REPO, **arguments)

    def assert_rejected(self, result, message):
        self.assertFalse(result["ok"], result)
        self.assertTrue(any(message in error for error in result["errors"]), result)

    def test_canonical_reference_has_expected_provenance(self):
        result = self.validate()

        self.assertTrue(result["ok"], result["errors"])
        self.assertEqual(
            result["source_provenance"], {"implemented": 35, "planned": 63}
        )
        self.assertTrue(result["embedded_manifest_matches"])
        self.assertEqual(
            result["screen_map"],
            {"rows": 98, "unique_ids": 98, "origins": 35, "concepts": 63,
             "source_owners_retained": True},
        )
        self.assertTrue(result["license_matches"])
        self.assertEqual(result["tokens"]["sha256"], VALIDATOR.TOKEN_SHA256)
        self.assertEqual(result["scope"], "static_reference_only")

    def test_synchronized_provenance_mutations_are_rejected(self):
        assignment = re.search(r"\bwindow\.SERVERDECK_SCREENS\s*=\s*", self.html)
        self.assertIsNotNone(assignment)
        _, end = VALIDATOR.DECODER.raw_decode(self.html, assignment.end())

        for implemented in (False, True):
            with self.subTest(implemented=implemented):
                screens = json.loads(self.manifest_text)
                for screen in screens:
                    screen["implemented"] = implemented
                manifest = json.dumps(screens, ensure_ascii=False)
                html = self.html[:assignment.end()] + manifest + self.html[end:]

                result = self.validate(manifest_text=manifest, html=html)

                self.assertTrue(result["embedded_manifest_matches"])
                self.assertEqual(
                    result["source_provenance"],
                    {
                        "implemented": 98 if implemented else 0,
                        "planned": 0 if implemented else 98,
                    },
                )
                self.assert_rejected(
                    result,
                    "expected 35 implemented origins and 63 planned concepts",
                )

    def test_duplicate_screen_map_id_is_rejected(self):
        changed = self.screen_map.replace("`02-service-unavailable`", "`01-startup`", 1)
        self.assert_rejected(self.validate(screen_map_text=changed), "duplicate screen IDs")

    def test_replaced_screen_map_id_is_rejected(self):
        changed = self.screen_map.replace("`01-startup`", "`01-unknown`", 1)
        result = self.validate(screen_map_text=changed)
        self.assertEqual(result["screen_map"]["unique_ids"], 98)
        self.assert_rejected(result, "IDs differ from screens.json")

    def test_screen_map_classifications_match_each_manifest_id(self):
        lines = self.screen_map.splitlines()
        origin = next(index for index, line in enumerate(lines) if line.startswith("| `01-startup`"))
        concept = next(index for index, line in enumerate(lines) if line.startswith("| `11-host-key-changed`"))
        lines[origin], lines[concept] = lines[concept], lines[origin]
        result = self.validate(screen_map_text="\n".join(lines))

        self.assertEqual(result["screen_map"]["origins"], 35)
        self.assertEqual(result["screen_map"]["concepts"], 63)
        self.assert_rejected(result, "01-startup: expected origin classification")
        self.assert_rejected(result, "11-host-key-changed: expected concept classification")

    def test_each_row_must_retain_its_source_owner_link(self):
        owner = "[lib/shell/readiness_view.dart](../../lib/shell/readiness_view.dart)"
        changed = self.screen_map.replace(owner, "`lib/shell/readiness_view.dart`", 1)
        self.assert_rejected(
            self.validate(screen_map_text=changed),
            "01-startup: missing source owner links: lib/shell/readiness_view.dart",
        )

    def test_source_owner_links_are_normalized(self):
        changed = self.screen_map.replace(
            "(../../lib/shell/readiness_view.dart)",
            "(<../../lib/shell/../shell/%72eadiness_view.dart#ReadinessView>)",
            1,
        )
        result = self.validate(screen_map_text=changed)
        self.assertTrue(result["ok"], result["errors"])

    def test_concepts_cannot_claim_runtime_acceptance(self):
        changed = self.screen_map.replace(
            "`concept; not-runtime-accepted`", "`concept; passed`", 1
        )
        self.assert_rejected(
            self.validate(screen_map_text=changed), "concept must remain not-runtime-accepted"
        )

    def test_token_hash_must_match_snapshot(self):
        changed = dict(self.reference_files)
        changed[VALIDATOR.TOKEN_SOURCE] += b"\n"
        self.assert_rejected(
            self.validate(reference_files=changed),
            "SHA-256 differs from the T001 canonical snapshot",
        )

    def test_document_token_source_links_are_required(self):
        for path in ("docs/design/README.md", "docs/design/DESIGN.md"):
            with self.subTest(path=path):
                changed = dict(self.reference_files)
                changed[path] = changed[path].replace(
                    b"../brandbook/tokens/serverdeck.tokens.json", b"screens.json"
                )
                self.assert_rejected(
                    self.validate(reference_files=changed),
                    f"{path}: missing Markdown link to canonical token source",
                )

    def test_stable_reference_files_are_required(self):
        for path in sorted(VALIDATOR.REFERENCE_FILES):
            with self.subTest(path=path):
                changed = dict(self.reference_files)
                del changed[path]
                self.assert_rejected(
                    self.validate(reference_files=changed),
                    f"{path}: required reference file is missing",
                )

    def test_design_license_must_match_bundled_source(self):
        changed = dict(self.reference_files)
        changed["docs/design/OFL.txt"] += b"changed"
        self.assert_rejected(
            self.validate(reference_files=changed),
            "docs/design/OFL.txt: differs from assets/brand/fonts/OFL.txt",
        )


if __name__ == "__main__":
    unittest.main()
