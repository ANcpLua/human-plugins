#!/usr/bin/env python3
from __future__ import annotations

import argparse
import getpass
import json
import mimetypes
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

VERSION = "2.0.0"
DISCORD_API = "https://discord.com/api/v10"
GITHUB_API = "https://api.github.com"
USER_AGENT = f"qyl-discord-sync/{VERSION}"
TRAILER = re.compile(r"sync\s+key=([a-z0-9-]+)\s+commit=([0-9a-f]{40})")
NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
REF = re.compile(r"^[A-Za-z0-9._/-]+$")
MAX_ATTACHMENT_BYTES = 24 * 1024 * 1024


class Failure(RuntimeError):
    pass


@dataclass(frozen=True)
class Source:
    key: str
    channel_id: str
    repo: str
    branch: str
    path: str
    filename: str


def default_config() -> Path:
    return (
        Path(
            os.environ.get(
                "XDG_CONFIG_HOME",
                Path.home() / ".config",
            )
        ).expanduser()
        / "human-plugins"
        / "qyl-discord-sync.json"
    )


def validate_relative_path(value: str) -> bool:
    path = PurePosixPath(value)
    return bool(value) and not path.is_absolute() and ".." not in path.parts


def parse_config(data: object) -> tuple[Source, ...]:
    if not isinstance(data, dict) or set(data) != {"schemaVersion", "sources"}:
        raise Failure("config must contain only schemaVersion and sources")
    if data["schemaVersion"] != 1:
        raise Failure("config schemaVersion must be 1")
    raw_sources = data["sources"]
    if not isinstance(raw_sources, list) or not raw_sources:
        raise Failure("config sources must be a non-empty array")
    required = {"key", "channel_id", "repo", "branch", "path", "filename"}
    sources: list[Source] = []
    keys: set[str] = set()
    for index, raw in enumerate(raw_sources):
        field = f"sources[{index}]"
        if not isinstance(raw, dict) or set(raw) != required:
            raise Failure(f"{field} must contain exactly {sorted(required)}")
        if not all(isinstance(raw[name], str) and raw[name] for name in required):
            raise Failure(f"{field} values must be non-empty strings")
        source = Source(**raw)
        if not NAME.fullmatch(source.key):
            raise Failure(f"{field}.key is invalid")
        if source.key in keys:
            raise Failure(f"duplicate source key: {source.key}")
        if not source.channel_id.isascii() or not source.channel_id.isdigit():
            raise Failure(f"{field}.channel_id must be numeric")
        if not REPOSITORY.fullmatch(source.repo):
            raise Failure(f"{field}.repo must be owner/name")
        if not REF.fullmatch(source.branch) or ".." in source.branch.split("/"):
            raise Failure(f"{field}.branch is invalid")
        if not validate_relative_path(source.path):
            raise Failure(f"{field}.path must stay inside the repository")
        if PurePosixPath(
            source.filename
        ).name != source.filename or not source.filename.endswith((".yaml", ".yml")):
            raise Failure(f"{field}.filename must be a YAML basename")
        keys.add(source.key)
        sources.append(source)
    return tuple(sources)


def load_config(path: Path) -> tuple[Source, ...]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise Failure(
            f"missing config: {path}; copy the packaged sources.example.json"
        ) from error
    except json.JSONDecodeError as error:
        raise Failure(f"invalid JSON config {path}: {error}") from error
    return parse_config(data)


def run(arguments: list[str], *, cwd: Path | None = None) -> str:
    process = subprocess.run(
        arguments,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
    )
    if process.returncode:
        detail = (process.stderr or process.stdout).strip()
        raise Failure(
            f"{' '.join(arguments)} exited {process.returncode}"
            + (f": {detail}" if detail else "")
        )
    return process.stdout.strip()


