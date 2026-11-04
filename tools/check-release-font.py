"""Static audit: release must contain the full pinned SDK icon font."""
import argparse
from pathlib import Path


def verify_font(bundled: Path, expected: Path) -> None:
    expected_bytes = expected.read_bytes()
    bundled_bytes = bundled.read_bytes()
    if not expected_bytes or bundled_bytes != expected_bytes:
        raise ValueError('Release MaterialIcons font is empty or differs from the SDK font')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundled', required=True, type=Path)
    parser.add_argument('--expected', required=True, type=Path)
    args = parser.parse_args()
    verify_font(args.bundled, args.expected)
    print('Release MaterialIcons audit passed: full SDK font included.')


if __name__ == '__main__':
    main()
