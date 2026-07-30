from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
import tarfile
from pathlib import Path

from .model import Manifest


def _safe_relative(value: str) -> Path:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe archive destination: {value}")
    return path


def _normalized(info: tarfile.TarInfo) -> tarfile.TarInfo:
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0
    if info.isdir():
        info.mode = 0o755
    else:
        info.mode &= 0o777
    return info


def _add_path(archive: tarfile.TarFile, source: Path, destination: Path) -> None:
    paths = [source]
    if source.is_dir():
        paths.extend(sorted(source.rglob("*"), key=lambda item: item.as_posix()))
    for path in paths:
        relative = path.relative_to(source) if path != source else Path()
        arcname = (destination / relative).as_posix().rstrip("/")
        info = _normalized(archive.gettarinfo(str(path), arcname=arcname))
        if info.issym() or info.islnk():
            target = Path(info.linkname)
            if target.is_absolute() or ".." in target.parts:
                raise ValueError(f"unsafe packaged symlink: {path} -> {target}")
        if info.isfile():
            with path.open("rb") as stream:
                archive.addfile(info, stream)
        else:
            archive.addfile(info)


def package_tool(
    manifest: Manifest,
    platform: str,
    build_dir: Path,
    artifacts_dir: Path,
) -> Path:
    package_dir = artifacts_dir / "packages"
    package_dir.mkdir(parents=True, exist_ok=True)
    output = package_dir / f"{manifest.id}-{platform}.tar.gz"
    temporary = output.with_suffix(".tmp")
    variables = {
        "root": str(manifest.directory.parent.parent),
        "tool": str(manifest.directory),
        "build": str(build_dir),
        "artifacts": str(artifacts_dir),
        "platform": platform,
    }
    with (
        temporary.open("wb") as raw,
        gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as compressed,
        tarfile.open(
            fileobj=compressed,
            mode="w",
            format=tarfile.PAX_FORMAT,
        ) as archive,
    ):
        manifest_bytes = (
            json.dumps(manifest.data, indent=2, ensure_ascii=False) + "\n"
        ).encode()
        info = tarfile.TarInfo("tool.json")
        info.size = len(manifest_bytes)
        info.mode = 0o644
        archive.addfile(_normalized(info), io.BytesIO(manifest_bytes))
        for item in manifest.data["package"]["files"]:
            source = Path(item["source"].format_map(variables))
            if not source.is_absolute():
                source = manifest.directory / source
            if not source.exists():
                raise FileNotFoundError(f"package source does not exist: {source}")
            destination = _safe_relative(item["destination"])
            _add_path(archive, source, destination)
    os.replace(temporary, output)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + ".sha256").write_text(
        f"{digest}  {output.name}\n",
        encoding="utf-8",
    )
    return output


def package_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
