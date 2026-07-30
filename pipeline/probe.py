from __future__ import annotations

import argparse
import os
import subprocess
import tarfile
import tempfile
from pathlib import Path


def _safe_members(archive: tarfile.TarFile) -> list[tarfile.TarInfo]:
    members = archive.getmembers()
    for member in members:
        path = Path(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"unsafe archive member: {member.name}")
        if member.issym() or member.islnk():
            target = Path(member.linkname)
            if target.is_absolute() or ".." in target.parts:
                raise ValueError(
                    f"unsafe archive link: {member.name} -> {member.linkname}"
                )
    return members


def extract(archive_path: Path, destination: Path) -> None:
    with tarfile.open(archive_path, "r:gz") as archive:
        archive.extractall(destination, members=_safe_members(archive), filter="data")


def main() -> int:
    parser = argparse.ArgumentParser()
    subcommands = parser.add_subparsers(dest="command", required=True)
    contains = subcommands.add_parser("contains")
    contains.add_argument("archive", type=Path)
    contains.add_argument("member")
    execute = subcommands.add_parser("exec")
    execute.add_argument("archive", type=Path)
    execute.add_argument("member")
    execute.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="human-tools-smoke-") as temporary:
        root = Path(temporary)
        extract(args.archive, root)
        target = root / args.member
        if not target.exists():
            raise FileNotFoundError(f"{args.member} is absent from {args.archive}")
        if args.command == "contains":
            return 0
        arguments = args.arguments
        if arguments[:1] == ["--"]:
            arguments = arguments[1:]
        environment = os.environ.copy()
        environment["HUMAN_TOOLS_SMOKE_ROOT"] = str(root)
        return subprocess.run(
            [str(target), *arguments], env=environment, check=False
        ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
