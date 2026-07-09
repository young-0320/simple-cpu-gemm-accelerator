from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = REPO_ROOT / "model" / "python"
sys.path.insert(0, str(MODEL_DIR))

from golden_gemm import (  # noqa: E402
    MAX_DIM,
    STATUS_BUSY_BIT,
    STATUS_DONE_BIT,
    STATUS_ERROR_BIT,
    STATUS_INVALID_SIZE_BIT,
)

# gemm_define.vh is hand-duplicated across all three RTL trees (see
# docs/CONTRIBUTING.md -- rtl/ and rtl_AT/ are GEMM-accelerator-only PPA
# comparison targets, rtl_v2/ is the final chosen system). Parse the same
# one every other check in this file uses, and separately assert the other
# two copies haven't drifted from it.
CANONICAL_DEFINE_PATH = REPO_ROOT / "rtl" / "gemm_accelerator" / "gemm_define.vh"
OTHER_DEFINE_PATHS = [
    REPO_ROOT / "rtl_v2" / "gemm_accelerator" / "gemm_define.vh",
    REPO_ROOT / "rtl_AT" / "gemm_accelerator" / "gemm_define.vh",
]

DEFINE_RE = re.compile(r"^`define\s+(\S+)\s+(\S+)")
VERILOG_LITERAL_RE = re.compile(r"(\d+)'([bdho])([0-9a-fA-F]+)", re.IGNORECASE)
VERILOG_BASE = {"b": 2, "d": 10, "h": 16, "o": 8}


def parse_verilog_literal(token: str) -> int:
    m = VERILOG_LITERAL_RE.fullmatch(token)
    if m:
        return int(m.group(3), VERILOG_BASE[m.group(2).lower()])
    return int(token, 0)


def parse_defines(path: Path) -> dict[str, int]:
    defines: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = DEFINE_RE.match(line.strip())
        if not m:
            continue
        name, value = m.groups()
        try:
            defines[name] = parse_verilog_literal(value)
        except ValueError:
            continue  # e.g. include-guard macros with no value
    return defines


class TestGemmDefineTreesInSync(unittest.TestCase):
    def test_gemm_define_identical_across_rtl_trees(self) -> None:
        canonical = CANONICAL_DEFINE_PATH.read_text(encoding="utf-8")
        for path in OTHER_DEFINE_PATHS:
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                canonical,
                f"{path} has drifted from {CANONICAL_DEFINE_PATH}. If this "
                "divergence is intentional, this test needs updating "
                "alongside it -- not just silenced.",
            )


class TestGemmDefineMatchesGoldenModel(unittest.TestCase):
    """Guards against exactly the failure mode this test was written for:
    RTL changes a status bit position or the dimension range in
    gemm_define.vh, and model/python/golden_gemm.py -- which every test
    vector in sim/vectors/ is generated from -- silently keeps using the
    old values."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.defines = parse_defines(CANONICAL_DEFINE_PATH)

    def test_status_bit_positions(self) -> None:
        self.assertEqual(self.defines["GEMM_ST_BUSY_BIT"], STATUS_BUSY_BIT)
        self.assertEqual(self.defines["GEMM_ST_DONE_BIT"], STATUS_DONE_BIT)
        self.assertEqual(self.defines["GEMM_ST_ERROR_BIT"], STATUS_ERROR_BIT)
        self.assertEqual(self.defines["GEMM_ST_INVSIZE_BIT"], STATUS_INVALID_SIZE_BIT)

    def test_dimension_range(self) -> None:
        self.assertEqual(self.defines["GEMM_DIM_MIN"], 1)
        self.assertEqual(self.defines["GEMM_DIM_MAX"], MAX_DIM)


class TestGemmRegsHeaderMatchesDefine(unittest.TestCase):
    """sim/tb/gemm_regs.h mirrors gemm_define.vh by hand for the C++
    harnesses; keep the copy honest the same way golden_gemm.py is."""

    HEADER_PATH = REPO_ROOT / "sim" / "tb" / "gemm_regs.h"
    CDEFINE_RE = re.compile(r"^#define\s+(\S+)\s+(\S+)")

    @classmethod
    def setUpClass(cls) -> None:
        cls.defines = parse_defines(CANONICAL_DEFINE_PATH)
        cls.header: dict[str, int] = {}
        for line in cls.HEADER_PATH.read_text(encoding="utf-8").splitlines():
            m = cls.CDEFINE_RE.match(line.strip())
            if not m:
                continue
            name, value = m.groups()
            try:
                cls.header[name] = int(value, 0)
            except ValueError:
                continue  # include guard

    def test_common_names_agree(self) -> None:
        common = set(self.header) & set(self.defines)
        self.assertGreaterEqual(len(common), 14, "header/define overlap shrank unexpectedly")
        for name in sorted(common):
            self.assertEqual(
                self.header[name], self.defines[name],
                f"{name} drifted between gemm_regs.h and gemm_define.vh")

    def test_absolute_addresses_are_base_plus_offset(self) -> None:
        base = self.defines["GEMM_MMIO_BASE"]
        for off_name, off in self.defines.items():
            if not off_name.startswith("GEMM_OFF_"):
                continue
            addr_name = "GEMM_" + off_name[len("GEMM_OFF_"):] + "_ADDR"
            self.assertIn(addr_name, self.header, f"gemm_regs.h is missing {addr_name}")
            self.assertEqual(
                self.header[addr_name], base + off,
                f"{addr_name} != GEMM_MMIO_BASE + {off_name}")


if __name__ == "__main__":
    unittest.main()
