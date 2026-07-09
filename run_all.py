#!/usr/bin/env python3
"""Single entry point: generate vectors, run all Verilator regressions, run unit tests.

Runs every documented verification step in order and reports one pass/fail summary.
Intended for local use and CI (see .github/workflows/ci.yml).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent

STEPS: list[tuple[str, list[str]]] = [
    # 1. Vector generation (directed / random / mixed) -> sim/vectors/*
    #    NOTE: this list mirrors the vector sets gen_gemm_vectors.py can produce;
    #    if a new set is added there, add its generation step here too.
    ("gen directed", ["python3", "model/python/gen_gemm_vectors.py",
                      "--directed-file", "model/gemm_directed_cases.json"]),
    ("gen random", ["python3", "model/python/gen_gemm_vectors.py", "--seed", "20260603"]),
    ("gen mixed", ["python3", "model/python/gen_gemm_vectors.py",
                  "--directed-file", "model/gemm_directed_cases.json", "--seed", "20260603"]),
    # 2. Verilator regressions (--jobs 1: verilator -j 0 intermittently aborts with
    #    "Internal Error: attempted to destroy locked Thread Pool" on v5.020)
    ("regress rtl", ["python3", "sim/scripts/run_gemm_regression.py", "--target", "rtl", "--jobs", "1"]),
    ("regress rtl_AT", ["python3", "sim/scripts/run_gemm_regression.py", "--target", "rtl_AT", "--jobs", "1"]),
    ("regress rtl_v2", ["python3", "sim/scripts/run_gemm_regression.py", "--target", "rtl_v2", "--jobs", "1"]),
    ("system verify", ["python3", "sim/scripts/run_gemm_system_verification.py", "--jobs", "1"]),
    # 3. CPU unit smoke TBs (self-checking; $fatal -> nonzero exit on FAIL)
    ("build tb_alu", ["verilator", "--binary", "--timing", "-Wall", "-Wno-fatal",
                      "-Irtl_v2/simple_cpu", "--Mdir", "sim/build/tb_alu",
                      "sim/tb/tb_alu.sv", "rtl_v2/simple_cpu/alu.v", "--top-module", "tb_alu"]),
    ("run tb_alu", ["sim/build/tb_alu/Vtb_alu"]),
    ("build tb_decoder", ["verilator", "--binary", "--timing", "-Wall", "-Wno-fatal",
                          "-Irtl_v2/simple_cpu", "--Mdir", "sim/build/tb_decoder",
                          "sim/tb/tb_decoder.sv", "rtl_v2/simple_cpu/decoder.v", "--top-module", "tb_decoder"]),
    ("run tb_decoder", ["sim/build/tb_decoder/Vtb_decoder"]),
    ("build tb_cpu_seq", ["verilator", "--binary", "--timing", "-Wall", "-Wno-fatal",
                          "-Irtl_v2/simple_cpu", "--Mdir", "sim/build/tb_cpu_seq",
                          "sim/tb/tb_cpu_seq.sv", "rtl_v2/simple_cpu/pc.v",
                          "rtl_v2/simple_cpu/inst_reg.v", "rtl_v2/simple_cpu/accumulator.v",
                          "rtl_v2/simple_cpu/cpu_fsm.v", "--top-module", "tb_cpu_seq"]),
    ("run tb_cpu_seq", ["sim/build/tb_cpu_seq/Vtb_cpu_seq"]),
    # 4. FPGA top: elaboration-only check (no TB; Vivado is the real build).
    #    PINCONNECTEMPTY is intentional -- debug buses are left open on the board.
    ("lint zybo_top", ["verilator", "--lint-only", "--timing", "-Wall", "-Wno-fatal",
                       "-Wno-PINCONNECTEMPTY",
                       "-Irtl_v2", "-Irtl_v2/simple_cpu", "-Irtl_v2/gemm_accelerator",
                       "rtl_v2/zybo_top.v", "rtl_v2/gemm_system_top.v", "rtl_v2/gemm_cpu_glue.v",
                       "rtl_v2/gemm_accelerator/gemm_accelerator_top.v",
                       "rtl_v2/gemm_accelerator/gemm_controller_fsm.v",
                       "rtl_v2/gemm_accelerator/gemm_local_buffer.v",
                       "rtl_v2/gemm_accelerator/gemm_lsu.v",
                       "rtl_v2/gemm_accelerator/gemm_mac_datapath.v",
                       "rtl_v2/gemm_accelerator/gemm_mac_datapath4.v",
                       "rtl_v2/gemm_accelerator/gemm_mac_datapath_at.v",
                       "rtl_v2/gemm_accelerator/gemm_mmio_reg.v",
                       "rtl_v2/simple_cpu/top_cpu.v", "rtl_v2/simple_cpu/pc.v",
                       "rtl_v2/simple_cpu/inst_reg.v", "rtl_v2/simple_cpu/decoder.v",
                       "rtl_v2/simple_cpu/cpu_fsm.v", "rtl_v2/simple_cpu/alu.v",
                       "rtl_v2/simple_cpu/accumulator.v",
                       "--top-module", "zybo_top"]),
    # 5. Python unit tests
    ("unittest sim", ["python3", "-m", "unittest", "discover", "-s", "sim/tests/python", "-p", "test_*.py"]),
    ("unittest sw", ["python3", "-m", "unittest", "discover", "-s", "sw/tests/python", "-p", "test_*.py"]),
]


def main() -> int:
    results: list[tuple[str, int]] = []
    for name, command in STEPS:
        print(f"\n===== {name}: {' '.join(command)} =====", flush=True)
        rc = subprocess.run(command, cwd=REPO_ROOT).returncode
        results.append((name, rc))
        if rc != 0:
            print(f"[FAIL] {name} exited {rc}", flush=True)

    print("\n===== SUMMARY =====")
    for name, rc in results:
        print(f"  {'PASS' if rc == 0 else 'FAIL'}  {name}")
    failed = [name for name, rc in results if rc != 0]
    print(f"\n{len(results) - len(failed)}/{len(results)} steps passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
