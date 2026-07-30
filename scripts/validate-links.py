#!/usr/bin/env python3

import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog.json"
MARKDOWN_LINK = re.compile(r"\[[^\]]*]\(([^)]+)\)")
HTTP_URL = re.compile(r"https?://[^\s<>()]+")
REQUIRED_TOOL_DOCS = ("README.md", "CLAUDE.md", "CHANGELOG.md")


def fail(message: str) -> None:
    failures.append(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_url(url: str) -> None:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
            "User-Agent": "ANcpLua-human-plugins-link-validator",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status >= 400:
                fail(f"HTTP {response.status}: {url}")
    except urllib.error.HTTPError as error:
        fail(f"HTTP {error.code}: {url}")
    except urllib.error.URLError as error:
        fail(f"unreachable: {url} ({error.reason})")


def raw_readme(repository: str) -> str:
    path = repository.removeprefix("https://github.com/")
    url = f"https://raw.githubusercontent.com/{path}/main/README.md"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "ANcpLua-human-plugins-link-validator"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.read().decode("utf-8")
    except (urllib.error.HTTPError, urllib.error.URLError, UnicodeDecodeError) as error:
        fail(f"cannot read canonical README: {url} ({error})")
        return ""


failures: list[str] = []
catalog = json.loads(read(CATALOG))
if catalog.get("schemaVersion") != 1:
    fail("catalog.json schemaVersion must be 1")

tools = catalog.get("tools")
if not isinstance(tools, list):
    fail("catalog.json tools must be an array")
    tools = []

names: set[str] = set()
catalog_urls: set[str] = set()
for tool in tools:
    name = tool.get("name")
    if not isinstance(name, str) or not name:
        fail("catalog tool has no name")
        continue
    if name in names:
        fail(f"duplicate catalog tool: {name}")
    names.add(name)

    directory = ROOT / "tools" / name
    if not directory.is_dir():
        fail(f"catalog tool directory missing: tools/{name}")
        continue
    for document in REQUIRED_TOOL_DOCS:
        if not (directory / document).is_file():
            fail(f"required tool document missing: tools/{name}/{document}")

    catalog_entry = tool.get("catalogEntry")
    if not isinstance(catalog_entry, str):
        fail(f"catalogEntry missing for {name}")
    else:
        catalog_urls.add(catalog_entry)

    ownership = tool.get("ownership")
    canonical = tool.get("canonicalRepository")
    if ownership == "federated":
        if not isinstance(canonical, str):
            fail(f"federated tool has no canonicalRepository: {name}")
            continue
        canonical_readme = raw_readme(canonical)
        if isinstance(catalog_entry, str) and catalog_entry not in canonical_readme:
            fail(f"canonical README does not link back to catalog: {name}")
    elif ownership == "embedded":
        if canonical != "https://github.com/ANcpLua/human-plugins":
            fail(f"embedded tool has unexpected canonicalRepository: {name}")
    elif ownership == "retired":
        if canonical is not None:
            fail(f"retired tool must use null canonicalRepository: {name}")
    else:
        fail(f"unknown ownership for {name}: {ownership}")

directory_names = {path.name for path in (ROOT / "tools").iterdir() if path.is_dir()}
for missing in sorted(directory_names - names):
    fail(f"tool directory is absent from catalog.json: {missing}")
for missing in sorted(names - directory_names):
    fail(f"catalog tool has no directory: {missing}")

urls: set[str] = set(catalog_urls)
for markdown in ROOT.rglob("*.md"):
    if ".git" in markdown.parts:
        continue
    text = read(markdown)
    for target in MARKDOWN_LINK.findall(text):
        target = target.strip()
        if target.startswith(("https://", "http://")):
            urls.add(target)
            continue
        if target.startswith(("#", "mailto:")):
            continue
        local = target.split("#", 1)[0].split("?", 1)[0]
        if local and not (markdown.parent / local).resolve().exists():
            fail(f"broken local link in {markdown.relative_to(ROOT)}: {target}")
    for url in HTTP_URL.findall(text):
        urls.add(url.rstrip(".,;:"))

for tool in tools:
    canonical = tool.get("canonicalRepository")
    if isinstance(canonical, str):
        urls.add(canonical)

for url in sorted(urls):
    check_url(url)

if failures:
    print("link integrity failed:", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    sys.exit(1)

print(
    f"link integrity ok — {len(tools)} catalog entries, "
    f"{len(urls)} external URLs"
)
