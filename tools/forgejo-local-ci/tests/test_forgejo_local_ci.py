from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from forgejo_local_ci import Failure, validate_compose


class ComposeTests(unittest.TestCase):
    def test_canonical_compose_is_immutable(self) -> None:
        compose = Path(__file__).parents[1] / "share" / "compose.yaml"
        validate_compose(compose)

    def test_floating_image_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            compose = Path(temporary) / "compose.yaml"
            compose.write_text(
                "services:\n"
                "  a:\n"
                "    image: example/a:latest\n"
                "  b:\n"
                "    image: example/b:latest\n"
                "  c:\n"
                "    image: example/c:latest\n"
                "${FORGEJO_LOCAL_STATE}\n"
                "privileged: true\n",
                encoding="utf-8",
            )
            with self.assertRaises(Failure):
                validate_compose(compose)


if __name__ == "__main__":
    unittest.main()
