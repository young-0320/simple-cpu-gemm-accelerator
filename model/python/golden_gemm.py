"""Golden model for the GEMM accelerator transaction contract.

This module is intentionally dependency-free so it can be used as a testcase
generator for a SystemVerilog Verilator testbench.
"""

from __future__ import annotations

from dataclasses import dataclass


MAX_DIM = 4
WORD_MASK = 0xFFFF_FFFF
BYTE_MASK = 0xFF


@dataclass(frozen=True)
class GemmTransaction:
    a_base: int
    b_base: int
    c_base: int
    m: int
    n: int
    k: int


@dataclass(frozen=True)
class GemmStatus:
    busy: int
    done: int
    error: int
    invalid_size: int


@dataclass(frozen=True)
class GemmResult:
    status: GemmStatus
    memory: dict[int, int]


def is_valid_dim(value: int) -> bool:
    return 1 <= value <= MAX_DIM


def is_valid_transaction(txn: GemmTransaction) -> bool:
    return is_valid_dim(txn.m) and is_valid_dim(txn.n) and is_valid_dim(txn.k)


def to_signed_int8(value: int) -> int:
    value &= BYTE_MASK
    return value - 0x100 if value & 0x80 else value


def to_uint32(value: int) -> int:
    return value & WORD_MASK


def pack_int8x4(values: list[int]) -> int:
    if len(values) > 4:
        raise ValueError("pack_int8x4 accepts at most four values")

    word = 0
    for lane, value in enumerate(values):
        word |= (value & BYTE_MASK) << (8 * lane)
    return word


def unpack_int8x4(word: int) -> list[int]:
    return [to_signed_int8((word >> (8 * lane)) & BYTE_MASK) for lane in range(4)]


def read_packed_int8_matrix(
    memory: dict[int, int],
    base: int,
    rows: int,
    cols: int,
) -> list[list[int]]:
    matrix: list[list[int]] = []
    for row in range(rows):
        matrix_row: list[int] = []
        for col in range(cols):
            index = row * cols + col
            word = memory.get(base + index // 4, 0)
            matrix_row.append(unpack_int8x4(word)[index % 4])
        matrix.append(matrix_row)
    return matrix


def write_int32_matrix(
    memory: dict[int, int],
    base: int,
    matrix: list[list[int]],
) -> None:
    for row, matrix_row in enumerate(matrix):
        for col, value in enumerate(matrix_row):
            memory[base + row * len(matrix_row) + col] = to_uint32(value)


def gemm_ref(a: list[list[int]], b: list[list[int]]) -> list[list[int]]:
    m = len(a)
    k = len(a[0]) if a else 0
    n = len(b[0]) if b else 0

    c: list[list[int]] = []
    for i in range(m):
        c_row: list[int] = []
        for j in range(n):
            acc = 0
            for kk in range(k):
                acc += to_signed_int8(a[i][kk]) * to_signed_int8(b[kk][j])
            c_row.append(acc)
        c.append(c_row)
    return c


def run_gemm_transaction(
    memory: dict[int, int],
    txn: GemmTransaction,
) -> GemmResult:
    expected_memory = dict(memory)

    if not is_valid_transaction(txn):
        return GemmResult(
            status=GemmStatus(busy=0, done=1, error=1, invalid_size=1),
            memory=expected_memory,
        )

    a = read_packed_int8_matrix(expected_memory, txn.a_base, txn.m, txn.k)
    b = read_packed_int8_matrix(expected_memory, txn.b_base, txn.k, txn.n)
    c = gemm_ref(a, b)
    write_int32_matrix(expected_memory, txn.c_base, c)

    return GemmResult(
        status=GemmStatus(busy=0, done=1, error=0, invalid_size=0),
        memory=expected_memory,
    )
