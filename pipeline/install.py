from __future__ import annotations

import hashlib
import hmac
import json
import os
import platform as host_platform
import re
import shutil
import subprocess
import tempfile
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .model import Manifest, ManifestError, validate_manifest
from .probe import extract
from .service import render as render_service

REPOSITORY = "ANcpLua/human-plugins"
RELEASE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")


class InstallFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class Installed:
    tool: str
    release: str
    digest: str
    path: Path
    previous: str | None


@dataclass(frozen=True)
class _Backup:
    target: Path
    saved: Path | None


def _platform() -> str:
    system = host_platform.system()
    if system == "Darwin":
        return "macos"
    if system == "Linux":
        return "linux"
    raise InstallFailure(f"unsupported host platform: {system}")


def _run(
    argv: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None
) -> None:
    process = subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if process.stdout:
        print(process.stdout, end="")
    if process.returncode:
        raise InstallFailure(f"{' '.join(argv)} exited {process.returncode}")


def _atomic_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def _atomic_symlink(target: str, link: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    temporary = link.with_name(f".{link.name}.{uuid.uuid4().hex}.tmp")
    temporary.symlink_to(target)
    os.replace(temporary, link)


def _digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def _release_tag(repository: str, release: str) -> str:
    if release != "latest":
        if not RELEASE_NAME.fullmatch(release):
            raise InstallFailure(f"unsafe release name: {release}")
        return release
    process = subprocess.run(
        [
            "gh",
            "release",
            "view",
            "--repo",
            repository,
            "--json",
            "tagName",
            "--jq",
            ".tagName",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if process.returncode:
        raise InstallFailure(process.stderr.strip() or "cannot resolve latest release")
    tag = process.stdout.strip()
    if not RELEASE_NAME.fullmatch(tag):
        raise InstallFailure(f"GitHub returned an unsafe release name: {tag!r}")
    return tag


def download_verified(
    tool: str,
    platform: str,
    *,
    repository: str = REPOSITORY,
    release: str = "latest",
    destination: Path,
) -> tuple[Path, str]:
    tag = _release_tag(repository, release)
    asset = f"{tool}-{platform}.tar.gz"
    checksum = f"{asset}.sha256"
    destination.mkdir(parents=True, exist_ok=True)
    _run(
        [
            "gh",
            "release",
            "download",
            tag,
            "--repo",
            repository,
            "--dir",
            str(destination),
            "--pattern",
            asset,
            "--pattern",
            checksum,
            "--clobber",
        ]
    )
    package = destination / asset
    checksum_path = destination / checksum
    try:
        expected, named_asset = (
            checksum_path.read_text(encoding="utf-8").strip().split()
        )
    except (OSError, ValueError) as error:
        raise InstallFailure(f"invalid checksum asset: {checksum_path}") from error
    if named_asset != asset or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise InstallFailure(f"invalid checksum record: {checksum_path}")
    actual = _digest(package)
    if not hmac.compare_digest(actual, expected):
        raise InstallFailure(f"checksum mismatch for {asset}")
    _run(["gh", "attestation", "verify", str(package), "--repo", repository])
    return package, tag


def _load_packaged_manifest(payload: Path, tool: str, platform: str) -> dict[str, Any]:
    path = payload / "tool.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InstallFailure(f"invalid packaged manifest: {error}") from error
    errors = validate_manifest(Path(tool) / "tool.json", data)
    if errors:
        raise ManifestError(errors)
    if data["id"] != tool:
        raise InstallFailure(f"package contains {data['id']}, expected {tool}")
    if platform not in data["platforms"]:
        raise InstallFailure(f"{tool} package does not support {platform}")
    return data


def _expand_target(value: str, home: Path) -> Path:
    if not value.startswith("~/"):
        raise InstallFailure(f"install target is not home-relative: {value}")
    return home / value[2:]


def _render(value: str, variables: dict[str, str]) -> str:
    try:
        return value.format_map(variables)
    except KeyError as error:
        raise InstallFailure(f"unknown install placeholder: {error.args[0]}") from error


def _capture(target: Path, transaction: Path, index: int) -> _Backup:
    if not target.exists() and not target.is_symlink():
        return _Backup(target, None)
    transaction.mkdir(parents=True, exist_ok=True)
    saved = transaction / f"{index:03d}-{target.name}"
    os.replace(target, saved)
    return _Backup(target, saved)


def _restore(backups: list[_Backup]) -> None:
    for backup in reversed(backups):
        target = backup.target
        if target.exists() or target.is_symlink():
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
        if backup.saved is not None and backup.saved.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(backup.saved, target)


def _install_links(
    manifest: dict[str, Any],
    home: Path,
    current: Path,
    transaction: Path,
    backups: list[_Backup],
) -> None:
    for link in manifest["install"]["links"]:
        target = _expand_target(link["target"], home)
        backups.append(_capture(target, transaction, len(backups)))
        payload = current / link["payload"]
        relative = os.path.relpath(payload, target.parent)
        _atomic_symlink(relative, target)


def _install_services(
    manifest: dict[str, Any],
    platform: str,
    home: Path,
    current: Path,
    transaction: Path,
    backups: list[_Backup],
) -> list[dict[str, str]]:
    services = manifest["install"]["services"].get(platform, [])
    for service in services:
        target = _expand_target(service["target"], home)
        backups.append(_capture(target, transaction, len(backups)))
        template = current / service["template"]
        render_service(template, target, home=home, current=current)
    return services


def _reload_services(services: list[dict[str, str]], platform: str, home: Path) -> None:
    if platform == "macos":
        domain = f"gui/{os.getuid()}"
        for service in services:
            target = _expand_target(service["target"], home)
            subprocess.run(
                ["launchctl", "bootout", domain, str(target)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            _run(["launchctl", "bootstrap", domain, str(target)])
        return
    _run(["systemctl", "--user", "daemon-reload"])
    for service in services:
        _run(["systemctl", "--user", "enable", "--now", service["id"]])


def _health(manifest: dict[str, Any], platform: str, home: Path, current: Path) -> None:
    variables = {"home": str(home), "current": str(current)}
    environment = os.environ.copy()
    environment["HOME"] = str(home)
    environment["HUMAN_TOOLS_CURRENT"] = str(current)
    for command in manifest["install"]["health"][platform]:
        argv = [_render(part, variables) for part in command["run"]]
        cwd_value = _render(command.get("cwd", "."), variables)
        cwd = Path(cwd_value)
        if not cwd.is_absolute():
            cwd = current / cwd
        command_env = environment.copy()
        command_env.update(
            {
                key: _render(value, variables)
                for key, value in command.get("env", {}).items()
            }
        )
        _run(argv, cwd=cwd, env=command_env)


def _read_state(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"schemaVersion": 1, "active": None, "previous": None, "history": []}
    except json.JSONDecodeError as error:
        raise InstallFailure(f"corrupt install state: {path}") from error
    if not isinstance(data, dict) or data.get("schemaVersion") != 1:
        raise InstallFailure(f"unsupported install state: {path}")
    return data


def installation_status(
    tool: str,
    *,
    home: Path | None = None,
    state_root: Path | None = None,
) -> dict[str, Any]:
    selected_home = (home or Path.home()).resolve()
    root = (state_root or selected_home / ".local/share/human-plugins/tools") / tool
    state = _read_state(root / "state.json")
    state["tool"] = tool
    state["current"] = (
        str((root / "current").resolve()) if (root / "current").exists() else None
    )
    return state


def install_package(
    package: Path,
    *,
    tool: str,
    release: str,
    platform: str | None = None,
    home: Path | None = None,
    state_root: Path | None = None,
    activate_services: bool = True,
) -> Installed:
    selected_platform = platform or _platform()
    selected_home = (home or Path.home()).resolve()
    if not RELEASE_NAME.fullmatch(release):
        raise InstallFailure(f"unsafe release name: {release}")
    digest = _digest(package)
    tool_root = (
        state_root or selected_home / ".local/share/human-plugins/tools"
    ) / tool
    releases = tool_root / "releases"
    state_path = tool_root / "state.json"
    current = tool_root / "current"
    release_id = f"{release}-{digest[:12]}"
    release_path = releases / release_id
    releases.mkdir(parents=True, exist_ok=True)

    if not release_path.exists():
        staging = tool_root / f".staging-{uuid.uuid4().hex}"
        staging.mkdir(parents=True)
        try:
            extract(package, staging)
            _load_packaged_manifest(staging, tool, selected_platform)
            (staging / ".digest").write_text(f"{digest}\n", encoding="utf-8")
            os.replace(staging, release_path)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    elif (release_path / ".digest").read_text(encoding="utf-8").strip() != digest:
        raise InstallFailure(f"release directory digest mismatch: {release_path}")

    manifest = _load_packaged_manifest(release_path, tool, selected_platform)
    state = _read_state(state_path)
    previous_id = state.get("active")
    previous_target = os.readlink(current) if current.is_symlink() else None
    transaction = tool_root / f".transaction-{uuid.uuid4().hex}"
    backups: list[_Backup] = []
    services: list[dict[str, str]] = []
    try:
        _atomic_symlink(str(Path("releases") / release_id), current)
        _install_links(manifest, selected_home, current, transaction, backups)
        services = _install_services(
            manifest,
            selected_platform,
            selected_home,
            current,
            transaction,
            backups,
        )
        if activate_services:
            _reload_services(services, selected_platform, selected_home)
        _health(manifest, selected_platform, selected_home, current)
    except Exception as error:
        _restore(backups)
        if previous_target is None:
            if current.exists() or current.is_symlink():
                current.unlink()
        else:
            _atomic_symlink(previous_target, current)
        if activate_services and services:
            try:
                _reload_services(services, selected_platform, selected_home)
            except InstallFailure as reload_error:
                raise InstallFailure(
                    f"installation failed ({error}); rollback service reload failed ({reload_error})"
                ) from error
        raise InstallFailure(f"installation rolled back: {error}") from error

    if transaction.exists():
        backup_root = (
            tool_root
            / "backups"
            / f"{int(time.time())}-{release_id}-{uuid.uuid4().hex[:8]}"
        )
        backup_root.parent.mkdir(parents=True, exist_ok=True)
        os.replace(transaction, backup_root)
    history = [
        release_id,
        *[item for item in state.get("history", []) if item != release_id],
    ]
    next_state = {
        "schemaVersion": 1,
        "active": release_id,
        "previous": previous_id if previous_id != release_id else state.get("previous"),
        "history": history,
        "digest": digest,
        "release": release,
        "platform": selected_platform,
    }
    _atomic_text(state_path, json.dumps(next_state, indent=2, sort_keys=True) + "\n")
    return Installed(tool, release_id, digest, release_path, previous_id)


def rollback(
    manifest: Manifest,
    *,
    platform: str | None = None,
    home: Path | None = None,
    state_root: Path | None = None,
    activate_services: bool = True,
) -> Installed:
    selected_platform = platform or _platform()
    selected_home = (home or Path.home()).resolve()
    tool_root = (
        state_root or selected_home / ".local/share/human-plugins/tools"
    ) / manifest.id
    state_path = tool_root / "state.json"
    state = _read_state(state_path)
    target_id = state.get("previous")
    active_id = state.get("active")
    if not target_id or not active_id:
        raise InstallFailure(f"{manifest.id} has no rollback release")
    target = tool_root / "releases" / target_id
    if not target.is_dir():
        raise InstallFailure(f"rollback release is missing: {target}")
    packaged = _load_packaged_manifest(target, manifest.id, selected_platform)
    current = tool_root / "current"
    transaction = tool_root / f".rollback-{uuid.uuid4().hex}"
    backups: list[_Backup] = []
    services: list[dict[str, str]] = []
    old_target = os.readlink(current) if current.is_symlink() else None
    try:
        _atomic_symlink(str(Path("releases") / target_id), current)
        _install_links(packaged, selected_home, current, transaction, backups)
        services = _install_services(
            packaged,
            selected_platform,
            selected_home,
            current,
            transaction,
            backups,
        )
        if activate_services:
            _reload_services(services, selected_platform, selected_home)
        _health(packaged, selected_platform, selected_home, current)
    except Exception as error:
        _restore(backups)
        if old_target is not None:
            _atomic_symlink(old_target, current)
        raise InstallFailure(
            f"rollback failed; active release preserved: {error}"
        ) from error
    if transaction.exists():
        shutil.rmtree(transaction)
    state["active"] = target_id
    state["previous"] = active_id
    state["history"] = [
        target_id,
        *[item for item in state.get("history", []) if item != target_id],
    ]
    state["digest"] = (target / ".digest").read_text(encoding="utf-8").strip()
    _atomic_text(state_path, json.dumps(state, indent=2, sort_keys=True) + "\n")
    return Installed(manifest.id, target_id, state["digest"], target, active_id)


def exercise_lifecycle(
    manifest: Manifest,
    platform: str,
    package: Path,
    artifacts: Path,
) -> None:
    digest = _digest(package)
    with tempfile.TemporaryDirectory(
        prefix=f"{manifest.id}-lifecycle-",
        dir=artifacts,
    ) as temporary:
        root = Path(temporary)
        home = root / "home"
        state = root / "state"
        home.mkdir()
        first = install_package(
            package,
            tool=manifest.id,
            release="candidate-a",
            platform=platform,
            home=home,
            state_root=state,
            activate_services=False,
        )
        second = install_package(
            package,
            tool=manifest.id,
            release="candidate-b",
            platform=platform,
            home=home,
            state_root=state,
            activate_services=False,
        )
        restored = rollback(
            manifest,
            platform=platform,
            home=home,
            state_root=state,
            activate_services=False,
        )
        if first.digest != digest or second.previous != first.release:
            raise InstallFailure(f"{manifest.id}: deployment history is inconsistent")
        if restored.release != first.release:
            raise InstallFailure(
                f"{manifest.id}: rollback did not restore the prior release"
            )
