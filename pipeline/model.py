from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

TOOL_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
PLATFORMS = {"linux", "macos"}
STAGES = ("check", "build", "test", "smoke")
KINDS = {"app", "automation", "cli", "daemon", "sandbox"}


class ManifestError(ValueError):
    def __init__(self, errors: list[str]) -> None:
        super().__init__("\n".join(errors))
        self.errors = errors


@dataclass(frozen=True)
class Manifest:
    path: Path
    data: dict[str, Any]

    @property
    def directory(self) -> Path:
        return self.path.parent

    @property
    def id(self) -> str:
        return str(self.data["id"])

    @property
    def platforms(self) -> tuple[str, ...]:
        return tuple(self.data["platforms"])

    def platform(self, name: str) -> dict[str, Any]:
        return self.data["pipeline"][name]


def _relative_path(value: object, field: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not value:
        errors.append(f"{field} must be a non-empty relative path")
        return
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        errors.append(f"{field} escapes the tool: {value}")


def _command(
    value: object,
    field: str,
    errors: list[str],
) -> None:
    if not isinstance(value, dict):
        errors.append(f"{field} must be an object")
        return
    if set(value) - {"name", "run", "cwd", "env"}:
        errors.append(
            f"{field} has unknown keys: {sorted(set(value) - {'name', 'run', 'cwd', 'env'})}"
        )
    if not isinstance(value.get("name"), str) or not value["name"]:
        errors.append(f"{field}.name must be a non-empty string")
    run = value.get("run")
    if (
        not isinstance(run, list)
        or not run
        or not all(isinstance(part, str) and part for part in run)
    ):
        errors.append(f"{field}.run must be a non-empty argv array")
    cwd = value.get("cwd", ".")
    _relative_path(cwd, f"{field}.cwd", errors)
    env = value.get("env", {})
    if not isinstance(env, dict) or not all(
        isinstance(key, str) and key and isinstance(item, str)
        for key, item in env.items()
    ):
        errors.append(f"{field}.env must map non-empty strings to strings")


def _packaged(path: str, destinations: set[str]) -> bool:
    candidate = Path(path)
    return any(
        candidate == Path(destination) or Path(destination) in candidate.parents
        for destination in destinations
    )


def validate_manifest(path: Path, data: object) -> list[str]:
    errors: list[str] = []
    prefix = path.parent.name
    if not isinstance(data, dict):
        return [f"{path}: root must be an object"]

    required = {
        "$schema",
        "schemaVersion",
        "id",
        "displayName",
        "summary",
        "status",
        "kind",
        "license",
        "platforms",
        "source",
        "pipeline",
        "package",
        "install",
    }
    allowed = required
    missing = required - set(data)
    unknown = set(data) - allowed
    if missing:
        errors.append(f"{prefix}: missing keys: {sorted(missing)}")
    if unknown:
        errors.append(f"{prefix}: unknown keys: {sorted(unknown)}")

    tool_id = data.get("id")
    if not isinstance(tool_id, str) or not TOOL_ID.fullmatch(tool_id):
        errors.append(f"{prefix}: id must be lower kebab-case")
    elif tool_id != prefix:
        errors.append(f"{prefix}: id must match directory name")
    if data.get("schemaVersion") != 1:
        errors.append(f"{prefix}: schemaVersion must be 1")
    if data.get("$schema") != "../../pipeline/tool.schema.json":
        errors.append(
            f"{prefix}: $schema must reference ../../pipeline/tool.schema.json"
        )
    for field in ("displayName", "summary"):
        if not isinstance(data.get(field), str) or not data[field].strip():
            errors.append(f"{prefix}: {field} must be a non-empty string")
    if data.get("status") != "active":
        errors.append(f"{prefix}: only active tools belong under tools/")
    if data.get("kind") not in KINDS:
        errors.append(f"{prefix}: unknown kind {data.get('kind')!r}")
    if data.get("license") != "MIT":
        errors.append(f"{prefix}: license must be MIT")

    platforms = data.get("platforms")
    if (
        not isinstance(platforms, list)
        or not platforms
        or not all(platform in PLATFORMS for platform in platforms)
        or len(platforms) != len(set(platforms))
    ):
        errors.append(
            f"{prefix}: platforms must be a unique non-empty macos/linux array"
        )
        platforms = []

    source = data.get("source")
    if not isinstance(source, dict):
        errors.append(f"{prefix}: source must be an object")
    else:
        if source.get("repository") != "ANcpLua/human-plugins":
            errors.append(f"{prefix}: source.repository must be ANcpLua/human-plugins")
        if source.get("path") != f"tools/{prefix}":
            errors.append(f"{prefix}: source.path must be tools/{prefix}")
        if set(source) - {"repository", "path", "migratedFrom", "migratedCommit"}:
            errors.append(f"{prefix}: source has unknown keys")
        migrated_from = source.get("migratedFrom")
        migrated_commit = source.get("migratedCommit")
        if (migrated_from is None) != (migrated_commit is None):
            errors.append(
                f"{prefix}: migratedFrom and migratedCommit must appear together"
            )
        if migrated_commit is not None and (
            not isinstance(migrated_commit, str)
            or not re.fullmatch(r"[0-9a-f]{40}", migrated_commit)
        ):
            errors.append(f"{prefix}: migratedCommit must be a full Git SHA")

    pipeline = data.get("pipeline")
    if not isinstance(pipeline, dict):
        errors.append(f"{prefix}: pipeline must be an object")
        pipeline = {}
    if set(pipeline) != set(platforms):
        errors.append(f"{prefix}: pipeline keys must exactly match platforms")
    for platform in platforms:
        spec = pipeline.get(platform)
        field = f"{prefix}.pipeline.{platform}"
        if not isinstance(spec, dict):
            errors.append(f"{field} must be an object")
            continue
        if set(spec) != {"runner", "stages"}:
            errors.append(f"{field} must contain only runner and stages")
        runner = spec.get("runner")
        expected_prefix = "macos-" if platform == "macos" else "ubuntu-"
        if not isinstance(runner, str) or not runner.startswith(expected_prefix):
            errors.append(f"{field}.runner must start with {expected_prefix}")
        stages = spec.get("stages")
        if not isinstance(stages, dict):
            errors.append(f"{field}.stages must be an object")
            continue
        if set(stages) != set(STAGES):
            errors.append(f"{field}.stages must contain exactly {list(STAGES)}")
        for stage in STAGES:
            commands = stages.get(stage)
            if not isinstance(commands, list) or not commands:
                errors.append(
                    f"{field}.stages.{stage} must contain at least one command"
                )
                continue
            names: set[str] = set()
            for index, command in enumerate(commands):
                _command(command, f"{field}.stages.{stage}[{index}]", errors)
                if isinstance(command, dict) and isinstance(command.get("name"), str):
                    if command["name"] in names:
                        errors.append(
                            f"{field}.stages.{stage}: duplicate command name {command['name']}"
                        )
                    names.add(command["name"])

    destinations: set[str] = set()
    package = data.get("package")
    if not isinstance(package, dict) or set(package) != {"files"}:
        errors.append(f"{prefix}: package must contain only files")
    else:
        files = package.get("files")
        if not isinstance(files, list) or not files:
            errors.append(f"{prefix}: package.files must not be empty")
        else:
            for index, item in enumerate(files):
                field = f"{prefix}.package.files[{index}]"
                if not isinstance(item, dict) or set(item) != {"source", "destination"}:
                    errors.append(f"{field} must contain source and destination")
                    continue
                _relative_path(item.get("destination"), f"{field}.destination", errors)
                source_value = item.get("source")
                if not isinstance(source_value, str) or not source_value:
                    errors.append(f"{field}.source must be a non-empty path template")
                destination = item.get("destination")
                if isinstance(destination, str):
                    if destination in destinations:
                        errors.append(f"{field}.destination is duplicated")
                    destinations.add(destination)

    install = data.get("install")
    if not isinstance(install, dict) or set(install) != {"links", "services", "health"}:
        errors.append(
            f"{prefix}: install must contain only links, services, and health"
        )
    else:
        links = install.get("links")
        if not isinstance(links, list) or not links:
            errors.append(f"{prefix}: install.links must not be empty")
        else:
            targets: set[str] = set()
            for index, link in enumerate(links):
                field = f"{prefix}.install.links[{index}]"
                if not isinstance(link, dict) or set(link) != {"payload", "target"}:
                    errors.append(f"{field} must contain payload and target")
                    continue
                _relative_path(link.get("payload"), f"{field}.payload", errors)
                if isinstance(link.get("payload"), str) and not _packaged(
                    link["payload"], destinations
                ):
                    errors.append(f"{field}.payload is not produced by package.files")
                target = link.get("target")
                if not isinstance(target, str) or not target.startswith(
                    ("~/.local/bin/", "~/Applications/")
                ):
                    errors.append(
                        f"{field}.target must live under ~/.local/bin or ~/Applications"
                    )
                elif target in targets:
                    errors.append(f"{field}.target is duplicated")
                else:
                    targets.add(target)
        services = install.get("services")
        if not isinstance(services, dict) or set(services) - PLATFORMS:
            errors.append(f"{prefix}: install.services keys must be macos/linux")
        elif not set(services).issubset(set(platforms)):
            errors.append(f"{prefix}: services cannot target an unsupported platform")
        else:
            for platform, entries in services.items():
                if not isinstance(entries, list):
                    errors.append(
                        f"{prefix}.install.services.{platform} must be an array"
                    )
                    continue
                for index, service in enumerate(entries):
                    field = f"{prefix}.install.services.{platform}[{index}]"
                    required_service = {"template", "target", "id", "activate"}
                    if (
                        not isinstance(service, dict)
                        or set(service) != required_service
                    ):
                        errors.append(
                            f"{field} must contain template, target, id, and activate"
                        )
                        continue
                    _relative_path(service.get("template"), f"{field}.template", errors)
                    if isinstance(service.get("template"), str) and not _packaged(
                        service["template"], destinations
                    ):
                        errors.append(
                            f"{field}.template is not produced by package.files"
                        )
                    if not isinstance(service.get("target"), str) or not service[
                        "target"
                    ].startswith(
                        ("~/Library/LaunchAgents/", "~/.config/systemd/user/")
                    ):
                        errors.append(
                            f"{field}.target is outside the supported service directories"
                        )
                    if not isinstance(service.get("id"), str) or not service["id"]:
                        errors.append(
                            f"{field}.id must be a non-empty service identifier"
                        )
                    if not isinstance(service.get("activate"), bool):
                        errors.append(f"{field}.activate must be a boolean")
        health = install.get("health")
        if not isinstance(health, dict) or set(health) != set(platforms):
            errors.append(f"{prefix}: install.health keys must exactly match platforms")
        else:
            for platform in platforms:
                commands = health.get(platform)
                field = f"{prefix}.install.health.{platform}"
                if not isinstance(commands, list) or not commands:
                    errors.append(f"{field} must contain at least one command")
                    continue
                for index, command in enumerate(commands):
                    _command(command, f"{field}[{index}]", errors)
    return errors


def load_manifests(root: Path) -> list[Manifest]:
    manifests: list[Manifest] = []
    errors: list[str] = []
    tools = root / "tools"
    for directory in sorted(path for path in tools.iterdir() if path.is_dir()):
        if directory.name in {"legacy", "stale"}:
            errors.append(f"forbidden source graveyard: {directory.relative_to(root)}")
            continue
        path = directory / "tool.json"
        if not path.is_file():
            errors.append(f"{directory.name}: missing tool.json")
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"{path.relative_to(root)}: {error}")
            continue
        errors.extend(validate_manifest(path, data))
        if isinstance(data, dict):
            manifests.append(Manifest(path, data))
        for required in ("README.md", "CHANGELOG.md"):
            if not (directory / required).is_file():
                errors.append(f"{directory.name}: missing {required}")
        for graveyard in ("legacy", "stale"):
            if (directory / graveyard).exists():
                errors.append(
                    f"{directory.name}: delete {graveyard}/; Git history is the archive"
                )
    ids = [manifest.id for manifest in manifests if "id" in manifest.data]
    if len(ids) != len(set(ids)):
        errors.append("duplicate tool id")
    targets: dict[str, str] = {}
    service_targets: dict[str, str] = {}
    for manifest in manifests:
        install = manifest.data.get("install", {})
        for link in install.get("links", []):
            target = link.get("target")
            if isinstance(target, str):
                owner = targets.setdefault(target, manifest.id)
                if owner != manifest.id:
                    errors.append(
                        f"install target {target} is owned by both {owner} and {manifest.id}"
                    )
        for services in install.get("services", {}).values():
            for service in services:
                target = service.get("target")
                if isinstance(target, str):
                    owner = service_targets.setdefault(target, manifest.id)
                    if owner != manifest.id:
                        errors.append(
                            f"service target {target} is owned by both {owner} and {manifest.id}"
                        )
    if errors:
        raise ManifestError(errors)
    return manifests


def catalog(manifests: list[Manifest]) -> dict[str, Any]:
    return {
        "schemaVersion": 2,
        "source": "tools/*/tool.json",
        "repository": "https://github.com/ANcpLua/human-plugins",
        "tools": [
            {
                "id": manifest.id,
                "displayName": manifest.data["displayName"],
                "summary": manifest.data["summary"],
                "kind": manifest.data["kind"],
                "platforms": manifest.platforms,
                "catalogEntry": (
                    "https://github.com/ANcpLua/human-plugins/tree/main/"
                    f"tools/{manifest.id}"
                ),
            }
            for manifest in manifests
        ],
    }


def catalog_text(manifests: list[Manifest]) -> str:
    return json.dumps(catalog(manifests), indent=2, ensure_ascii=False) + "\n"
