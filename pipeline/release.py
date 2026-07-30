from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from .model import Manifest


def _digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def write_index(
    manifests: list[Manifest],
    directory: Path,
    *,
    commit: str,
    tag: str,
) -> Path:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("release commit must be a full Git SHA")
    expected = [
        (manifest.id, platform)
        for manifest in manifests
        for platform in manifest.platforms
    ]
    assets: list[dict[str, str]] = []
    for tool, platform in expected:
        name = f"{tool}-{platform}.tar.gz"
        package = directory / name
        checksum = directory / f"{name}.sha256"
        if not package.is_file() or not checksum.is_file():
            raise FileNotFoundError(f"release asset pair is incomplete: {name}")
        digest = _digest(package)
        try:
            recorded, recorded_name = (
                checksum.read_text(encoding="utf-8").strip().split()
            )
        except ValueError as error:
            raise ValueError(f"invalid checksum record: {checksum}") from error
        if recorded_name != name or recorded != digest:
            raise ValueError(f"checksum does not match package: {name}")
        assets.append(
            {
                "tool": tool,
                "platform": platform,
                "name": name,
                "sha256": digest,
            }
        )
    index = {
        "schemaVersion": 1,
        "repository": "ANcpLua/human-plugins",
        "commit": commit,
        "tag": tag,
        "assets": assets,
    }
    output = directory / "release.json"
    output.write_text(
        json.dumps(index, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return output
