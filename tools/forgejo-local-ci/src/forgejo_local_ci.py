#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import http.client
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

VERSION = "2.0.0"
NAME = re.compile(r"^[A-Za-z0-9._-]+$")
TERMINAL_STATES = {"success", "failure", "cancelled", "skipped", "timed_out"}


class Failure(RuntimeError):
    pass


@dataclass(frozen=True)
class Runtime:
    state: Path
    compose: Path
    url: str
    admin: str
    email: str
    repository: str
    runner: str

    @property
    def secrets(self) -> Path:
        return self.state / "secrets"

    @property
    def token_file(self) -> Path:
        return self.secrets / "admin-token"

    def compose_argv(self, *arguments: str) -> list[str]:
        return [
            "docker",
            "compose",
            "--project-name",
            "forgejo-local-ci",
            "--project-directory",
            str(self.state),
            "--file",
            str(self.compose),
            *arguments,
        ]

    def environment(self) -> dict[str, str]:
        environment = os.environ.copy()
        environment["FORGEJO_LOCAL_STATE"] = str(self.state)
        return environment


def run(
    arguments: list[str],
    *,
    environment: dict[str, str] | None = None,
    cwd: Path | None = None,
    capture: bool = False,
) -> str:
    process = subprocess.run(
        arguments,
        cwd=cwd,
        env=environment,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        check=False,
    )
    if process.returncode:
        detail = (process.stderr or process.stdout or "").strip()
        raise Failure(
            f"{' '.join(arguments)} exited {process.returncode}"
            + (f": {detail}" if detail else "")
        )
    return (process.stdout or "").strip()


def require(*commands: str) -> None:
    missing = [command for command in commands if shutil.which(command) is None]
    if missing:
        raise Failure(f"missing commands: {', '.join(missing)}")


def package_root() -> Path:
    return Path(__file__).resolve().parent.parent


def default_state() -> Path:
    base = Path(
        os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")
    ).expanduser()
    return base / "human-plugins" / "forgejo-local-ci"


def runtime(args: argparse.Namespace) -> Runtime:
    state = args.state.expanduser().resolve()
    compose = args.compose.expanduser().resolve()
    selected = Runtime(
        state=state,
        compose=compose,
        url=os.environ.get("FORGEJO_LOCAL_URL", "http://localhost:3000").rstrip("/"),
        admin=os.environ.get("FORGEJO_LOCAL_ADMIN_USER", "localadmin"),
        email=os.environ.get("FORGEJO_LOCAL_ADMIN_EMAIL", "localadmin@local.invalid"),
        repository=os.environ.get("FORGEJO_LOCAL_REPO", "ci-smoke"),
        runner=os.environ.get("FORGEJO_LOCAL_RUNNER_NAME", "local-ci-runner"),
    )
    for label, value in (
        ("admin user", selected.admin),
        ("repository", selected.repository),
        ("runner", selected.runner),
    ):
        if not NAME.fullmatch(value):
            raise Failure(f"invalid {label}: {value!r}")
    return selected


def write_secret(path: Path, value: str, *, newline: bool = True) -> None:
    content = value.rstrip("\r\n") + ("\n" if newline else "")
    path.write_text(content, encoding="utf-8")
    path.chmod(0o600)


def prepare_state(selected: Runtime) -> None:
    for directory in (
        selected.secrets,
        selected.state / "forgejo",
        selected.state / "runner",
    ):
        directory.mkdir(parents=True, exist_ok=True)
    selected.secrets.chmod(0o700)
    password = selected.secrets / "admin-password"
    runner_secret = selected.secrets / "runner-secret"
    if not password.exists():
        write_secret(password, secrets.token_urlsafe(30))
    if not runner_secret.exists():
        write_secret(runner_secret, secrets.token_hex(20), newline=False)
    else:
        write_secret(
            runner_secret,
            runner_secret.read_text(encoding="utf-8"),
            newline=False,
        )


