#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

VERSION = "2.0.0"
INCLUDE = (
    re.compile(
        r"(?:^|/)(?:bin|obj)/(?:Debug|Release|net\d|netstandard|netcoreapp|x64|x86|AnyCPU)/",
        re.IGNORECASE,
    ),
    re.compile(
        r"(?:^|/)(?:bin|obj)/.*\.(?:dll|pdb|exe|nupkg|snupkg|cache|assets\.json)$",
        re.IGNORECASE,
    ),
    re.compile(r"(?:^|/)target/(?:debug|release)/", re.IGNORECASE),
    re.compile(
        r"(?:^|/)(?:build|out)/.*\.(?:dll|pdb|exe|o|a|so|dylib)$",
        re.IGNORECASE,
    ),
)
EXCLUDE = re.compile(
    r"(?:^|/)(?:wwwroot/lib|node_modules|vendor|third_party)/",
    re.IGNORECASE,
)
SKIP_DIRECTORIES = {".git", "node_modules", "vendor", "third_party"}


@dataclass(frozen=True)
class Finding:
    repository: Path
    files: tuple[str, ...]


def repositories(roots: list[Path], depth: int) -> list[Path]:
    found: set[Path] = set()
    for requested in roots:
        root = requested.expanduser().resolve()
        if not root.is_dir():
            raise NotADirectoryError(root)
        for directory, names, files in os.walk(root):
            current = Path(directory)
            relative_depth = len(current.relative_to(root).parts)
            if ".git" in names or ".git" in files:
                found.add(current)
            names[:] = [
                name
                for name in names
                if name not in SKIP_DIRECTORIES and relative_depth < depth
            ]
    return sorted(found)


def tracked_files(repository: Path) -> tuple[str, ...]:
    process = subprocess.run(
        ["git", "-C", str(repository), "ls-files", "-z"],
        check=True,
        stdout=subprocess.PIPE,
    )
    return tuple(
        value.decode("utf-8", errors="surrogateescape")
        for value in process.stdout.split(b"\0")
        if value
    )


def is_artifact(path: str) -> bool:
    return not EXCLUDE.search(path) and any(pattern.search(path) for pattern in INCLUDE)


def scan(roots: list[Path], depth: int) -> tuple[list[Finding], int]:
    candidates = repositories(roots, depth)
    findings = [
        Finding(
            repository,
            tuple(path for path in tracked_files(repository) if is_artifact(path)),
        )
        for repository in candidates
    ]
    return [finding for finding in findings if finding.files], len(candidates)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        prog="repo-hygiene",
        description="Find build output committed to Git repositories.",
    )
    result.add_argument("roots", nargs="*", type=Path, default=[Path.cwd()])
    result.add_argument("-d", "--depth", type=int, default=6)
    result.add_argument("-n", "--max-show", type=int, default=4)
    result.add_argument("-v", "--verbose", action="store_true")
    result.add_argument("-q", "--quiet", action="store_true")
    result.add_argument("--color", choices=("auto", "always", "never"), default="auto")
    result.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    return result


def main(arguments: list[str] | None = None) -> int:
    args = parser().parse_args(arguments)
    if args.depth < 0 or args.max_show < 1:
        parser().error("depth must be non-negative and max-show must be positive")
    try:
        findings, count = scan(args.roots, args.depth)
    except (NotADirectoryError, subprocess.CalledProcessError) as error:
        print(f"repo-hygiene: {error}", file=sys.stderr)
        return 2
    if args.quiet:
        return int(bool(findings))
    color = args.color == "always" or (args.color == "auto" and sys.stdout.isatty())
    yellow = "\033[1;33m" if color else ""
    grey = "\033[0;90m" if color else ""
    reset = "\033[0m" if color else ""
    for finding in findings:
        print(f"{yellow}{finding.repository}{reset}  ({len(finding.files)} files)")
        shown = finding.files if args.verbose else finding.files[: args.max_show]
        for path in shown:
            print(f"      {grey}{path}{reset}")
        remaining = len(finding.files) - len(shown)
        if remaining:
            print(f"      {grey}... and {remaining} more (-v to list){reset}")
    if findings:
        print(f"\nScanned {count} repos. Build output is tracked in the repos above.")
        return 1
    print(f"clean — {count} repos scanned, no tracked build output")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
