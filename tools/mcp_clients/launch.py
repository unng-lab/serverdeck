"""Fixed isolated loader for the two private acceptance clients."""
from pathlib import Path
import runpy
import sys


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("wire", "sdk"):
        raise ValueError("ACTOR_CONFIGURATION")
    directory = Path(__file__).resolve().parent
    sys.path.insert(0, str(directory))
    runpy.run_path(str(directory / (sys.argv[1] + "_client.py")), run_name="__main__")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.stderr.write("MCP_ACTOR_FAILED\n")
        sys.exit(1)
