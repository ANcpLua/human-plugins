#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

VERSION = "2.0.0"
REQUIRED = (
    "HUMAN_AGENT_COMMAND",
    "HUMAN_TERMINAL_EXECUTABLE",
    "hs.task.new",
    "hs.eventtap.new",
    "humanAgentLauncherStatus",
)
FORBIDDEN = (
    "--dangerously-skip-permissions",
    "/Users/",
    "CLAUDE-FABLE",
    "hs.execute",
)


def default_config() -> Path:
    return Path(__file__).resolve().parent.parent / "share" / "init.lua"


def validate(path: Path) -> None:
    source = path.resolve(strict=True).read_text(encoding="utf-8")
    missing = [fragment for fragment in REQUIRED if fragment not in source]
    forbidden = [fragment for fragment in FORBIDDEN if fragment in source]
    if missing or forbidden:
        details = []
        if missing:
            details.append(f"missing: {', '.join(missing)}")
        if forbidden:
            details.append(f"forbidden: {', '.join(forbidden)}")
        raise ValueError("; ".join(details))


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="hammerspoon-claude-launcher-doctor")
    parser.add_argument("--version", action="version", version=VERSION)
    parser.add_argument("config", nargs="?", type=Path, default=default_config())
    args = parser.parse_args(arguments)
    try:
        validate(args.config)
    except (OSError, ValueError) as error:
        print(f"hammerspoon-claude-launcher: {error}", file=sys.stderr)
        return 1
    print(f"hammerspoon-claude-launcher {VERSION} ok: {args.config}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
