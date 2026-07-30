from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from qyl_discord_sync import Failure, Source, document, parse_config


def config(path: str = "docs") -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "sources": [
            {
                "key": "docs",
                "channel_id": "123456789",
                "repo": "example/project",
                "branch": "main",
                "path": path,
                "filename": "docs.yaml",
            }
        ],
    }


class ConfigTests(unittest.TestCase):
    def test_valid_config(self) -> None:
        sources = parse_config(config())
        self.assertEqual(sources[0].repo, "example/project")

    def test_private_legacy_fields_are_rejected(self) -> None:
        payload = config()
        payload["guild_id"] = "123"
        with self.assertRaises(Failure):
            parse_config(payload)

    def test_escaping_path_is_rejected(self) -> None:
        with self.assertRaises(Failure):
            parse_config(config("../secrets"))

    def test_document_is_deterministic_yaml_compatible_json(self) -> None:
        source = Source(
            "docs",
            "123456789",
            "example/project",
            "main",
            "docs",
            "docs.yaml",
        )
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "b.md").write_text("second", encoding="utf-8")
            (directory / "a.md").write_text("first", encoding="utf-8")
            first = document(source, "a" * 40, directory)
            second = document(source, "a" * 40, directory)
            self.assertEqual(first, second)
            files = json.loads(first)["files"]
            self.assertEqual([item["path"] for item in files], ["a.md", "b.md"])


if __name__ == "__main__":
    unittest.main()
