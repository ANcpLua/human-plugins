#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import platform
import re
import subprocess
from dataclasses import asdict, dataclass

GIB = 1024**3


@dataclass(frozen=True)
class Memory:
    total: int
    used: int
    available: int
    swap_total: int
    swap_used: int


@dataclass(frozen=True)
class Process:
    pid: int
    rss: int
    command: str


def parse_linux_meminfo(text: str) -> Memory:
    values = {
        key: int(value) * 1024
        for key, value in re.findall(r"^(\w+):\s+(\d+)\s+kB$", text, re.MULTILINE)
    }
    required = ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree")
    if any(key not in values for key in required):
        raise ValueError("Linux meminfo is incomplete")
    return Memory(
        total=values["MemTotal"],
        used=values["MemTotal"] - values["MemAvailable"],
        available=values["MemAvailable"],
        swap_total=values["SwapTotal"],
        swap_used=values["SwapTotal"] - values["SwapFree"],
    )


def parse_macos_vm(total: int, vm_stat: str, swapusage: str) -> Memory:
    page_match = re.search(r"page size of (\d+) bytes", vm_stat)
    if not page_match:
        raise ValueError("vm_stat page size is missing")
    page_size = int(page_match.group(1))
    pages = {
        name: int(value.replace(".", ""))
        for name, value in re.findall(r"^([^:]+):\s+([\d.]+)\.$", vm_stat, re.MULTILINE)
    }
    used_pages = sum(
        pages.get(name, 0)
        for name in ("Pages active", "Pages wired down", "Pages occupied by compressor")
    )
    swap = re.search(r"total = ([\d.]+)M\s+used = ([\d.]+)M", swapusage)
    if not swap:
        raise ValueError("vm.swapusage is invalid")
    used = min(total, used_pages * page_size)
    return Memory(
        total=total,
        used=used,
        available=total - used,
        swap_total=int(float(swap.group(1)) * 1024**2),
        swap_used=int(float(swap.group(2)) * 1024**2),
    )


def memory_snapshot(system: str | None = None) -> Memory:
    selected = system or platform.system()
    if selected == "Linux":
        with open("/proc/meminfo", encoding="utf-8") as stream:
            return parse_linux_meminfo(stream.read())
    if selected == "Darwin":
        total = int(
            subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True).strip()
        )
        vm_stat = subprocess.check_output(["vm_stat"], text=True)
        swap = subprocess.check_output(["sysctl", "-n", "vm.swapusage"], text=True)
        return parse_macos_vm(total, vm_stat, swap)
    raise RuntimeError(f"unsupported platform: {selected}")


def matching_processes(pattern: re.Pattern[str]) -> list[Process]:
    output = subprocess.check_output(["ps", "-axo", "rss=,pid=,command="], text=True)
    matches: list[Process] = []
    for line in output.splitlines():
        fields = line.strip().split(maxsplit=2)
        if len(fields) != 3 or not pattern.search(fields[2]):
            continue
        matches.append(
            Process(pid=int(fields[1]), rss=int(fields[0]) * 1024, command=fields[2])
        )
    return sorted(matches, key=lambda process: process.rss, reverse=True)


def gib(value: int) -> str:
    return f"{value / GIB:.2f} GiB"


def self_test() -> None:
    linux = parse_linux_meminfo(
        "MemTotal:       16000000 kB\n"
        "MemAvailable:    4000000 kB\n"
        "SwapTotal:       2000000 kB\n"
        "SwapFree:         500000 kB\n"
    )
    assert linux.used == 12_000_000 * 1024
    mac = parse_macos_vm(
        16 * GIB,
        "Mach Virtual Memory Statistics: (page size of 16384 bytes)\n"
        "Pages active: 100000.\n"
        "Pages wired down: 20000.\n"
        "Pages occupied by compressor: 30000.\n",
        "total = 4096.00M  used = 1024.00M  free = 3072.00M",
    )
    assert mac.swap_used == 1024**3
    print("memcheck self-test: ok")


def main() -> int:
    parser = argparse.ArgumentParser(prog="memcheck")
    parser.add_argument("--match", default=r"claude|codex")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    pattern = re.compile(args.match, re.IGNORECASE)
    memory = memory_snapshot()
    processes = matching_processes(pattern)
    if args.json:
        print(
            json.dumps(
                {
                    "memory": asdict(memory),
                    "processes": [asdict(process) for process in processes],
                },
                indent=2,
            )
        )
        return 0
    print(
        f"Memory  {gib(memory.used)} used / {gib(memory.total)} total "
        f"({gib(memory.available)} available)"
    )
    print(f"Swap    {gib(memory.swap_used)} used / {gib(memory.swap_total)} total")
    print("\nProcesses")
    if not processes:
        print("  none")
        return 0
    for process in processes:
        command = (
            process.command
            if len(process.command) <= 100
            else f"{process.command[:97]}..."
        )
        print(f"  {gib(process.rss):>10}  {process.pid:<7} {command}")
    print(f"  {gib(sum(process.rss for process in processes)):>10}  total")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