def api(
    selected: Runtime,
    method: str,
    path: str,
    *,
    payload: dict[str, Any] | None = None,
    authenticated: bool = True,
) -> Any:
    headers = {"Accept": "application/json", "User-Agent": "forgejo-local-ci/2"}
    if authenticated:
        try:
            token = selected.token_file.read_text(encoding="utf-8").strip()
        except FileNotFoundError as error:
            raise Failure("run `forgejo-local-ci bootstrap` first") from error
        headers["Authorization"] = f"token {token}"
    body = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload, separators=(",", ":")).encode()
    request = urllib.request.Request(
        selected.url + path,
        data=body,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            content = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace").strip()
        raise Failure(f"{method} {path}: HTTP {error.code}: {detail}") from error
    except (
        urllib.error.URLError,
        http.client.HTTPException,
        TimeoutError,
    ) as error:
        reason = getattr(error, "reason", error)
        raise Failure(f"{method} {path}: {reason}") from error
    if not content:
        return None
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        return content.decode(errors="replace")


def exists(selected: Runtime, path: str) -> bool:
    try:
        api(selected, "GET", path)
        return True
    except Failure as error:
        if "HTTP 404:" in str(error):
            return False
        raise


def remote_file_exists(selected: Runtime, path: str) -> bool:
    try:
        payload = api(selected, "GET", path)
    except Failure as error:
        if "HTTP 404:" in str(error):
            return False
        raise
    return isinstance(payload, dict) and isinstance(payload.get("sha"), str)


def wait_for_health(selected: Runtime, timeout: int = 120) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            api(selected, "GET", "/api/healthz", authenticated=False)
            return
        except Failure:
            time.sleep(1)
    raise Failure(f"Forgejo did not become healthy at {selected.url}")


def compose_exec(selected: Runtime, *arguments: str, capture: bool = False) -> str:
    return run(
        selected.compose_argv("exec", "-T", "-u", "git", "forgejo", *arguments),
        environment=selected.environment(),
        capture=capture,
    )


def ensure_admin(selected: Runtime) -> None:
    users = compose_exec(selected, "forgejo", "admin", "user", "list", capture=True)
    if re.search(rf"(^|\s){re.escape(selected.admin)}(\s|$)", users, re.MULTILINE):
        return
    password = (selected.secrets / "admin-password").read_text(encoding="utf-8").strip()
    compose_exec(
        selected,
        "forgejo",
        "admin",
        "user",
        "create",
        "--admin",
        "--username",
        selected.admin,
        "--password",
        password,
        "--email",
        selected.email,
        "--must-change-password=false",
    )


def ensure_token(selected: Runtime) -> None:
    if selected.token_file.exists():
        return
    token = compose_exec(
        selected,
        "forgejo",
        "admin",
        "user",
        "generate-access-token",
        "--username",
        selected.admin,
        "--token-name",
        "local-ci",
        "--scopes",
        "all",
        "--raw",
        capture=True,
    )
    if not token:
        raise Failure("Forgejo returned an empty admin token")
    write_secret(selected.token_file, token)


def ensure_repository(selected: Runtime, name: str) -> None:
    if exists(selected, f"/api/v1/repos/{selected.admin}/{name}"):
        return
    api(
        selected,
        "POST",
        "/api/v1/user/repos",
        payload={"name": name, "private": True, "auto_init": False},
    )


def wait_for_git_repository(
    selected: Runtime,
    name: str,
    timeout: int = 30,
) -> None:
    token = selected.token_file.read_text(encoding="utf-8").strip()
    credentials = base64.b64encode(f"{selected.admin}:{token}".encode()).decode()
    url = (
        f"{selected.url}/{selected.admin}/{name}.git/info/refs?service=git-receive-pack"
    )
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        operation = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Basic {credentials}",
                "User-Agent": "forgejo-local-ci/2",
            },
        )
        try:
            with urllib.request.urlopen(operation, timeout=10) as response:
                if response.status == 200:
                    return
        except urllib.error.HTTPError as error:
            if error.code not in {401, 404}:
                raise Failure(
                    f"Forgejo Git endpoint returned HTTP {error.code}"
                ) from error
        except urllib.error.URLError:
            pass
        time.sleep(0.5)
    raise Failure(f"Forgejo Git endpoint did not become ready for {name}")


def askpass(selected: Runtime, directory: Path) -> Path:
    path = directory / "askpass"
    quoted_user = json.dumps(selected.admin)
    quoted_token = json.dumps(str(selected.token_file))
    path.write_text(
        "#!/usr/bin/env python3\n"
        "import pathlib, sys\n"
        f"user = {quoted_user}\n"
        f"token = pathlib.Path({quoted_token}).read_text().strip()\n"
        "print(user if 'Username' in sys.argv[1] else token)\n",
        encoding="utf-8",
    )
    path.chmod(0o700)
    return path


