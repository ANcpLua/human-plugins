from __future__ import annotations

import unittest

from memcheck import GIB, parse_linux_meminfo, parse_macos_vm


class MemcheckTests(unittest.TestCase):
    def test_linux_available_and_swap(self) -> None:
        result = parse_linux_meminfo(
            "MemTotal:       16000000 kB\n"
            "MemAvailable:    4000000 kB\n"
            "SwapTotal:       2000000 kB\n"
            "SwapFree:         500000 kB\n"
        )
        self.assertEqual(result.used, 12_000_000 * 1024)
        self.assertEqual(result.swap_used, 1_500_000 * 1024)

    def test_macos_pressure_pages(self) -> None:
        result = parse_macos_vm(
            16 * GIB,
            "Mach Virtual Memory Statistics: (page size of 16384 bytes)\n"
            "Pages active: 100000.\n"
            "Pages wired down: 20000.\n"
            "Pages occupied by compressor: 30000.\n",
            "total = 4096.00M  used = 1024.00M  free = 3072.00M",
        )
        self.assertEqual(result.used, 150000 * 16384)
        self.assertEqual(result.swap_used, GIB)


if __name__ == "__main__":
    unittest.main()
