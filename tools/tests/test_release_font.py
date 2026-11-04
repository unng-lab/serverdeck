"""Isolated unit tests for the static release font audit."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


_spec = importlib.util.spec_from_file_location(
    'release_font', Path(__file__).resolve().parents[1] / 'check-release-font.py')
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)


class ReleaseFontTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.expected = Path(self.temporary.name) / 'sdk.otf'
        self.bundled = Path(self.temporary.name) / 'bundled.otf'
        self.expected.write_bytes(b'synthetic full font')

    def test_accepts_identical_nonempty_font(self):
        self.bundled.write_bytes(self.expected.read_bytes())
        _module.verify_font(self.bundled, self.expected)

    def test_rejects_subset_or_modified_font(self):
        for data in [b'synthetic', b'Synthetic full font', b'']:
            with self.subTest(data=data):
                self.bundled.write_bytes(data)
                with self.assertRaises(ValueError):
                    _module.verify_font(self.bundled, self.expected)

    def test_rejects_empty_source_even_when_identical(self):
        self.expected.write_bytes(b'')
        self.bundled.write_bytes(b'')
        with self.assertRaises(ValueError):
            _module.verify_font(self.bundled, self.expected)

    def test_rejects_missing_bundle(self):
        with self.assertRaises(FileNotFoundError):
            _module.verify_font(self.bundled, self.expected)

    def test_rejects_missing_source(self):
        self.expected.unlink()
        self.bundled.write_bytes(b'synthetic full font')
        with self.assertRaises(FileNotFoundError):
            _module.verify_font(self.bundled, self.expected)


if __name__ == '__main__':
    unittest.main()
