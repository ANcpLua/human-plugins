from __future__ import annotations

import re
import urllib.error
import urllib.request
from pathlib import Path

MARKDOWN_LINK = re.compile(r"\[[^\]]*]\(([^)]+)\)")
HTTP_URL = re.compile(r"https?://[^\s<>()]+")


def collect(root: Path) -> tuple[list[str], set[str]]:
    failures: list[str] = []
    urls: set[str] = set()
    for markdown in root.rglob("*.md"):
        if any(part in {".git", ".artifacts"} for part in markdown.parts):
            continue
        text = markdown.read_text(encoding="utf-8")
        for target in MARKDOWN_LINK.findall(text):
            target = target.strip()
            if target.startswith(("https://", "http://")):
                urls.add(target)
                continue
            if target.startswith(("#", "mailto:")):
                continue
            local = target.split("#", 1)[0].split("?", 1)[0]
            if local and not (markdown.parent / local).resolve().exists():
                failures.append(
                    f"broken local link in {markdown.relative_to(root)}: {target}"
                )
        for url in HTTP_URL.findall(text):
            urls.add(url.rstrip(".,;:"))
    return failures, urls


def check(root: Path, external: bool) -> tuple[list[str], set[str]]:
    failures, urls = collect(root)
    if not external:
        return failures, urls
    for url in sorted(urls):
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
                "User-Agent": "ANcpLua-human-tools-link-validator",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                if response.status >= 400:
                    failures.append(f"HTTP {response.status}: {url}")
        except urllib.error.HTTPError as error:
            failures.append(f"HTTP {error.code}: {url}")
        except urllib.error.URLError as error:
            failures.append(f"unreachable: {url} ({error.reason})")
    return failures, urls