def push_smoke_repository(selected: Runtime) -> None:
    workflow_path = (
        f"/api/v1/repos/{selected.admin}/{selected.repository}/contents/"
        ".forgejo/workflows/local-ci.yml?ref=main"
    )
    if remote_file_exists(selected, workflow_path):
        return
    with tempfile.TemporaryDirectory(prefix="forgejo-local-ci-smoke-") as temporary:
        repository = Path(temporary)
        workflow = repository / ".forgejo" / "workflows" / "local-ci.yml"
        workflow.parent.mkdir(parents=True)
        workflow.write_text(
            "name: local-ci\n\n"
            "on:\n"
            "  push:\n"
            "  workflow_dispatch:\n\n"
            "jobs:\n"
            "  smoke:\n"
            "    runs-on: ubuntu-latest\n"
            "    steps:\n"
            "      - run: node --version\n",
            encoding="utf-8",
        )
        run(["git", "init", "-q", "-b", "main"], cwd=repository)
        run(["git", "add", ".forgejo/workflows/local-ci.yml"], cwd=repository)
        run(
            [
                "git",
                "-c",
                f"user.name={selected.admin}",
                "-c",
                f"user.email={selected.email}",
                "commit",
                "-qm",
                "Add local CI smoke workflow",
            ],
            cwd=repository,
        )
        helper = askpass(selected, repository)
        environment = os.environ.copy()
        environment.update(
            {
                "GIT_ASKPASS": str(helper),
                "GIT_ASKPASS_REQUIRE": "force",
                "GIT_TERMINAL_PROMPT": "0",
            }
        )
        run(
            [
                "git",
                "push",
                f"{selected.url}/{selected.admin}/{selected.repository}.git",
                "main:main",
            ],
            cwd=repository,
            environment=environment,
        )


def register_runner(selected: Runtime) -> None:
    config = selected.state / "runner" / "runner-config.yml"
    if config.exists():
        return
    secret = (selected.secrets / "runner-secret").read_text(encoding="utf-8").strip()
    output = compose_exec(
        selected,
        "forgejo",
        "forgejo-cli",
        "actions",
        "register",
        "--name",
        selected.runner,
        "--scope",
        selected.admin,
        "--secret-file",
        "/local-ci-secrets/runner-secret",
        "--labels",
        "ubuntu-latest,node22,docker",
        capture=True,
    )
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        raise Failure("Forgejo did not return a runner UUID")
    runner_uuid = lines[-1]
    config.write_text(
        "log:\n"
        "  level: info\n"
        "runner:\n"
        "  file: /data/.runner\n"
        "  capacity: 2\n"
        "  timeout: 3h\n"
        "  labels:\n"
        "    - ubuntu-latest:docker://docker.io/library/node:22-bookworm\n"
        "    - node22:docker://docker.io/library/node:22-bookworm\n"
        "    - docker:docker://docker.io/library/node:22-bookworm\n"
        "server:\n"
        "  connections:\n"
        "    local:\n"
        "      url: http://forgejo:3000/\n"
        f"      uuid: {runner_uuid}\n"
        f"      token: {secret}\n",
        encoding="utf-8",
    )
    config.chmod(0o600)


def bootstrap(selected: Runtime) -> None:
    require("docker", "git")
    prepare_state(selected)
    run(
        selected.compose_argv("up", "-d", "forgejo", "docker-in-docker"),
        environment=selected.environment(),
    )
    wait_for_health(selected)
    ensure_admin(selected)
    ensure_token(selected)
    ensure_repository(selected, selected.repository)
    wait_for_git_repository(selected, selected.repository)
    push_smoke_repository(selected)
    register_runner(selected)
    run(
        selected.compose_argv("--profile", "runner", "up", "-d", "runner"),
        environment=selected.environment(),
    )
    print(f"ready: {selected.url}/{selected.admin}/{selected.repository}")
    print(f"admin password: {selected.secrets / 'admin-password'}")


def status(selected: Runtime) -> None:
    require("docker")
    run(
        selected.compose_argv("--profile", "runner", "ps"),
        environment=selected.environment(),
    )


def doctor(selected: Runtime) -> None:
    require("docker", "git")
    status(selected)
    health = api(selected, "GET", "/api/healthz", authenticated=False)
    version = api(selected, "GET", "/api/v1/version")
    runners = api(selected, "GET", "/api/v1/user/actions/runners")
    runner_items = (
        runners.get("runners", runners) if isinstance(runners, dict) else runners
    )
    print(
        json.dumps(
            {"health": health, "version": version, "runners": runner_items}, indent=2
        )
    )


def dispatch(selected: Runtime, repository: str, workflow: str, ref: str) -> None:
    if not NAME.fullmatch(repository) or not NAME.fullmatch(workflow):
        raise Failure("repository and workflow must be safe path segments")
    api(
        selected,
        "POST",
        (
            f"/api/v1/repos/{selected.admin}/{repository}/actions/workflows/"
            f"{workflow}/dispatches"
        ),
        payload={"ref": ref, "inputs": {}},
    )
    print(f"dispatched: {selected.admin}/{repository} {workflow}@{ref}")


