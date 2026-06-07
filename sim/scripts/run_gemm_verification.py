#!/usr/bin/env python3
"""Run GEMM Verilator verification and generate report artifacts."""

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

TB_CONFIGS: dict[str, dict[str, Any]] = {
    "dual": {
        "top": "tb_gemm_vectors_dual",
        "tb_file": Path("sim/tb/tb_gemm_vectors_dual.sv"),
        "build_dir": Path("sim/build/gemm_vectors_dual"),
        "dumpfile": "tb_gemm_vectors_dual.fst",
        "supports_reports": True,
    },
    "single": {
        "top": "tb_gemm_vectors_single",
        "tb_file": Path("sim/tb/tb_gemm_vectors_single.sv"),
        "build_dir": Path("sim/build/gemm_vectors_single"),
        "dumpfile": "tb_gemm_vectors_single.fst",
        "supports_reports": True,
    },
}


def project_path(path: Path) -> Path:
    return path if path.is_absolute() else REPO_ROOT / path


def cmd_path(path: Path) -> str:
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def allocate_result_dir(results_root: Path, vector_set: str, run_id: str) -> tuple[str, Path]:
    base = results_root / vector_set / run_id
    candidate = base
    suffix = 1
    while candidate.exists():
        candidate = results_root / vector_set / f"{run_id}_{suffix:02d}"
        suffix += 1
    candidate.mkdir(parents=True)
    return candidate.name, candidate


