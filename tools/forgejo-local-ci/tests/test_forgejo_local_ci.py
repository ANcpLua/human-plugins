from __future__ import annotations

import http.client
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from forgejo_local_ci import (
    Failure,
    Runtime,
    api,
    prepare_state,
    remote_file_exists,
    validate_compose,
)


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

    def test_runner_secret_is_exactly_forty_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            selected = Runtime(
                state=root,
                compose=root / "compose.yaml",
                url="http://localhost:3000",
                admin="localadmin",
                email="localadmin@local.invalid",
                repository="ci-smoke",
                runner="local-ci-runner",
            )
            prepare_state(selected)
            secret = (selected.secrets / "runner-secret").read_bytes()
            self.assertEqual(len(secret), 40)
            self.assertNotIn(b"\n", secret)

    def test_transport_disconnect_is_a_retryable_failure(self) -> None:
        selected = Runtime(
            state=Path("/tmp/unused"),
            compose=Path("/tmp/unused.yaml"),
            url="http://localhost:3000",
            admin="localadmin",
            email="localadmin@local.invalid",
            repository="ci-smoke",
            runner="local-ci-runner",
        )
        with (
            patch(
                "forgejo_local_ci.urllib.request.urlopen",
                side_effect=http.client.RemoteDisconnected(),
            ),
            self.assertRaises(Failure),
        ):
            api(selected, "GET", "/api/healthz", authenticated=False)

    def test_null_contents_response_is_not_a_file(self) -> None:
        selected = Runtime(
            state=Path("/tmp/unused"),
            compose=Path("/tmp/unused.yaml"),
            url="http://localhost:3000",
            admin="localadmin",
            email="localadmin@local.invalid",
            repository="ci-smoke",
            runner="local-ci-runner",
        )
        with patch("forgejo_local_ci.api", return_value=None):
            self.assertFalse(remote_file_exists(selected, "/contents/file"))
        with patch("forgejo_local_ci.api", return_value={"sha": "abc"}):
            self.assertTrue(remote_file_exists(selected, "/contents/file"))


if __name__ == "__main__":
    unittest.main()
