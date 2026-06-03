"""Generate deterministic GEMM accelerator test vectors.

The generated files are intended for a SystemVerilog Verilator transaction
bench. Python owns vector generation; the SV bench still drives MMIO
transactions and reads the memory images.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

from golden_gemm import (
    MAX_DIM,
    WORD_MASK,
    GemmTransaction,
    is_valid_transaction,
    row_packed_word_count,
    require_matrix_shape,
    require_signed_int8_matrix,
    run_gemm_transaction,
    write_packed_int8_matrix,
)


MEMORY_WORDS = 4096
DATA_REGION_START = 0x080
DATA_REGION_END = 0xFEF
DEFAULT_VECTOR_ROOT = Path("sim/vectors")
DEFAULT_DIRECTED_OUT_DIR = DEFAULT_VECTOR_ROOT / "directed_case"
DEFAULT_RANDOM_OUT_DIR = DEFAULT_VECTOR_ROOT / "random_case"
DEFAULT_MIXED_OUT_DIR = DEFAULT_VECTOR_ROOT / "mixed_case"
GENERATED_OUTPUT_PATTERNS = (
    "manifest.json",
    "cases.tsv",
    "*_init.mem",
    "*_expected.mem",
)
DEFAULT_RANDOM_VALID_CASES = 50
DEFAULT_RANDOM_INVALID_CASES = 20
MAX_A_WORDS = row_packed_word_count(MAX_DIM, MAX_DIM)
MAX_B_WORDS = row_packed_word_count(MAX_DIM, MAX_DIM)
MAX_C_WORDS = MAX_DIM * MAX_DIM


@dataclass(frozen=True)
class VectorCase:
    name: str
    source: str
    kind: str
    txn: GemmTransaction
    memory_seed: int
    a_matrix: Optional[list[list[int]]] = None
    b_matrix: Optional[list[list[int]]] = None
    directed_label: Optional[str] = None


def format_word(value: int) -> str:
    return f"{value & WORD_MASK:08x}"


def format_addr(value: int) -> str:
    return f"{value & WORD_MASK:08x}"


def stable_seed(value: Any) -> int:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    digest = hashlib.sha256(payload).digest()
    return int.from_bytes(digest[:8], "big")


def parse_int(value: Any, field: str) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        text = value.strip()
        if text.lower().startswith("0x"):
            return int(text, 16)
        if len(text) == 8:
            return int(text, 16)
        return int(text, 10)
    raise ValueError(f"{field} must be an integer")


def words_for_valid_dims(m: int, n: int, k: int) -> tuple[int, int, int]:
    return row_packed_word_count(m, k), row_packed_word_count(k, n), m * n


def words_for_case(txn: GemmTransaction) -> tuple[int, int, int]:
    if is_valid_transaction(txn):
        return words_for_valid_dims(txn.m, txn.n, txn.k)
    return MAX_A_WORDS, MAX_B_WORDS, MAX_C_WORDS


def range_in_data_region(base: int, words: int) -> bool:
    if words <= 0:
        return DATA_REGION_START <= base <= DATA_REGION_END
    return DATA_REGION_START <= base and base + words - 1 <= DATA_REGION_END


def ranges_overlap(base_a: int, words_a: int, base_b: int, words_b: int) -> bool:
    return base_a < base_b + words_b and base_b < base_a + words_a


def validate_bases(txn: GemmTransaction) -> None:
    if not is_valid_transaction(txn):
        return

    sizes = words_for_case(txn)
    bases = (txn.a_base, txn.b_base, txn.c_base)
    for base, words, label in zip(bases, sizes, ("A", "B", "C")):
        if not range_in_data_region(base, words):
            raise ValueError(f"{label}_BASE range is outside the data region")

    for left in range(len(bases)):
        for right in range(left + 1, len(bases)):
            if ranges_overlap(bases[left], sizes[left], bases[right], sizes[right]):
                raise ValueError("A/B/C memory ranges must not overlap")


def choose_base(rng: random.Random, words: int) -> int:
    last_base = DATA_REGION_END - words + 1
    return rng.randrange(DATA_REGION_START, last_base + 1)


def choose_non_overlapping_bases(
    rng: random.Random,
    a_words: int,
    b_words: int,
    c_words: int,
) -> tuple[int, int, int]:
    sizes = (a_words, b_words, c_words)
    for _attempt in range(10_000):
        bases = (
            choose_base(rng, a_words),
            choose_base(rng, b_words),
            choose_base(rng, c_words),
        )
        if all(
            not ranges_overlap(bases[left], sizes[left], bases[right], sizes[right])
            for left in range(len(bases))
            for right in range(left + 1, len(bases))
        ):
            return bases
    raise RuntimeError("failed to place non-overlapping A/B/C ranges")


def build_initial_memory(memory_seed: int) -> dict[int, int]:
    rng = random.Random(memory_seed)
    return {addr: rng.getrandbits(32) for addr in range(MEMORY_WORDS)}


def write_mem_image(path: Path, memory: dict[int, int]) -> None:
    with path.open("w", encoding="ascii") as f:
        for addr in range(MEMORY_WORDS):
            f.write(format_word(memory.get(addr, 0)))
            f.write("\n")


def read_directed_entries(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and isinstance(data.get("cases"), list):
        return data["cases"]
    raise ValueError("directed file must be a JSON list or an object with a cases list")


def get_matrix(entry: dict[str, Any], *names: str) -> Optional[list[list[int]]]:
    for name in names:
        if name in entry:
            matrix = entry[name]
            if matrix is None:
                return None
            if not isinstance(matrix, list):
                raise ValueError(f"{name} must be a matrix list")
            return matrix
    return None


def infer_or_read_dims(
    entry: dict[str, Any],
    a_matrix: Optional[list[list[int]]],
    b_matrix: Optional[list[list[int]]],
) -> tuple[int, int, int]:
    has_explicit_dims = all(field in entry for field in ("m", "n", "k"))
    if has_explicit_dims:
        return (
            parse_int(entry["m"], "m"),
            parse_int(entry["n"], "n"),
            parse_int(entry["k"], "k"),
        )

    if a_matrix is None or b_matrix is None:
        raise ValueError("directed cases without explicit m/n/k must provide A and B")

    a_rows = len(a_matrix)
    a_cols = len(a_matrix[0]) if a_matrix else 0
    b_rows = len(b_matrix)
    b_cols = len(b_matrix[0]) if b_matrix else 0
    if a_cols != b_rows:
        raise ValueError("directed A/B matrix shapes are incompatible")
    return a_rows, b_cols, a_cols


def read_optional_bases(entry: dict[str, Any]) -> Optional[tuple[int, int, int]]:
    fields = ("a_base", "b_base", "c_base")
    present = [field in entry for field in fields]
    if any(present) and not all(present):
        raise ValueError("directed case must provide all or none of a_base/b_base/c_base")
    if not any(present):
        return None
    return (
        parse_int(entry["a_base"], "a_base"),
        parse_int(entry["b_base"], "b_base"),
        parse_int(entry["c_base"], "c_base"),
    )


def build_directed_cases(path: Path) -> list[VectorCase]:
    cases: list[VectorCase] = []
    for index, entry in enumerate(read_directed_entries(path)):
        if not isinstance(entry, dict):
            raise ValueError("each directed case must be a JSON object")

        name = f"directed_{index:03d}"
        label = entry.get("name")
        a_matrix = get_matrix(entry, "a", "a_matrix")
        b_matrix = get_matrix(entry, "b", "b_matrix")
        m, n, k = infer_or_read_dims(entry, a_matrix, b_matrix)
        base_rng = random.Random(stable_seed({"bases": entry, "index": index}))
        memory_seed = parse_int(entry["memory_seed"], "memory_seed") if "memory_seed" in entry else stable_seed({"memory": entry, "index": index})

        txn_without_bases = GemmTransaction(0, 0, 0, m, n, k)
        base_values = read_optional_bases(entry)
        if base_values is None:
            base_values = choose_non_overlapping_bases(base_rng, *words_for_case(txn_without_bases))
        txn = GemmTransaction(base_values[0], base_values[1], base_values[2], m, n, k)
        validate_bases(txn)

        if is_valid_transaction(txn):
            if a_matrix is None or b_matrix is None:
                raise ValueError("valid directed cases must provide A and B matrices")
            require_signed_int8_matrix(a_matrix, "A")
            require_signed_int8_matrix(b_matrix, "B")
            require_matrix_shape(a_matrix, m, k, "A")
            require_matrix_shape(b_matrix, k, n, "B")
        elif a_matrix is not None or b_matrix is not None:
            raise ValueError("invalid directed cases should omit A and B matrices")

        cases.append(
            VectorCase(
                name=name,
                source="directed",
                kind="valid" if is_valid_transaction(txn) else "invalid",
                txn=txn,
                memory_seed=memory_seed,
                a_matrix=a_matrix,
                b_matrix=b_matrix,
                directed_label=label,
            )
        )
    return cases


def random_matrix(rng: random.Random, rows: int, cols: int) -> list[list[int]]:
    return [[rng.randint(-128, 127) for _col in range(cols)] for _row in range(rows)]


def random_valid_dims(rng: random.Random) -> tuple[int, int, int]:
    return rng.randint(1, MAX_DIM), rng.randint(1, MAX_DIM), rng.randint(1, MAX_DIM)


def random_invalid_dims(rng: random.Random) -> tuple[int, int, int]:
    dims = [rng.randint(1, MAX_DIM), rng.randint(1, MAX_DIM), rng.randint(1, MAX_DIM)]
    dims[rng.randrange(3)] = rng.choice([0, MAX_DIM + 1])
    return dims[0], dims[1], dims[2]


def build_random_cases(seed: int, valid_cases: int, invalid_cases: int) -> list[VectorCase]:
    rng = random.Random(seed)
    cases: list[VectorCase] = []

    for _index in range(valid_cases):
        m, n, k = random_valid_dims(rng)
        a_words, b_words, c_words = words_for_valid_dims(m, n, k)
        a_base, b_base, c_base = choose_non_overlapping_bases(rng, a_words, b_words, c_words)
        cases.append(
            VectorCase(
                name=f"random_{len(cases):03d}",
                source="random",
                kind="valid",
                txn=GemmTransaction(a_base, b_base, c_base, m, n, k),
                memory_seed=rng.getrandbits(64),
                a_matrix=random_matrix(rng, m, k),
                b_matrix=random_matrix(rng, k, n),
            )
        )

    for _index in range(invalid_cases):
        m, n, k = random_invalid_dims(rng)
        txn_without_bases = GemmTransaction(0, 0, 0, m, n, k)
        a_base, b_base, c_base = choose_non_overlapping_bases(rng, *words_for_case(txn_without_bases))
        cases.append(
            VectorCase(
                name=f"random_{len(cases):03d}",
                source="random",
                kind="invalid",
                txn=GemmTransaction(a_base, b_base, c_base, m, n, k),
                memory_seed=rng.getrandbits(64),
            )
        )

    return cases


def materialize_case(case: VectorCase, out_dir: Path) -> dict[str, Any]:
    init_memory = build_initial_memory(case.memory_seed)
    if case.a_matrix is not None:
        write_packed_int8_matrix(init_memory, case.txn.a_base, case.a_matrix)
    if case.b_matrix is not None:
        write_packed_int8_matrix(init_memory, case.txn.b_base, case.b_matrix)

    result = run_gemm_transaction(init_memory, case.txn)
    init_mem_name = f"{case.name}_init.mem"
    expected_mem_name = f"{case.name}_expected.mem"
    write_mem_image(out_dir / init_mem_name, init_memory)
    write_mem_image(out_dir / expected_mem_name, result.memory)

    metadata: dict[str, Any] = {
        "name": case.name,
        "source": case.source,
        "kind": case.kind,
        "a_base": format_addr(case.txn.a_base),
        "b_base": format_addr(case.txn.b_base),
        "c_base": format_addr(case.txn.c_base),
        "m": case.txn.m,
        "n": case.txn.n,
        "k": case.txn.k,
        "init_mem": init_mem_name,
        "expected_mem": expected_mem_name,
        "expected_status": result.status.to_dict(),
        "memory_seed": case.memory_seed,
        "a_matrix": case.a_matrix,
        "b_matrix": case.b_matrix,
        "c_matrix": result.c_matrix,
    }
    if case.directed_label is not None:
        metadata["directed_label"] = case.directed_label
    return metadata


def write_cases_tsv(path: Path, cases: list[dict[str, Any]]) -> None:
    headers = [
        "name",
        "init_mem",
        "expected_mem",
        "a_base",
        "b_base",
        "c_base",
        "m",
        "n",
        "k",
        "exp_status",
    ]
    with path.open("w", encoding="ascii") as f:
        f.write("	".join(headers))
        f.write("\n")
        for case in cases:
            row = [
                case["name"],
                case["init_mem"],
                case["expected_mem"],
                case["a_base"],
                case["b_base"],
                case["c_base"],
                str(case["m"]),
                str(case["n"]),
                str(case["k"]),
                case["expected_status"]["word"],
            ]
            f.write("	".join(row))
            f.write("\n")


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")


def clean_generated_outputs(out_dir: Path) -> None:
    for pattern in GENERATED_OUTPUT_PATTERNS:
        for path in out_dir.glob(pattern):
            if path.is_file():
                path.unlink()


def generation_mode(
    directed_file: Optional[Path],
    seed: Optional[int],
    valid_cases: int,
    invalid_cases: int,
) -> str:
    has_directed = directed_file is not None
    has_random = seed is not None and (valid_cases > 0 or invalid_cases > 0)
    if has_directed and has_random:
        return "mixed"
    if has_directed:
        return "directed"
    return "random"


def generate_vectors(
    out_dir: Path,
    directed_file: Optional[Path] = None,
    seed: Optional[int] = None,
    valid_cases: int = 0,
    invalid_cases: int = 0,
) -> dict[str, Any]:
    if valid_cases < 0 or invalid_cases < 0:
        raise ValueError("case counts must be non-negative")
    if (valid_cases or invalid_cases) and seed is None:
        raise ValueError("random cases require --seed")
    if directed_file is None and seed is None:
        raise ValueError("provide --directed-file, --seed, or both")
    if directed_file is None and valid_cases == 0 and invalid_cases == 0:
        raise ValueError("random generation requested no cases")

    out_dir.mkdir(parents=True, exist_ok=True)
    clean_generated_outputs(out_dir)

    vector_cases: list[VectorCase] = []
    if directed_file is not None:
        vector_cases.extend(build_directed_cases(directed_file))
    if seed is not None and (valid_cases or invalid_cases):
        vector_cases.extend(build_random_cases(seed, valid_cases, invalid_cases))
    if not vector_cases:
        raise ValueError("no vector cases were generated")

    case_metadata = [materialize_case(case, out_dir) for case in vector_cases]
    write_cases_tsv(out_dir / "cases.tsv", case_metadata)

    manifest: dict[str, Any] = {
        "schema": "gemm_vectors_v1",
        "mode": generation_mode(directed_file, seed, valid_cases, invalid_cases),
        "seed": seed,
        "directed_file": str(directed_file) if directed_file is not None else None,
        "memory_words": MEMORY_WORDS,
        "data_region": {
            "start": format_addr(DATA_REGION_START),
            "end": format_addr(DATA_REGION_END),
        },
        "random": {
            "valid_cases": valid_cases if seed is not None else 0,
            "invalid_cases": invalid_cases if seed is not None else 0,
        },
        "cases": case_metadata,
    }
    write_manifest(out_dir / "manifest.json", manifest)
    return manifest


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate GEMM accelerator vectors")
    parser.add_argument("--directed-file", type=Path, default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--valid-cases", type=int, default=None)
    parser.add_argument("--invalid-cases", type=int, default=None)
    parser.add_argument("--out-dir", type=Path, default=None)
    return parser


def resolve_case_counts(args: argparse.Namespace) -> tuple[int, int]:
    counts_were_provided = args.valid_cases is not None or args.invalid_cases is not None
    if args.seed is not None and not counts_were_provided:
        return DEFAULT_RANDOM_VALID_CASES, DEFAULT_RANDOM_INVALID_CASES
    return args.valid_cases or 0, args.invalid_cases or 0


def resolve_out_dir(
    args: argparse.Namespace,
    valid_cases: int,
    invalid_cases: int,
) -> Path:
    if args.out_dir is not None:
        return args.out_dir

    has_directed = args.directed_file is not None
    has_random = args.seed is not None and (valid_cases > 0 or invalid_cases > 0)
    if has_directed and has_random:
        return DEFAULT_MIXED_OUT_DIR
    if has_directed:
        return DEFAULT_DIRECTED_OUT_DIR
    return DEFAULT_RANDOM_OUT_DIR


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    valid_cases, invalid_cases = resolve_case_counts(args)

    if valid_cases < 0 or invalid_cases < 0:
        parser.error("case counts must be non-negative")
    if (valid_cases or invalid_cases) and args.seed is None:
        parser.error("--valid-cases/--invalid-cases require --seed")
    if args.directed_file is None and args.seed is None:
        parser.error("provide --directed-file, --seed, or both")
    if args.directed_file is None and valid_cases == 0 and invalid_cases == 0:
        parser.error("random generation requested no cases")

    out_dir = resolve_out_dir(args, valid_cases, invalid_cases)
    manifest = generate_vectors(
        out_dir=out_dir,
        directed_file=args.directed_file,
        seed=args.seed,
        valid_cases=valid_cases,
        invalid_cases=invalid_cases,
    )
    print(f"wrote {len(manifest['cases'])} vector case(s) to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
