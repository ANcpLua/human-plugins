from __future__ import annotations

import io
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

from pipeline.install import (
    InstallFailure,
    install_package,
    installation_status,
    rollback,
)
from pipeline.model import Manifest, validate_manifest
from pipeline.package import package_digest, package_tool
from pipeline.probe import extract

PLATFORM = "macos" if __import__("platform").system() == "Darwin" else "linux"
RUNNER = "macos-15" if PLATFORM == "macos" else "ubuntu-24.04"


def manifest_data(tool: str = "demo") -> dict:
    command = {"name": "true", "run": ["/usr/bin/true"]}
    return {
        "$schema": "../../pipeline/tool.schema.json",
        "schemaVersion": 1,
        "id": tool,
        "displayName": "Demo",
        "summary": "Pipeline fixture.",
        "status": "active",
        "kind": "cli",
        "license": "MIT",
        "platforms": [PLATFORM],
        "source": {
            "repository": "ANcpLua/human-plugins",
            "path": f"tools/{tool}",
        },
        "pipeline": {
            PLATFORM: {
                "runner": RUNNER,
                "stages": {
                    "check": [command],
                    "build": [command],
                    "test": [command],
                    "smoke": [command],
                },
            }
        },
        "package": {"files": [{"source": "src/demo", "destination": "bin/demo"}]},
        "install": {
            "links": [{"payload": "bin/demo", "target": "~/.local/bin/demo"}],
            "services": {},
            "health": {
                PLATFORM: [
                    {
                        "name": "self-test",
                        "run": ["{current}/bin/demo", "--self-test"],
                    }
                ]
            },
        },
    }


def write_tool(root: Path, output: str, exit_code: int = 0) -> Manifest:
    directory = root / "tools" / "demo"
    (directory / "src").mkdir(parents=True)
    script = directory / "src" / "demo"
    script.write_text(
        "#!/bin/sh\n"
        f'if [ "${{1:-}}" = --self-test ]; then exit {exit_code}; fi\n'
        f"printf '%s\\n' '{output}'\n",
        encoding="utf-8",
    )
    script.chmod(0o755)
    data = manifest_data()
    path = directory / "tool.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return Manifest(path, data)


class ManifestTests(unittest.TestCase):
    def test_complete_manifest_is_valid(self) -> None:
        self.assertEqual(validate_manifest(Path("demo/tool.json"), manifest_data()), [])

    def test_install_payload_must_be_packaged(self) -> None:
        data = manifest_data()
        data["install"]["links"][0]["payload"] = "bin/missing"
        errors = validate_manifest(Path("demo/tool.json"), data)
        self.assertTrue(any("not produced" in error for error in errors))


class PackageTests(unittest.TestCase):
    def test_package_is_reproducible(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = write_tool(root, "v1")
            first = package_tool(manifest, PLATFORM, root / "build", root / "a")
            second = package_tool(manifest, PLATFORM, root / "build", root / "b")
            self.assertEqual(package_digest(first), package_digest(second))

    def test_extraction_rejects_parent_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "bad.tar.gz"
            with tarfile.open(archive, "w:gz") as stream:
                info = tarfile.TarInfo("../outside")
                info.size = 1
                stream.addfile(info, io.BytesIO(b"x"))
            with self.assertRaises(ValueError):
                extract(archive, root / "output")


class InstallTests(unittest.TestCase):
    def package(
        self, root: Path, name: str, output: str, exit_code: int = 0
    ) -> tuple[Manifest, Path]:
        source = root / name
        manifest = write_tool(source, output, exit_code)
        package = package_tool(
            manifest,
            PLATFORM,
            source / "build",
            source / "artifacts",
        )
        return manifest, package

    def test_failed_health_check_restores_previous_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, good = self.package(root, "good", "v1")
            _, bad = self.package(root, "bad", "v2", exit_code=23)
            home = root / "home"
            home.mkdir()
            state = root / "state"
            first = install_package(
                good,
                tool="demo",
                release="v1",
                platform=PLATFORM,
                home=home,
                state_root=state,
                activate_services=False,
            )
            with self.assertRaisesRegex(InstallFailure, "rolled back"):
                install_package(
                    bad,
                    tool="demo",
                    release="v2",
                    platform=PLATFORM,
                    home=home,
                    state_root=state,
                    activate_services=False,
                )
            current = state / "demo" / "current"
            self.assertEqual(current.resolve(), first.path.resolve())
            output = subprocess.check_output(
                [str(home / ".local/bin/demo")],
                text=True,
            ).strip()
            self.assertEqual(output, "v1")

    def test_explicit_rollback_restores_prior_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest, first_package = self.package(root, "first", "v1")
            _, second_package = self.package(root, "second", "v2")
            home = root / "home"
            home.mkdir()
            state = root / "state"
            first = install_package(
                first_package,
                tool="demo",
                release="v1",
                platform=PLATFORM,
                home=home,
                state_root=state,
                activate_services=False,
            )
            second = install_package(
                second_package,
                tool="demo",
                release="v2",
                platform=PLATFORM,
                home=home,
                state_root=state,
                activate_services=False,
            )
            restored = rollback(
                manifest,
                platform=PLATFORM,
                home=home,
                state_root=state,
                activate_services=False,
            )
            self.assertEqual(restored.release, first.release)
            output = subprocess.check_output(
                [str(home / ".local/bin/demo")],
                text=True,
            ).strip()
            self.assertEqual(output, "v1")
            status = installation_status("demo", home=home, state_root=state)
            self.assertEqual(status["active"], first.release)
            self.assertEqual(status["previous"], second.release)
            self.assertEqual(status["release"], "v1")
            self.assertEqual(status["digest"], first.digest)
            self.assertEqual(status["platform"], PLATFORM)


if __name__ == "__main__":
    unittest.main()