def request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
) -> bytes:
    selected_headers = {"User-Agent": USER_AGENT, **(headers or {})}
    operation = urllib.request.Request(
        url,
        data=body,
        headers=selected_headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(operation, timeout=30) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace").strip()
        raise Failure(f"{method} {url}: HTTP {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        raise Failure(f"{method} {url}: {error.reason}") from error


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
) -> Any:
    content = request(url, method=method, headers=headers, body=body)
    try:
        return json.loads(content)
    except json.JSONDecodeError as error:
        raise Failure(f"{method} {url}: response is not JSON") from error


def github_headers() -> dict[str, str]:
    headers = {"Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def latest_commit(source: Source) -> str | None:
    query = urllib.parse.urlencode(
        {"sha": source.branch, "path": source.path, "per_page": 1}
    )
    payload = request_json(
        f"{GITHUB_API}/repos/{source.repo}/commits?{query}",
        headers=github_headers(),
    )
    if not isinstance(payload, list):
        raise Failure(f"GitHub returned an invalid commit list for {source.key}")
    if not payload:
        return None
    sha = payload[0].get("sha") if isinstance(payload[0], dict) else None
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise Failure(f"GitHub returned an invalid commit for {source.key}")
    return sha


def discord_token() -> str:
    environment = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if environment:
        return environment
    if sys.platform != "darwin":
        raise Failure("DISCORD_BOT_TOKEN is required on this platform")
    token = run(
        [
            "security",
            "find-generic-password",
            "-a",
            getpass.getuser(),
            "-s",
            "DISCORD_BOT_TOKEN",
            "-w",
        ]
    )
    if not token:
        raise Failure("the DISCORD_BOT_TOKEN keychain item is empty")
    return token


def discord_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bot {token}"}


def last_commit(token: str, source: Source) -> str | None:
    query = urllib.parse.urlencode({"limit": 50})
    messages = request_json(
        f"{DISCORD_API}/channels/{source.channel_id}/messages?{query}",
        headers=discord_headers(token),
    )
    if not isinstance(messages, list):
        raise Failure(f"Discord returned an invalid message list for {source.key}")
    for message in messages:
        if not isinstance(message, dict):
            continue
        match = TRAILER.search(str(message.get("content", "")))
        if match and match.group(1) == source.key:
            return match.group(2)
    return None


def document(source: Source, commit: str, directory: Path) -> bytes:
    files: list[dict[str, str]] = []
    total = 0
    for path in sorted(directory.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        resolved = path.resolve()
        try:
            relative = resolved.relative_to(directory.resolve()).as_posix()
        except ValueError as error:
            raise Failure(f"file escapes sparse checkout: {path}") from error
        content = path.read_text(encoding="utf-8", errors="replace")
        content = content.replace("\r\n", "\n").replace("\r", "\n")
        total += len(content.encode())
        if total > MAX_ATTACHMENT_BYTES:
            raise Failure(
                f"{source.key} exceeds the {MAX_ATTACHMENT_BYTES} byte attachment budget"
            )
        files.append({"path": relative, "content": content})
    if not files:
        raise Failure(f"{source.repo}/{source.path} contains no regular files")
    payload = {
        "source": {
            "repo": f"https://github.com/{source.repo}",
            "commit": commit,
            "dir": source.path,
        },
        "files": files,
    }
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode()
    if len(encoded) > MAX_ATTACHMENT_BYTES:
        raise Failure(
            f"{source.key} exceeds the {MAX_ATTACHMENT_BYTES} byte attachment budget"
        )
    json.loads(encoded)
    return encoded


def export(source: Source, commit: str) -> tuple[bytes, int]:
    with tempfile.TemporaryDirectory(prefix=f"qyl-discord-{source.key}-") as temporary:
        checkout = Path(temporary)
        run(
            [
                "git",
                "clone",
                "--depth",
                "1",
                "--filter=blob:none",
                "--sparse",
                "--branch",
                source.branch,
                f"https://github.com/{source.repo}.git",
                str(checkout),
            ]
        )
        run(["git", "-C", str(checkout), "sparse-checkout", "set", source.path])
        directory = checkout / source.path
        if not directory.is_dir():
            raise Failure(f"sparse checkout did not produce {source.path}")
        content = document(source, commit, directory)
        count = len(json.loads(content)["files"])
        return content, count


def multipart(
    fields: dict[str, str],
    filename: str,
    content: bytes,
) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                value.encode(),
                b"\r\n",
            ]
        )
    content_type = mimetypes.guess_type(filename)[0] or "application/yaml"
    chunks.extend(
        [
            f"--{boundary}\r\n".encode(),
            (
                'Content-Disposition: form-data; name="files[0]"; '
                f'filename="{filename}"\r\n'
            ).encode(),
            f"Content-Type: {content_type}\r\n\r\n".encode(),
            content,
            b"\r\n",
            f"--{boundary}--\r\n".encode(),
        ]
    )
    return b"".join(chunks), boundary


def post(
    token: str,
    source: Source,
    commit: str,
    attachment: bytes,
    file_count: int,
) -> None:
    message = (
        f"Synced **{source.repo} / {source.path}** — {file_count} files. "
        f"Upstream `{commit[:12]}`.\n"
        f"-# sync key={source.key} commit={commit}"
    )
    body, boundary = multipart(
        {"payload_json": json.dumps({"content": message})},
        source.filename,
        attachment,
    )
    request(
        f"{DISCORD_API}/channels/{source.channel_id}/messages",
        method="POST",
        headers={
            **discord_headers(token),
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        body=body,
    )


def sync(
    sources: tuple[Source, ...],
    *,
    only: str | None,
    dry_run: bool,
    force: bool,
) -> None:
    selected = tuple(source for source in sources if only in (None, source.key))
    if only is not None and not selected:
        raise Failure(f"unknown source key: {only}")
    token = discord_token()
    changed = 0
    for source in selected:
        upstream = latest_commit(source)
        if upstream is None:
            raise Failure(f"no commit touches {source.repo}/{source.path}")
        stored = last_commit(token, source)
        drift = force or stored != upstream
        state = "force" if force else ("drift" if drift else "in-sync")
        print(
            f"{source.key}: upstream={upstream[:12]} "
            f"channel={stored[:12] if stored else '-'} {state}"
        )
        if not drift:
            continue
        changed += 1
        if dry_run:
            continue
        attachment, count = export(source, upstream)
        post(token, source, upstream, attachment, count)
        print(f"{source.key}: posted {count} files")
    suffix = "would change" if dry_run else "updated"
    print(f"done: {changed} source(s) {suffix}")


def self_test() -> None:
    source = Source(
        key="example",
        channel_id="123456789",
        repo="example/project",
        branch="main",
        path="docs",
        filename="docs.yaml",
    )
    parse_config(
        {
            "schemaVersion": 1,
            "sources": [
                {
                    "key": source.key,
                    "channel_id": source.channel_id,
                    "repo": source.repo,
                    "branch": source.branch,
                    "path": source.path,
                    "filename": source.filename,
                }
            ],
        }
    )
    with tempfile.TemporaryDirectory(prefix="qyl-discord-self-test-") as temporary:
        root = Path(temporary)
        (root / "a.md").write_text("hello\n", encoding="utf-8")
        payload = json.loads(document(source, "a" * 40, root))
        if payload["files"] != [{"path": "a.md", "content": "hello\n"}]:
            raise Failure("document roundtrip failed")
    print(f"qyl-discord-sync {VERSION} self-test ok")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="qyl-discord-sync")
    result.add_argument("--version", action="version", version=VERSION)
    result.add_argument("--config", type=Path, default=default_config())
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("check-config")
    commands.add_parser("self-test")
    sync_parser = commands.add_parser("sync")
    sync_parser.add_argument("--only")
    sync_parser.add_argument("--dry-run", action="store_true")
    sync_parser.add_argument("--force", action="store_true")
    return result


def main(arguments: list[str] | None = None) -> int:
    args = parser().parse_args(arguments)
    try:
        if args.command == "self-test":
            self_test()
        elif args.command == "check-config":
            sources = load_config(args.config)
            print(f"config ok: {len(sources)} source(s)")
        elif args.command == "sync":
            sync(
                load_config(args.config),
                only=args.only,
                dry_run=args.dry_run,
                force=args.force,
            )
        else:
            raise AssertionError(args.command)
        return 0
    except (Failure, OSError, ValueError) as error:
        print(f"qyl-discord-sync: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