def run_command(command: list[str], cwd: Path, log_path: Path) -> int:
    try:
        proc = subprocess.run(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as exc:
        output = f"failed to run command: {exc}\n"
        log_path.write_text(output, encoding="utf-8")
        print(output, end="")
        return 127
    log_path.write_text(proc.stdout, encoding="utf-8")
    print(proc.stdout, end="")
    return proc.returncode


def command_output(command: list[str], cwd: Path) -> str:
    try:
        proc = subprocess.run(
            command,
            cwd=cwd,
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


def git_output(command: list[str], cwd: Path) -> str:
    env = os.environ.copy()
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    try:
        proc = subprocess.run(
            command,
            cwd=cwd,
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
    return text if proc.returncode == 0 and text else "unavailable"


def build_command(args: argparse.Namespace, config: dict[str, Any]) -> list[str]:
    rtl_dir = project_path(args.rtl_dir)
    rtl_files = sorted(rtl_dir.glob("*.v"))
    if not rtl_files:
        raise FileNotFoundError(f"no Verilog RTL files found in {rtl_dir}")

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
            cmd_path(project_path(config["build_dir"])),
            f"-I{cmd_path(rtl_dir)}",
            "--top-module",
            config["top"],
            f"-GMAC_MODE={args.mac_mode}",
            cmd_path(project_path(config["tb_file"])),
        ]
    )
    command.extend(cmd_path(path) for path in rtl_files)
    return command


def clean_build_dir(build_dir: Path) -> None:
    resolved_build_dir = build_dir.resolve()
    resolved_repo_root = REPO_ROOT.resolve()
    try:
        resolved_build_dir.relative_to(resolved_repo_root)
    except ValueError as exc:
        raise ValueError(f"refusing to clean build dir outside repository: {build_dir}") from exc
    if resolved_build_dir.exists():
        shutil.rmtree(resolved_build_dir)


def executable_path(config: dict[str, Any]) -> Path:
    exe = project_path(config["build_dir"]) / f"V{config['top']}"
    if exe.exists():
        return exe
    exe_with_suffix = exe.with_suffix(".exe")
    return exe_with_suffix if exe_with_suffix.exists() else exe


def simulation_command(
    args: argparse.Namespace,
    config: dict[str, Any],
    vector_dir: Path,
    vector_set: str,
    run_id: str,
    result_dir: Path,
) -> list[str]:
    command = [executable_path(config).as_posix(), f"+VECTOR_DIR={cmd_path(vector_dir)}"]
    cases_path = vector_dir / "cases.tsv"
    command.append(f"+CASES={cmd_path(cases_path)}")

    if config["supports_reports"]:
        command.extend(
            [
                f"+RESULT_DIR={cmd_path(result_dir)}",
                f"+RUN_ID={run_id}",
                f"+VECTOR_SET={vector_set}",
                f"+DUMPFILE={cmd_path(result_dir / config['dumpfile'])}",
            ]
        )
    return command


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


CYCLE_BREAKDOWN_FIELDS = [
    ("cycles", "total"),
    ("busy_cycles", "busy"),
    ("idle_cycles", "idle"),
    ("load_cycles", "load"),
    ("compute_cycles", "compute"),
    ("store_cycles", "store"),
    ("done_cycles", "done"),
    ("mem_read_cycles", "mem_read"),
    ("mem_write_cycles", "mem_write"),
    ("port_a_read_cycles", "port_a_read"),
    ("port_b_read_cycles", "port_b_read"),
    ("port_a_write_cycles", "port_a_write"),
    ("dual_read_cycles", "dual_read"),
]


def build_summary(rows: list[dict[str, str]], build_rc: int, run_rc: int | None) -> dict[str, Any]:
    total = len(rows)
    passed = sum(1 for row in rows if row.get("result") == "PASS")
    failed = sum(1 for row in rows if row.get("result") == "FAIL")
    timeouts = sum(1 for row in rows if int_field(row, "timeout") != 0)
    total_cycles = sum(int_field(row, "cycles") for row in rows)
    max_cycles = max((int_field(row, "cycles") for row in rows), default=0)
    total_mem_writes = sum(int_field(row, "mem_write_count") for row in rows)
    total_c_mismatches = sum(int_field(row, "c_mismatch_count") for row in rows)
    cycle_breakdown = {}
    for field, label in CYCLE_BREAKDOWN_FIELDS:
        values = [int_field(row, field) for row in rows]
        field_total = sum(values)
        cycle_breakdown[label] = {
            "field": field,
            "total": field_total,
            "avg": (field_total / total) if total else 0.0,
            "max": max(values, default=0),
        }
    return {
        "build_returncode": build_rc,
        "run_returncode": run_rc,
        "total_transactions": total,
        "passed_transactions": passed,
        "failed_transactions": failed,
        "timeout_transactions": timeouts,
        "pass_rate": (passed / total) if total else 0.0,
        "total_cycles": total_cycles,
        "max_cycles": max_cycles,
        "total_mem_write_count": total_mem_writes,
        "total_c_mismatch_count": total_c_mismatches,
        "cycle_breakdown": cycle_breakdown,
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


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
    lines.append("# GEMM Verification Report")
    lines.append("")
    lines.append("## Verification Metadata")
    lines.append(
        markdown_table(
            ["Field", "Value"],
            [
                ["run_id", metadata["run_id"]],
                ["timestamp", metadata["timestamp"]],
                ["testbench", metadata["tb"]],
                ["top_module", metadata["top_module"]],
                ["vector_set", metadata["vector_set"]],
                ["vector_dir", metadata["vector_dir"]],
                ["rtl_dir", metadata["rtl_dir"]],
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
                ["total_transactions", summary["total_transactions"]],
                ["passed_transactions", summary["passed_transactions"]],
                ["failed_transactions", summary["failed_transactions"]],
                ["timeout_transactions", summary["timeout_transactions"]],
                ["pass_rate", f"{summary['pass_rate']:.3f}"],
                ["total_cycles", summary["total_cycles"]],
                ["max_cycles", summary["max_cycles"]],
                ["total_mem_write_count", summary["total_mem_write_count"]],
                ["total_c_mismatch_count", summary["total_c_mismatch_count"]],
            ],
        )
    )
    lines.append("")
    lines.append("## Cycle Breakdown")
    lines.append(
        markdown_table(
            ["Metric", "Total", "Avg/Txn", "Max/Txn"],
            [
                [label, stats["total"], f"{stats['avg']:.2f}", stats["max"]]
                for label, stats in summary["cycle_breakdown"].items()
            ],
        )
    )
    lines.append("")

    slowest_cases = sorted(case_rows, key=lambda row: int_field(row, "cycles"), reverse=True)[:10]
    lines.append("## Slowest Transactions")
    if not slowest_cases:
        lines.append("No transaction rows were captured.")
    else:
        lines.append(
            markdown_table(
                ["txn_id", "txn_name", "m", "n", "k", "cycles", "load", "compute", "store", "mem_read", "mem_write", "dual_read"],
                [
                    [
                        row.get("txn_id", ""),
                        row.get("txn_name", ""),
                        row.get("m", ""),
                        row.get("n", ""),
                        row.get("k", ""),
                        row.get("cycles", ""),
                        row.get("load_cycles", ""),
                        row.get("compute_cycles", ""),
                        row.get("store_cycles", ""),
                        row.get("mem_read_cycles", ""),
                        row.get("mem_write_cycles", ""),
                        row.get("dual_read_cycles", ""),
                    ]
                    for row in slowest_cases
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

    failed_cases = [row for row in case_rows if row.get("result") == "FAIL"]
    lines.append("## Failed Transactions")
    if not failed_cases:
        lines.append("No failed transactions.")
    else:
        lines.append(
            markdown_table(
                ["txn_id", "txn_name", "m", "n", "k", "cycles", "fail_reason"],
                [
                    [
                        row.get("txn_id", ""),
                        row.get("txn_name", ""),
                        row.get("m", ""),
                        row.get("n", ""),
                        row.get("k", ""),
                        row.get("cycles", ""),
                        row.get("fail_reason", ""),
                    ]
                    for row in failed_cases
                ],
            )
        )
    lines.append("")

    lines.append("## Failure Details")
    if not failure_rows:
        lines.append("No failure detail rows.")
    else:
        lines.append(
            markdown_table(
                ["txn_id", "txn_name", "failure_type", "location", "expected", "actual", "cycle", "detail"],
                [
                    [
                        row.get("txn_id", ""),
                        row.get("txn_name", ""),
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
    parser = argparse.ArgumentParser(description="Run GEMM Verilator verification")
    parser.add_argument("--vector-dir", type=Path, default=Path("sim/vectors/directed_case"))
    parser.add_argument("--tb", choices=sorted(TB_CONFIGS), default="single")
    parser.add_argument("--results-root", type=Path, default=Path("sim/results"))
    parser.add_argument("--run-id", default=None)
    parser.add_argument("--rtl-dir", type=Path, default=Path("rtl/gemm_accelerator"))
    parser.add_argument("--mac-mode", type=int, default=4)
    parser.add_argument("--jobs", default="0")
    parser.add_argument("--trace-fst", action="store_true")
    parser.add_argument("--no-clean-build", dest="clean_build", action="store_false")
    parser.set_defaults(clean_build=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    config = TB_CONFIGS[args.tb]
    vector_dir = project_path(args.vector_dir)
    results_root = project_path(args.results_root)
    vector_set = vector_dir.name
    requested_run_id = args.run_id or f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{args.tb}"
    run_id, result_dir = allocate_result_dir(results_root, vector_set, requested_run_id)

    build_log = result_dir / "build.log"
    run_log = result_dir / "run.log"
    warning_summary = result_dir / "warning_summary.tsv"
    metadata_path = result_dir / "metadata.json"
    summary_path = result_dir / "summary.json"
    report_path = result_dir / "report.md"

    try:
        build_cmd = build_command(args, config)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    build_dir = project_path(config["build_dir"])
    if args.clean_build:
        try:
            clean_build_dir(build_dir)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
    build_dir.parent.mkdir(parents=True, exist_ok=True)

    print(f"[RUN_ID] {run_id}")
    print(f"[RESULT_DIR] {cmd_path(result_dir)}")
    print("[BUILD] " + " ".join(build_cmd))
    build_rc = run_command(build_cmd, REPO_ROOT, build_log)

    run_cmd: list[str] | None = None
    run_rc: int | None = None
    if build_rc == 0:
        run_cmd = simulation_command(args, config, vector_dir, vector_set, run_id, result_dir)
        print("[SIM] " + " ".join(run_cmd))
        run_rc = run_command(run_cmd, REPO_ROOT, run_log)
    else:
        run_log.write_text("simulation skipped because Verilator build failed\n", encoding="utf-8")

    build_text = build_log.read_text(encoding="utf-8", errors="replace")
    warning_counts, warning_blocks = parse_log_counts(build_text)
    write_warning_summary(warning_summary, warning_counts)

    case_rows = read_tsv(result_dir / "case_results.tsv")
    failure_rows = read_tsv(result_dir / "failure_details.tsv")
    summary = build_summary(case_rows, build_rc, run_rc)
    write_json(summary_path, summary)

    reproduction = "python3 sim/scripts/run_gemm_verification.py"
    reproduction += f" --vector-dir {cmd_path(vector_dir)} --tb {args.tb}"
    if args.trace_fst:
        reproduction += " --trace-fst"

    metadata = {
        "run_id": run_id,
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "tb": args.tb,
        "top_module": config["top"],
        "tb_file": cmd_path(project_path(config["tb_file"])),
        "rtl_dir": cmd_path(project_path(args.rtl_dir)),
        "vector_set": vector_set,
        "vector_dir": cmd_path(vector_dir),
        "cases_path": cmd_path(vector_dir / "cases.tsv"),
        "result_dir": cmd_path(result_dir),
        "verilator_version": command_output(["verilator", "--version"], REPO_ROOT),
        "git_commit": git_output(["git", "rev-parse", "--short", "HEAD"], REPO_ROOT),
        "git_status": git_output(["git", "status", "--short"], REPO_ROOT),
        "build_command": build_cmd,
        "simulation_command": run_cmd,
        "reproduction_command": reproduction,
        "supports_reports": config["supports_reports"],
        "clean_build": args.clean_build,
    }
    write_json(metadata_path, metadata)

    generate_report(
        report_path,
        metadata,
        summary,
        warning_counts,
        warning_blocks,
        case_rows,
        failure_rows,
    )

    print(f"[REPORT] {cmd_path(report_path)}")
    return 0 if build_rc == 0 and (run_rc == 0 or run_rc is None) else 1


if __name__ == "__main__":
    raise SystemExit(main())
