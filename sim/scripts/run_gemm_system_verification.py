#!/usr/bin/env python3
"""Run rtl_v2 CPU-driven GEMM system verification and generate artifacts."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]

TB_TOP = "tb_gemm_system_v2"
TB_FILE = Path("sim/tb/tb_gemm_system_v2.sv")
BUILD_DIR = Path("sim/build/gemm_system_v2")


def project_path(path: Path) -> Path:
    return path if path.is_absolute() else REPO_ROOT / path


def cmd_path(path: Path) -> str:
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def allocate_result_dir(results_root: Path, requested_run_id: str) -> tuple[str, Path]:
    base = results_root / "system_v2" / requested_run_id
    candidate = base
    suffix = 1
    while candidate.exists():
        candidate = results_root / "system_v2" / f"{requested_run_id}_{suffix:02d}"
        suffix += 1
    candidate.mkdir(parents=True)
    return candidate.name, candidate


def run_command(command: list[str], log_path: Path) -> int:
    try:
        proc = subprocess.run(
            command,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as exc:
        output = f"failed to run command: {exc}\n"
        log_path.write_text(output, encoding="utf-8")
        print(output, end="")
        return 127
    log_path.write_text(proc.stdout, encoding="utf-8")
    print(proc.stdout, end="")
    return proc.returncode


def command_output(command: list[str]) -> str:
    try:
        proc = subprocess.run(
            command,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError:
        return "unavailable"
    text = proc.stdout.strip()
    return text if proc.returncode == 0 and text else "unavailable"


def git_output(command: list[str]) -> str:
    env = os.environ.copy()
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    try:
        proc = subprocess.run(
            command,
            cwd=REPO_ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError:
        return "unavailable"
    text = proc.stdout.strip()
    if proc.returncode != 0:
        return "unavailable"
    return text if text else "clean"


def parse_log_counts(log_text: str) -> tuple[dict[str, int], list[str]]:
    counts: dict[str, int] = {}
    raw_warning_blocks: list[str] = []
    current_block: list[str] = []

    def finish_block() -> None:
        nonlocal current_block
        if current_block:
            raw_warning_blocks.append("\n".join(current_block))
            current_block = []

    for line in log_text.splitlines():
        warning_match = re.match(r"^%Warning-([A-Za-z0-9_]+):", line)
        error_match = re.match(r"^%Error(?:-([A-Za-z0-9_]+))?:", line)
        fatal_match = re.match(r"^%Fatal(?:-([A-Za-z0-9_]+))?:", line)

        if warning_match:
            finish_block()
            kind = warning_match.group(1)
            counts[kind] = counts.get(kind, 0) + 1
            current_block = [line]
        elif error_match:
            finish_block()
            kind = error_match.group(1) or "ERROR"
            counts[kind] = counts.get(kind, 0) + 1
        elif fatal_match:
            finish_block()
            kind = fatal_match.group(1) or "FATAL"
            counts[kind] = counts.get(kind, 0) + 1
        elif current_block and (line.startswith(" ") or line.startswith("\t") or line.startswith(":")):
            current_block.append(line)
        else:
            finish_block()

    finish_block()
    return counts, raw_warning_blocks


def write_warning_summary(path: Path, counts: dict[str, int]) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(["type", "count"])
        for kind in sorted(counts):
            writer.writerow([kind, counts[kind]])


def read_tsv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def int_field(row: dict[str, str], key: str) -> int:
    value = row.get(key, "0")
    try:
        return int(value, 0)
    except ValueError:
        return 0


def write_json(path: Path, payload: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


def validate_build_dir(build_dir: Path) -> None:
    resolved_build_dir = build_dir.resolve()
    resolved_build_root = (REPO_ROOT / "sim" / "build").resolve()
    try:
        resolved_build_dir.relative_to(resolved_build_root)
    except ValueError as exc:
        raise ValueError(f"refusing build dir outside sim/build: {build_dir}") from exc
    if resolved_build_dir == resolved_build_root:
        raise ValueError("refusing to use the whole sim/build directory as one build target")


def clean_build_dir(build_dir: Path) -> None:
    validate_build_dir(build_dir)
    resolved_build_dir = build_dir.resolve()
    if resolved_build_dir.exists():
        shutil.rmtree(resolved_build_dir)


def collect_rtl_files(rtl_dir: Path) -> list[Path]:
    simple_cpu_files = sorted((rtl_dir / "simple_cpu").glob("*.v"))
    gemm_files = sorted((rtl_dir / "gemm_accelerator").glob("*.v"))
    top_files = [rtl_dir / "gemm_cpu_glue.v", rtl_dir / "gemm_system_top.v"]
    files = simple_cpu_files + gemm_files + top_files
    missing = [path for path in files if not path.exists()]
    if missing:
        missing_list = ", ".join(cmd_path(path) for path in missing)
        raise FileNotFoundError(f"missing rtl_v2 system file(s): {missing_list}")
    return files


def build_command(args: argparse.Namespace) -> list[str]:
    rtl_dir = project_path(args.rtl_dir)
    rtl_files = collect_rtl_files(rtl_dir)
    build_dir = project_path(args.build_dir)
    command = [
        "verilator",
        "-Wall",
        "-Wno-fatal",
        "--binary",
        "--timing",
        "-j",
        str(args.jobs),
    ]
    if args.trace_fst:
        command.append("--trace-fst")

    command.extend(
        [
            "-sv",
            "-CFLAGS",
            "-std=c++20",
            "--Mdir",
            cmd_path(build_dir),
            f"-I{cmd_path(rtl_dir)}",
            f"-I{cmd_path(rtl_dir / 'simple_cpu')}",
            f"-I{cmd_path(rtl_dir / 'gemm_accelerator')}",
            "--top-module",
            TB_TOP,
            f"-GMAC_MODE={args.mac_mode}",
            cmd_path(project_path(TB_FILE)),
        ]
    )
    command.extend(cmd_path(path) for path in rtl_files)
    return command


def executable_path(build_dir: Path) -> Path:
    exe = build_dir / f"V{TB_TOP}"
    if exe.exists():
        return exe
    exe_with_suffix = exe.with_suffix(".exe")
    return exe_with_suffix if exe_with_suffix.exists() else exe


def simulation_command(args: argparse.Namespace, run_id: str, result_dir: Path) -> list[str]:
    build_dir = project_path(args.build_dir)
    return [
        executable_path(build_dir).as_posix(),
        f"+RESULT_DIR={cmd_path(result_dir)}",
        f"+RUN_ID={run_id}",
        f"+DUMPFILE={cmd_path(result_dir / 'tb_gemm_system_v2.fst')}",
    ]


def build_summary(rows: list[dict[str, str]], build_rc: int, run_rc: int | None) -> dict[str, Any]:
    total = len(rows)
    passed = sum(1 for row in rows if row.get("result") == "PASS")
    failed = sum(1 for row in rows if row.get("result") == "FAIL")
    timeouts = sum(1 for row in rows if int_field(row, "timeout") != 0)
    total_cycles = sum(int_field(row, "cycles") for row in rows)
    total_busy_cycles = sum(int_field(row, "busy_cycles") for row in rows)
    total_load_cycles = sum(int_field(row, "load_cycles") for row in rows)
    total_compute_cycles = sum(int_field(row, "compute_cycles") for row in rows)
    total_store_cycles = sum(int_field(row, "store_cycles") for row in rows)
    total_c_compare_count = sum(int_field(row, "c_compare_count") for row in rows)
    total_c_mismatch_count = sum(int_field(row, "c_mismatch_count") for row in rows)
    return {
        "build_returncode": build_rc,
        "run_returncode": run_rc,
        "total_cases": total,
        "passed_cases": passed,
        "failed_cases": failed,
        "timeout_cases": timeouts,
        "pass_rate": (passed / total) if total else 0.0,
        "total_cycles": total_cycles,
        "max_cycles": max((int_field(row, "cycles") for row in rows), default=0),
        "total_busy_cycles": total_busy_cycles,
        "total_load_cycles": total_load_cycles,
        "total_compute_cycles": total_compute_cycles,
        "total_store_cycles": total_store_cycles,
        "total_c_compare_count": total_c_compare_count,
        "total_c_mismatch_count": total_c_mismatch_count,
    }


def md_escape(value: Any) -> str:
    return str(value).replace("|", "\\|")


def markdown_table(headers: list[str], rows: list[list[Any]]) -> str:
    lines = ["| " + " | ".join(headers) + " |"]
    lines.append("| " + " | ".join("---" for _ in headers) + " |")
    for row in rows:
        lines.append("| " + " | ".join(md_escape(item) for item in row) + " |")
    return "\n".join(lines)


def generate_report(
    path: Path,
    metadata: dict[str, Any],
    summary: dict[str, Any],
    warning_counts: dict[str, int],
    warning_blocks: list[str],
    case_rows: list[dict[str, str]],
    failure_rows: list[dict[str, str]],
) -> None:
    lines: list[str] = []
    lines.append("# GEMM System Verification Report")
    lines.append("")
    lines.append("## Verification Metadata")
    lines.append(
        markdown_table(
            ["Field", "Value"],
            [
                ["run_id", metadata["run_id"]],
                ["timestamp", metadata["timestamp"]],
                ["top_module", metadata["top_module"]],
                ["testbench", metadata["testbench"]],
                ["rtl_dir", metadata["rtl_dir"]],
                ["mac_mode", metadata["mac_mode"]],
                ["verilator_version", metadata["verilator_version"]],
                ["git_commit", metadata["git_commit"]],
                ["result_dir", metadata["result_dir"]],
            ],
        )
    )
    lines.append("")
    lines.append("## Test Summary")
    lines.append(
        markdown_table(
            ["Metric", "Value"],
            [
                ["build_returncode", summary["build_returncode"]],
                ["run_returncode", summary["run_returncode"]],
                ["total_cases", summary["total_cases"]],
                ["passed_cases", summary["passed_cases"]],
                ["failed_cases", summary["failed_cases"]],
                ["timeout_cases", summary["timeout_cases"]],
                ["pass_rate", f"{summary['pass_rate']:.3f}"],
                ["total_cycles", summary["total_cycles"]],
                ["max_cycles", summary["max_cycles"]],
                ["total_busy_cycles", summary["total_busy_cycles"]],
                ["total_c_compare_count", summary["total_c_compare_count"]],
                ["total_c_mismatch_count", summary["total_c_mismatch_count"]],
            ],
        )
    )
    lines.append("")
    lines.append("## Cycle Totals")
    lines.append(
        markdown_table(
            ["Metric", "Total"],
            [
                ["load_cycles", summary["total_load_cycles"]],
                ["compute_cycles", summary["total_compute_cycles"]],
                ["store_cycles", summary["total_store_cycles"]],
            ],
        )
    )
    lines.append("")

    lines.append("## Cases")
    if not case_rows:
        lines.append("No case rows were captured.")
    else:
        lines.append(
            markdown_table(
                ["case_id", "case_name", "m", "n", "k", "cycles", "busy", "cpu_done", "c_mismatch", "result"],
                [
                    [
                        row.get("case_id", ""),
                        row.get("case_name", ""),
                        row.get("m", ""),
                        row.get("n", ""),
                        row.get("k", ""),
                        row.get("cycles", ""),
                        row.get("busy_cycles", ""),
                        row.get("cpu_done", ""),
                        row.get("c_mismatch_count", ""),
                        row.get("result", ""),
                    ]
                    for row in case_rows
                ],
            )
        )
    lines.append("")

    lines.append("## Verilator Warning Summary")
    if warning_counts:
        lines.append(markdown_table(["Type", "Count"], [[kind, warning_counts[kind]] for kind in sorted(warning_counts)]))
    else:
        lines.append("No Verilator warnings, errors, or fatals were found in build.log.")
    lines.append("")

    lines.append("## Raw Warning Log")
    if warning_blocks:
        lines.append("```text")
        lines.append("\n\n".join(warning_blocks))
        lines.append("```")
    else:
        lines.append("No raw Verilator warning blocks were captured.")
    lines.append("")

    lines.append("## Failure Details")
    if not failure_rows:
        lines.append("No failure detail rows.")
    else:
        lines.append(
            markdown_table(
                ["case_id", "case_name", "failure_type", "location", "expected", "actual", "cycle", "detail"],
                [
                    [
                        row.get("case_id", ""),
                        row.get("case_name", ""),
                        row.get("failure_type", ""),
                        row.get("location", ""),
                        row.get("expected", ""),
                        row.get("actual", ""),
                        row.get("cycle", ""),
                        row.get("detail", ""),
                    ]
                    for row in failure_rows
                ],
            )
        )
    lines.append("")

    lines.append("## Reproduction")
    lines.append("```bash")
    lines.append(metadata["reproduction_command"])
    lines.append("```")
    lines.append("")

    lines.append("## Artifacts")
    lines.append(
        markdown_table(
            ["Artifact", "Path"],
            [
                ["metadata", "metadata.json"],
                ["summary", "summary.json"],
                ["case results", "case_results.tsv"],
                ["failure details", "failure_details.tsv"],
                ["warning summary", "warning_summary.tsv"],
                ["build log", "build.log"],
                ["run log", "run.log"],
            ],
        )
    )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run rtl_v2 CPU-driven GEMM system verification")
    parser.add_argument("--rtl-dir", type=Path, default=Path("rtl_v2"))
    parser.add_argument("--results-root", type=Path, default=Path("sim/results"))
    parser.add_argument("--run-id", default=None)
    parser.add_argument("--build-dir", type=Path, default=BUILD_DIR)
    parser.add_argument("--mac-mode", type=int, default=4)
    parser.add_argument("--jobs", default="0")
    parser.add_argument("--trace-fst", action="store_true")
    parser.add_argument("--no-clean-build", dest="clean_build", action="store_false")
    parser.set_defaults(clean_build=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    build_dir = project_path(args.build_dir)
    try:
        validate_build_dir(build_dir)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    results_root = project_path(args.results_root)
    requested_run_id = args.run_id or f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_system_v2"
    run_id, result_dir = allocate_result_dir(results_root, requested_run_id)

    build_log = result_dir / "build.log"
    run_log = result_dir / "run.log"
    warning_summary = result_dir / "warning_summary.tsv"
    metadata_path = result_dir / "metadata.json"
    summary_path = result_dir / "summary.json"
    report_path = result_dir / "report.md"

    try:
        build_cmd = build_command(args)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.clean_build:
        clean_build_dir(build_dir)
    build_dir.parent.mkdir(parents=True, exist_ok=True)

    print(f"[RUN_ID] {run_id}")
    print(f"[RESULT_DIR] {cmd_path(result_dir)}")
    print("[BUILD] " + " ".join(build_cmd))
    build_rc = run_command(build_cmd, build_log)

    run_cmd: list[str] | None = None
    run_rc: int | None = None
    if build_rc == 0:
        run_cmd = simulation_command(args, run_id, result_dir)
        print("[SIM] " + " ".join(run_cmd))
        run_rc = run_command(run_cmd, run_log)
    else:
        run_log.write_text("simulation skipped because Verilator build failed\n", encoding="utf-8")

    build_text = build_log.read_text(encoding="utf-8", errors="replace")
    warning_counts, warning_blocks = parse_log_counts(build_text)
    write_warning_summary(warning_summary, warning_counts)

    case_rows = read_tsv(result_dir / "case_results.tsv")
    failure_rows = read_tsv(result_dir / "failure_details.tsv")
    summary = build_summary(case_rows, build_rc, run_rc)
    write_json(summary_path, summary)

    reproduction = "python3 sim/scripts/run_gemm_system_verification.py"
    reproduction += f" --rtl-dir {cmd_path(project_path(args.rtl_dir))}"
    reproduction += f" --mac-mode {args.mac_mode}"
    if args.trace_fst:
        reproduction += " --trace-fst"

    metadata = {
        "run_id": run_id,
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "top_module": "gemm_system_top",
        "testbench": TB_TOP,
        "tb_file": cmd_path(project_path(TB_FILE)),
        "rtl_dir": cmd_path(project_path(args.rtl_dir)),
        "mac_mode": args.mac_mode,
        "result_dir": cmd_path(result_dir),
        "verilator_version": command_output(["verilator", "--version"]),
        "git_commit": git_output(["git", "rev-parse", "--short", "HEAD"]),
        "git_status": git_output(["git", "status", "--short"]),
        "build_command": build_cmd,
        "simulation_command": run_cmd,
        "reproduction_command": reproduction,
        "clean_build": args.clean_build,
    }
    write_json(metadata_path, metadata)

    generate_report(report_path, metadata, summary, warning_counts, warning_blocks, case_rows, failure_rows)

    print(f"[REPORT] {cmd_path(report_path)}")
    all_passed = (
        build_rc == 0
        and run_rc == 0
        and summary["total_cases"] != 0
        and summary["failed_cases"] == 0
    )
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
