import hashlib
import tempfile
import unittest
from pathlib import Path
from release_manifest import manifest, version


class ReleaseTests(unittest.TestCase):
    def test_version_and_hash(self):
        self.assertRegex(version(), r"^\d+\.\d+\.\d+\+\d+$")
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "ServerDeck-1.2.3+4-windows-x64.msi").write_bytes(b"fixture")
            result = manifest(directory, "1.2.3+4", "changes")
            asset = result["assets"]["windows-x64"]
            self.assertEqual(asset["size"], 7)
            self.assertEqual(asset["sha256"], hashlib.sha256(b"fixture").hexdigest())
            self.assertIn("v1.2.3%2B4/ServerDeck-1.2.3%2B4", asset["url"])
            with self.assertRaises(ValueError):
                manifest(directory, "1.2.3+4", require_all=True)
            (directory / "ServerDeck-1.2.3+4-windows-x64.msi").write_bytes(b"")
            with self.assertRaises(ValueError):
                manifest(directory, "1.2.3+4")


if __name__ == "__main__":
    unittest.main()
