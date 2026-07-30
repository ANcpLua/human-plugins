from __future__ import annotations

import argparse
import os
import re
import uuid
from pathlib import Path


def render(source: Path, destination: Path, *, home: Path, current: Path) -> None:
    content = source.read_text(encoding="utf-8")
    content = content.replace("{home}", str(home)).replace("{current}", str(current))
    if re.search(r"\{[a-z][a-z0-9_]*\}", content):
        raise ValueError(f"unresolved service template placeholder in {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--home", required=True, type=Path)
    parser.add_argument("--current", required=True, type=Path)
    args = parser.parse_args()
    render(args.source, args.destination, home=args.home, current=args.current)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
