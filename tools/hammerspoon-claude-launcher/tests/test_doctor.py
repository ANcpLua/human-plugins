from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from doctor import validate


class DoctorTests(unittest.TestCase):
    def test_canonical_config(self) -> None:
        validate(Path(__file__).parents[1] / "share" / "init.lua")

    def test_dangerous_permission_bypass_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "init.lua"
            path.write_text("--dangerously-skip-permissions", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate(path)


if __name__ == "__main__":
    unittest.main()
