"""Static provenance check; never imports or runs the vendored package."""

import hashlib
import json
import subprocess
from pathlib import Path, PurePosixPath


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    repo = Path(__file__).resolve().parent.parent
    root = repo / "third_party/dartssh2"
    metadata = json.loads((root / "UPSTREAM.json").read_text(encoding="utf-8"))
    if metadata["version"] != "4.1.0" or metadata["archiveSHA256"] != (
        "39359aceafcf5940b868249e3c9c6d86e4e0f989eec7417d033c943157c84c51"
    ):
        raise ValueError("Unexpected SSH upstream identity")
    changed = metadata["patchedFiles"]
    allowed = {
        "lib/src/ssh_client.dart",
        "lib/src/ssh_transport.dart",
        "lib/src/ssh_errors.dart",
    }
    if set(changed) != allowed:
        raise ValueError("SSH policy changes exceed the reviewed file allowlist")
    expected = {**metadata["pristineFiles"], **changed, **metadata["addedFiles"]}
    for name, sha in expected.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or "\\" in name:
            raise ValueError("Invalid SSH provenance path")
        path = root / relative
        if not path.resolve().is_relative_to(root.resolve()) or digest(path) != sha:
            raise ValueError(f"SSH source/provenance mismatch: {name}")
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    if actual != set(expected) | {"UPSTREAM.json"}:
        raise ValueError("Unexpected files in the SSH vendor directory")
    patch = repo / "patches/dartssh2-4.1.0-policy.patch"
    if digest(patch) != metadata["patchSHA256"]:
        raise ValueError("SSH policy patch hash mismatch")
    for name in {*changed, *metadata["addedFiles"]}:
        if b"\r" in (root / name).read_bytes():
            raise ValueError(f"SSH hashes must survive LF checkout: {name}")
    if b"\r" in patch.read_bytes():
        raise ValueError("SSH patch must use LF")
    subprocess.run(
        ["git", "apply", "--reverse", "--check",
         "--directory=third_party/dartssh2", str(patch)],
        cwd=repo, check=True,
    )
    print(f"SSH source provenance passed: {len(expected)} files, 3 policy sources.")


if __name__ == "__main__":
    main()
