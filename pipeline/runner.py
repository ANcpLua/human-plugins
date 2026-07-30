from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from .install import exercise_lifecycle
from .model import Manifest
from .package import package_tool


class PipelineFailure(RuntimeError):
    pass


def _event(**values: object) -> None:
    print(json.dumps(values, ensure_ascii=False, sort_keys=True), flush=True)


def _expand(value: str, variables: dict[str, str]) -> str:
    try:
        return value.format_map(variables)
    except KeyError as error:
        raise PipelineFailure(
            f"unknown command placeholder: {error.args[0]}"
        ) from error


def run_stage(
    manifest: Manifest,
    platform: str,
    stage: str,
    artifacts_dir: Path,
    package: Path | None = None,
) -> None:
    if platform not in manifest.platforms:
        raise PipelineFailure(f"{manifest.id} does not support {platform}")
    build_dir = artifacts_dir / "build" / manifest.id / platform
    log_dir = artifacts_dir / "logs" / manifest.id / platform
    build_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)
    variables = {
        "root": str(manifest.directory.parent.parent),
        "tool": str(manifest.directory),
        "build": str(build_dir),
        "artifacts": str(artifacts_dir),
        "platform": platform,
        "package": str(
            package or artifacts_dir / "packages" / f"{manifest.id}-{platform}.tar.gz"
        ),
    }
    commands: list[dict[str, Any]] = manifest.platform(platform)["stages"][stage]
    for index, command in enumerate(commands, start=1):
        argv = [_expand(part, variables) for part in command["run"]]
        cwd = manifest.directory / _expand(command.get("cwd", "."), variables)
        environment = os.environ.copy()
        environment.update(
            {
                "HUMAN_TOOLS_ROOT": variables["root"],
                "HUMAN_TOOLS_TOOL": variables["tool"],
                "HUMAN_TOOLS_BUILD": variables["build"],
                "HUMAN_TOOLS_ARTIFACTS": variables["artifacts"],
                "HUMAN_TOOLS_PLATFORM": platform,
            }
        )
        environment.update(
            {
                key: _expand(value, variables)
                for key, value in command.get("env", {}).items()
            }
        )
        log_path = log_dir / f"{stage}-{index:02d}-{command['name']}.log"
        _event(
            event="command_started",
            tool=manifest.id,
            platform=platform,
            stage=stage,
            command=command["name"],
            argv=argv,
            cwd=str(cwd),
            log=str(log_path),
        )
        started = time.monotonic()
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(
                argv,
                cwd=cwd,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            assert process.stdout is not None
            for line in process.stdout:
                sys.stdout.write(line)
                log.write(line)
            return_code = process.wait()
        elapsed = round(time.monotonic() - started, 3)
        _event(
            event="command_finished",
            tool=manifest.id,
            platform=platform,
            stage=stage,
            command=command["name"],
            elapsedSeconds=elapsed,
            exitCode=return_code,
            log=str(log_path),
        )
        if return_code != 0:
            raise PipelineFailure(
                f"{manifest.id}/{platform}/{stage}/{command['name']} exited {return_code}"
            )


def verify_tool(
    manifest: Manifest,
    platform: str,
    artifacts_dir: Path,
) -> Path:
    build_dir = artifacts_dir / "build" / manifest.id / platform
    if build_dir.exists():
        shutil.rmtree(build_dir)
    for stage in ("check", "build", "test"):
        run_stage(manifest, platform, stage, artifacts_dir)
    package = package_tool(manifest, platform, build_dir, artifacts_dir)
    _event(
        event="package_created",
        tool=manifest.id,
        platform=platform,
        path=str(package),
    )
    run_stage(manifest, platform, "smoke", artifacts_dir, package)
    _event(event="lifecycle_started", tool=manifest.id, platform=platform)
    exercise_lifecycle(manifest, platform, package, artifacts_dir)
    _event(event="lifecycle_verified", tool=manifest.id, platform=platform)
    _event(event="tool_verified", tool=manifest.id, platform=platform)
    return package
