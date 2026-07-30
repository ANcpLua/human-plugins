from __future__ import annotations

import argparse
import json
import os
import platform as host_platform
import sys
import tempfile
from pathlib import Path

from .install import (
    InstallFailure,
    download_verified,
    install_package,
    installation_status,
    rollback,
)
from .links import check as check_links
from .model import Manifest, ManifestError, catalog_text, load_manifests
from .release import write_index
from .runner import PipelineFailure, run_stage, verify_tool

ROOT = Path(__file__).resolve().parent.parent


def _platform() -> str:
    name = host_platform.system()
    if name == "Darwin":
        return "macos"
    if name == "Linux":
        return "linux"
    raise PipelineFailure(f"unsupported host platform: {name}")


def _manifest(manifests: list[Manifest], tool_id: str) -> Manifest:
    for manifest in manifests:
        if manifest.id == tool_id:
            return manifest
    raise PipelineFailure(f"unknown tool: {tool_id}")


def _artifacts(value: str | None) -> Path:
    path = Path(value or os.environ.get("HUMAN_TOOLS_ARTIFACTS", ROOT / ".artifacts"))
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="toolctl")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate")
    commands.add_parser("list")
    catalog = commands.add_parser("catalog")
    catalog.add_argument("--write", action="store_true")
    links = commands.add_parser("links")
    links.add_argument("--external", action="store_true")
    matrix = commands.add_parser("matrix")
    matrix.add_argument("--json", action="store_true")
    run = commands.add_parser("run")
    run.add_argument("stage", choices=("check", "build", "test", "smoke"))
    run.add_argument("--tool", required=True)
    run.add_argument("--platform", choices=("macos", "linux"))
    run.add_argument("--artifacts")
    verify = commands.add_parser("verify")
    verify.add_argument("--tool", required=True)
    verify.add_argument("--platform", choices=("macos", "linux"))
    verify.add_argument("--artifacts")
    install = commands.add_parser("install")
    install.add_argument("--tool", required=True)
    install.add_argument("--package", required=True, type=Path)
    install.add_argument("--release", default="local")
    install.add_argument("--platform", choices=("macos", "linux"))
    install.add_argument("--home", type=Path)
    install.add_argument("--state-root", type=Path)
    install.add_argument("--no-services", action="store_true")
    update = commands.add_parser("update")
    update.add_argument("--tool")
    update.add_argument("--release", default="latest")
    update.add_argument("--repository", default="ANcpLua/human-plugins")
    update.add_argument("--platform", choices=("macos", "linux"))
    update.add_argument("--no-services", action="store_true")
    rollback_parser = commands.add_parser("rollback")
    rollback_parser.add_argument("--tool", required=True)
    rollback_parser.add_argument("--platform", choices=("macos", "linux"))
    rollback_parser.add_argument("--no-services", action="store_true")
    status = commands.add_parser("status")
    status.add_argument("--tool")
    release_index = commands.add_parser("release-index")
    release_index.add_argument("--directory", required=True, type=Path)
    release_index.add_argument("--commit", required=True)
    release_index.add_argument("--tag", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        manifests = load_manifests(ROOT)
        if args.command == "validate":
            expected = catalog_text(manifests)
            actual = (ROOT / "catalog.json").read_text(encoding="utf-8")
            if actual != expected:
                raise PipelineFailure(
                    "catalog.json is stale; run ./toolctl catalog --write"
                )
            failures, _ = check_links(ROOT, external=False)
            if failures:
                raise PipelineFailure("\n".join(failures))
            print(f"manifest integrity ok — {len(manifests)} tools")
            return 0
        if args.command == "list":
            for manifest in manifests:
                print(
                    f"{manifest.id}\t{','.join(manifest.platforms)}\t"
                    f"{manifest.data['kind']}\t{manifest.data['summary']}"
                )
            return 0
        if args.command == "catalog":
            rendered = catalog_text(manifests)
            if args.write:
                (ROOT / "catalog.json").write_text(rendered, encoding="utf-8")
                print("catalog.json updated")
                return 0
            print(rendered, end="")
            return 0
        if args.command == "links":
            failures, urls = check_links(ROOT, external=args.external)
            if failures:
                raise PipelineFailure("\n".join(failures))
            mode = "external" if args.external else "local"
            print(f"{mode} link integrity ok — {len(urls)} URLs")
            return 0
        if args.command == "matrix":
            include = [
                {
                    "tool": manifest.id,
                    "platform": platform,
                    "runner": manifest.platform(platform)["runner"],
                }
                for manifest in manifests
                for platform in manifest.platforms
            ]
            payload = {"include": include}
            print(
                json.dumps(payload, separators=(",", ":"))
                if args.json
                else json.dumps(payload, indent=2)
            )
            return 0
        if args.command == "release-index":
            output = write_index(
                manifests,
                args.directory,
                commit=args.commit,
                tag=args.tag,
            )
            print(output)
            return 0
        if args.command == "status":
            selected = (
                manifests if args.tool is None else [_manifest(manifests, args.tool)]
            )
            payload = [installation_status(manifest.id) for manifest in selected]
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 0
        if args.command == "update":
            platform = args.platform or _platform()
            selected = (
                [manifest for manifest in manifests if platform in manifest.platforms]
                if args.tool is None
                else [_manifest(manifests, args.tool)]
            )
            for manifest in selected:
                if platform not in manifest.platforms:
                    raise PipelineFailure(f"{manifest.id} does not support {platform}")
                with tempfile.TemporaryDirectory(
                    prefix=f"{manifest.id}-download-"
                ) as temporary:
                    package, tag = download_verified(
                        manifest.id,
                        platform,
                        repository=args.repository,
                        release=args.release,
                        destination=Path(temporary),
                    )
                    installed = install_package(
                        package,
                        tool=manifest.id,
                        release=tag,
                        platform=platform,
                        activate_services=not args.no_services,
                    )
                    print(f"{manifest.id}: active {installed.release}")
            return 0
        manifest = _manifest(manifests, args.tool)
        platform = args.platform or _platform()
        if args.command == "install":
            installed = install_package(
                args.package.resolve(),
                tool=manifest.id,
                release=args.release,
                platform=platform,
                home=args.home,
                state_root=args.state_root,
                activate_services=not args.no_services,
            )
            print(f"{manifest.id}: active {installed.release}")
            return 0
        if args.command == "rollback":
            restored = rollback(
                manifest,
                platform=platform,
                activate_services=not args.no_services,
            )
            print(f"{manifest.id}: restored {restored.release}")
            return 0
        artifacts = _artifacts(args.artifacts)
        if args.command == "run":
            run_stage(manifest, platform, args.stage, artifacts)
            return 0
        if args.command == "verify":
            verify_tool(manifest, platform, artifacts)
            return 0
        raise AssertionError(args.command)
    except (
        InstallFailure,
        ManifestError,
        PipelineFailure,
        FileNotFoundError,
        ValueError,
    ) as error:
        print(f"toolctl: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
