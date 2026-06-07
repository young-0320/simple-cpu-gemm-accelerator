#!/usr/bin/env python3
"""Run the standard GEMM verification matrix for one RTL target."""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]

VECTOR_DIRS = (
    Path("sim/vectors/directed_case"),
    Path("sim/vectors/random_case"),
    Path("sim/vectors/mixed_case"),
)


@dataclass(frozen=True)
class TargetConfig:
    rtl_dir: Path
    tb: str
    mac_modes: tuple[int, ...]
    slug: str


TARGETS = {
    "rtl": TargetConfig(
        rtl_dir=Path("rtl/gemm_accelerator"),
        tb="single",
        mac_modes=(1, 4),
        slug="rtl",
    ),
    "rtl_AT": TargetConfig(
        rtl_dir=Path("rtl_AT/gemm_accelerator"),
        tb="compat",
        mac_modes=(0,),
        slug="rtl_at",
    ),
    "rtl_v2": TargetConfig(
        rtl_dir=Path("rtl_v2/gemm_accelerator"),
        tb="dual",
        mac_modes=(4,),
        slug="rtl_v2",
    ),
}


def project_path(path: Path) -> Path:
    return path if path.is_absolute() else REPO_ROOT / path


def cmd_path(path: Path) -> str:
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def allocate_batch_dir(results_root: Path, requested_id: str) -> tuple[str, Path]:
    base = results_root / "regression" / requested_id
    candidate = base
    suffix = 1
    while candidate.exists():
        candidate = results_root / "regression" / f"{requested_id}_{suffix:02d}"
        suffix += 1
    candidate.mkdir(parents=True)
    return candidate.name, candidate


def parse_result_dir(output: str) -> Path | None:
    match = re.search(r"^\[RESULT_DIR\]\s+(.+)$", output, re.MULTILINE)
    if not match:
        return None
    return project_path(Path(match.group(1)))


def read_json(path: Path) -> dict[str, object]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def read_warning_counts(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8", newline="") as f:
        rows = csv.DictReader(f, delimiter="\t")
        return {row["type"]: int(row["count"]) for row in rows}


def format_warnings(warnings: dict[str, int]) -> str:
    if not warnings:
        return ""
    return ";".join(f"{kind}={warnings[kind]}" for kind in sorted(warnings))


def run_one(command: list[str]) -> tuple[int, str]:
    print("[PIPELINE] " + " ".join(command), flush=True)
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
    print(proc.stdout, end="")
    return proc.returncode, proc.stdout


def build_runs(target: str, config: TargetConfig, batch_id: str, args: argparse.Namespace) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    results_root = project_path(args.results_root)

    for vector_dir in VECTOR_DIRS:
        for mac_mode in config.mac_modes:
            child_run_id = f"{batch_id}_{vector_dir.name}_m{mac_mode}"
            command = [
                sys.executable,
                "sim/scripts/run_gemm_verification.py",
                "--rtl-dir",
                config.rtl_dir.as_posix(),
                "--vector-dir",
                vector_dir.as_posix(),
                "--tb",
                config.tb,
                "--mac-mode",
                str(mac_mode),
                "--results-root",
                cmd_path(results_root),
                "--run-id",
                child_run_id,
                "--jobs",
                str(args.jobs),
            ]
            if args.trace_fst:
                command.append("--trace-fst")
            if args.no_clean_build:
                command.append("--no-clean-build")

            returncode, output = run_one(command)
            result_dir = parse_result_dir(output)
            summary = read_json(result_dir / "summary.json") if result_dir else {}
            warnings = read_warning_counts(result_dir / "warning_summary.tsv") if result_dir else {}
            total = int(summary.get("total_transactions", 0))
            passed = int(summary.get("passed_transactions", 0))
            failed = int(summary.get("failed_transactions", 0))
            build_rc = summary.get("build_returncode", "")
            run_rc = summary.get("run_returncode", "")
            ok = returncode == 0 and failed == 0 and total != 0

            rows.append(
                {
                    "target": target,
                    "rtl_dir": config.rtl_dir.as_posix(),
                    "tb": config.tb,
                    "vector_set": vector_dir.name,
                    "mac_mode": mac_mode,
                    "returncode": returncode,
                    "build_returncode": build_rc,
                    "run_returncode": run_rc,
                    "passed": passed,
                    "total": total,
                    "failed": failed,
                    "warnings": format_warnings(warnings),
                    "result": "PASS" if ok else "FAIL",
                    "result_dir": cmd_path(result_dir) if result_dir else "",
                }
            )

    return rows


def write_summary(batch_dir: Path, rows: list[dict[str, object]]) -> None:
    fields = [
        "target",
        "rtl_dir",
        "tb",
        "vector_set",
        "mac_mode",
        "result",
        "passed",
        "total",
        "failed",
        "returncode",
        "build_returncode",
        "run_returncode",
        "warnings",
        "result_dir",
    ]
    with (batch_dir / "summary.tsv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, delimiter="\t", fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    total = len(rows)
    passed = sum(1 for row in rows if row["result"] == "PASS")
    lines = [
        "# GEMM Regression Report",
        "",
        f"- total_runs: {total}",
        f"- passed_runs: {passed}",
        f"- failed_runs: {total - passed}",
        "",
        "| target | vector_set | mac_mode | result | passed/total | warnings | result_dir |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            "| {target} | {vector_set} | {mac_mode} | {result} | {passed}/{total} | {warnings} | {result_dir} |".format(
                **row
            )
        )
    lines.append("")
    (batch_dir / "report.md").write_text("\n".join(lines), encoding="utf-8")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run a GEMM verification pipeline for one RTL target")
    parser.add_argument("--target", choices=sorted(TARGETS), required=True)
    parser.add_argument("--results-root", type=Path, default=Path("sim/results"))
    parser.add_argument("--run-id", default=None, help="batch id prefix; defaults to timestamp_target")
    parser.add_argument("--jobs", default="0")
    parser.add_argument("--trace-fst", action="store_true")
    parser.add_argument("--no-clean-build", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    config = TARGETS[args.target]

    requested_id = args.run_id or f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{config.slug}"
    batch_id, batch_dir = allocate_batch_dir(project_path(args.results_root), requested_id)
    print(f"[BATCH_ID] {batch_id}")
    print(f"[BATCH_DIR] {cmd_path(batch_dir)}")

    rows = build_runs(args.target, config, batch_id, args)
    write_summary(batch_dir, rows)

    passed = sum(1 for row in rows if row["result"] == "PASS")
    total = len(rows)
    print(f"[SUMMARY] pass={passed}/{total}")
    print(f"[REPORT] {cmd_path(batch_dir / 'report.md')}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