def poll(
    selected: Runtime,
    repository: str,
    timeout: int,
    interval: float,
) -> None:
    if not NAME.fullmatch(repository):
        raise Failure("repository must be a safe path segment")
    deadline = time.monotonic() + timeout
    while True:
        payload = api(
            selected,
            "GET",
            f"/api/v1/repos/{selected.admin}/{repository}/actions/tasks",
        )
        runs = (
            payload.get("workflow_runs", payload)
            if isinstance(payload, dict)
            else payload
        )
        latest = runs[0] if runs else None
        if latest:
            state = str(latest.get("status", "unknown"))
            print(
                f"{latest.get('id', '?')} "
                f"{latest.get('name') or latest.get('display_title') or '?'} {state}"
            )
            if state in TERMINAL_STATES:
                if state != "success":
                    raise Failure(f"workflow finished with {state}")
                return
        else:
            print("no workflow run")
        if time.monotonic() >= deadline:
            raise Failure(f"timed out waiting for {selected.admin}/{repository}")
        time.sleep(interval)


def import_repository(selected: Runtime, source: Path, name: str | None) -> None:
    require("git")
    source = source.expanduser().resolve()
    run(["git", "-C", str(source), "rev-parse", "--git-dir"], capture=True)
    repository = name or source.name
    if not NAME.fullmatch(repository):
        raise Failure(f"invalid repository name: {repository!r}")
    ensure_repository(selected, repository)
    with tempfile.TemporaryDirectory(prefix="forgejo-local-ci-import-") as temporary:
        mirror = Path(temporary) / f"{repository}.git"
        run(["git", "clone", "--mirror", str(source), str(mirror)])
        helper = askpass(selected, Path(temporary))
        environment = os.environ.copy()
        environment.update(
            {
                "GIT_ASKPASS": str(helper),
                "GIT_ASKPASS_REQUIRE": "force",
                "GIT_TERMINAL_PROMPT": "0",
            }
        )
        run(
            [
                "git",
                "-C",
                str(mirror),
                "push",
                "--mirror",
                f"{selected.url}/{selected.admin}/{repository}.git",
            ],
            environment=environment,
        )
    print(f"imported: {source} -> {selected.admin}/{repository}")


def stop(selected: Runtime) -> None:
    require("docker")
    run(
        selected.compose_argv("--profile", "runner", "down", "--remove-orphans"),
        environment=selected.environment(),
    )


def validate_compose(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    images = re.findall(r"^\s*image:\s*(\S+)", text, re.MULTILINE)
    if len(images) != 3 or any(
        not re.search(r"@sha256:[0-9a-f]{64}$", image) for image in images
    ):
        raise Failure("compose images must be three immutable SHA-256 references")
    if "${FORGEJO_LOCAL_STATE}" not in text:
        raise Failure("compose state must be explicit and release-independent")
    if text.count("privileged: true") != 1:
        raise Failure("only Docker-in-Docker may be privileged")


def self_test(selected: Runtime) -> None:
    validate_compose(selected.compose)
    if not NAME.fullmatch("repo.with-spaces-not"):
        raise Failure("name validator is broken")
    print(f"forgejo-local-ci {VERSION} self-test ok")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="forgejo-local-ci")
    result.add_argument("--version", action="version", version=VERSION)
    result.add_argument("--state", type=Path, default=default_state())
    result.add_argument(
        "--compose", type=Path, default=package_root() / "share" / "compose.yaml"
    )
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("bootstrap")
    commands.add_parser("status")
    commands.add_parser("doctor")
    commands.add_parser("stop")
    commands.add_parser("self-test")
    dispatch_parser = commands.add_parser("dispatch")
    dispatch_parser.add_argument("repository", nargs="?")
    dispatch_parser.add_argument("workflow", nargs="?", default="local-ci.yml")
    dispatch_parser.add_argument("--ref", default="main")
    poll_parser = commands.add_parser("poll")
    poll_parser.add_argument("repository", nargs="?")
    poll_parser.add_argument("--timeout", type=int, default=300)
    poll_parser.add_argument("--interval", type=float, default=5)
    import_parser = commands.add_parser("import")
    import_parser.add_argument("source", type=Path)
    import_parser.add_argument("name", nargs="?")
    return result


def main(arguments: list[str] | None = None) -> int:
    args = parser().parse_args(arguments)
    try:
        selected = runtime(args)
        if args.command == "bootstrap":
            bootstrap(selected)
        elif args.command == "status":
            status(selected)
        elif args.command == "doctor":
            doctor(selected)
        elif args.command == "dispatch":
            dispatch(
                selected,
                args.repository or selected.repository,
                args.workflow,
                args.ref,
            )
        elif args.command == "poll":
            poll(
                selected,
                args.repository or selected.repository,
                args.timeout,
                args.interval,
            )
        elif args.command == "import":
            import_repository(selected, args.source, args.name)
        elif args.command == "stop":
            stop(selected)
        elif args.command == "self-test":
            self_test(selected)
        else:
            raise AssertionError(args.command)
        return 0
    except (Failure, OSError, ValueError) as error:
        print(f"forgejo-local-ci: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
