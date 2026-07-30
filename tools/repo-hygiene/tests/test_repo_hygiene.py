from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from repo_hygiene import is_artifact, scan


def commit(repository: Path, files: dict[str, str]) -> None:
    repository.mkdir(parents=True)
    subprocess.run(["git", "-C", str(repository), "init", "-q"], check=True)
    for name, content in files.items():
        path = repository / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    subprocess.run(["git", "-C", str(repository), "add", "-f", "-A"], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(repository),
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "-qm",
            "fixture",
        ],
        check=True,
    )


class RepoHygieneTests(unittest.TestCase):
    def test_patterns_distinguish_artifacts_from_source(self) -> None:
        self.assertTrue(is_artifact("src/bin/Release/net10.0/App.dll"))
        self.assertTrue(is_artifact("target/debug/app"))
        self.assertFalse(is_artifact("bin/repo-hygiene"))
        self.assertFalse(is_artifact("wwwroot/lib/bootstrap/dist/b.css"))

    def test_scan_reports_only_dirty_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            commit(
                root / "dirty",
                {
                    "src/bin/Release/net10.0/App.dll": "x",
                    "wwwroot/lib/bootstrap/dist/b.css": "x",
                },
            )
            commit(root / "clean", {"src/Program.cs": "x"})
            findings, count = scan([root], 3)
            self.assertEqual(count, 2)
            self.assertEqual(len(findings), 1)
            self.assertEqual(
                findings[0].files,
                ("src/bin/Release/net10.0/App.dll",),
            )


if __name__ == "__main__":
    unittest.main()
