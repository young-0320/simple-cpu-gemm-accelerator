"""Golden model for the GEMM accelerator transaction contract.

This module is intentionally dependency-free so it can be used by vector
generators and test harnesses. It does not own CLI parsing, randomness, or file
IO.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


MAX_DIM = 4
WORD_MASK = 0xFFFF_FFFF
BYTE_MASK = 0xFF
INT32_SIGN_BIT = 0x8000_0000
INT32_MOD = 0x1_0000_0000

STATUS_BUSY_BIT = 0
STATUS_DONE_BIT = 1
STATUS_ERROR_BIT = 2
STATUS_INVALID_SIZE_BIT = 3

STATUS_BUSY = 1 << STATUS_BUSY_BIT
STATUS_DONE = 1 << STATUS_DONE_BIT
STATUS_ERROR = 1 << STATUS_ERROR_BIT
STATUS_INVALID_SIZE = 1 << STATUS_INVALID_SIZE_BIT


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

    def to_word(self) -> int:
        return (
            ((self.busy & 1) << STATUS_BUSY_BIT)
            | ((self.done & 1) << STATUS_DONE_BIT)
            | ((self.error & 1) << STATUS_ERROR_BIT)
            | ((self.invalid_size & 1) << STATUS_INVALID_SIZE_BIT)
        )

    def to_dict(self) -> dict[str, int | str]:
        return {
            "word": f"{self.to_word():08x}",
            "busy": self.busy,
            "done": self.done,
            "error": self.error,
            "invalid_size": self.invalid_size,
        }


@dataclass(frozen=True)
class GemmResult:
    status: GemmStatus
    memory: dict[int, int]
    c_matrix: Optional[list[list[int]]] = None


VALID_DONE_STATUS = GemmStatus(busy=0, done=1, error=0, invalid_size=0)
INVALID_SIZE_STATUS = GemmStatus(busy=0, done=1, error=1, invalid_size=1)


def is_valid_dim(value: int) -> bool:
    return 1 <= value <= MAX_DIM


def is_valid_transaction(txn: GemmTransaction) -> bool:
    return is_valid_dim(txn.m) and is_valid_dim(txn.n) and is_valid_dim(txn.k)


def to_signed_int8(value: int) -> int:
    value &= BYTE_MASK
    return value - 0x100 if value & 0x80 else value


def to_uint32(value: int) -> int:
    return value & WORD_MASK


def to_signed_int32(value: int) -> int:
    value &= WORD_MASK
    return value - INT32_MOD if value & INT32_SIGN_BIT else value


def packed_word_count(element_count: int) -> int:
    if element_count < 0:
        raise ValueError("element_count must be non-negative")
    return (element_count + 3) // 4


def matrix_shape(matrix: list[list[int]]) -> tuple[int, int]:
    if not matrix:
        return 0, 0

    cols = len(matrix[0])
    for row in matrix:
        if len(row) != cols:
            raise ValueError("matrix rows must have a consistent length")
    return len(matrix), cols


def require_matrix_shape(
    matrix: list[list[int]],
    rows: int,
    cols: int,
    name: str,
) -> None:
    actual_rows, actual_cols = matrix_shape(matrix)
    if (actual_rows, actual_cols) != (rows, cols):
        raise ValueError(
            f"{name} matrix shape must be {rows}x{cols}, "
            f"got {actual_rows}x{actual_cols}"
        )


def require_signed_int8_matrix(matrix: list[list[int]], name: str) -> None:
    matrix_shape(matrix)
    for row in matrix:
        for value in row:
            if value < -128 or value > 127:
                raise ValueError(f"{name} matrix value {value} is not signed int8")


def flatten_row_major(matrix: list[list[int]]) -> list[int]:
    matrix_shape(matrix)
    return [value for row in matrix for value in row]


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


def write_packed_int8_matrix(
    memory: dict[int, int],
    base: int,
    matrix: list[list[int]],
) -> None:
    values = flatten_row_major(matrix)
    for word_index in range(packed_word_count(len(values))):
        start = word_index * 4
        memory[base + word_index] = pack_int8x4(values[start : start + 4])


def read_int32_matrix(
    memory: dict[int, int],
    base: int,
    rows: int,
    cols: int,
) -> list[list[int]]:
    matrix: list[list[int]] = []
    for row in range(rows):
        matrix_row: list[int] = []
        for col in range(cols):
            matrix_row.append(to_signed_int32(memory.get(base + row * cols + col, 0)))
        matrix.append(matrix_row)
    return matrix


def write_int32_matrix(
    memory: dict[int, int],
    base: int,
    matrix: list[list[int]],
) -> None:
    _rows, cols = matrix_shape(matrix)
    for row, matrix_row in enumerate(matrix):
        for col, value in enumerate(matrix_row):
            memory[base + row * cols + col] = to_uint32(value)


def golden_gemm(a: list[list[int]], b: list[list[int]]) -> list[list[int]]:
    m, k = matrix_shape(a)
    b_rows, n = matrix_shape(b)
    if k != b_rows:
        raise ValueError(f"matrix shapes are incompatible: A is {m}x{k}, B is {b_rows}x{n}")

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


# Compatibility alias for older callers that used the previous function name.
gemm_ref = golden_gemm


def run_gemm_transaction(
    memory: dict[int, int],
    txn: GemmTransaction,
) -> GemmResult:
    expected_memory = dict(memory)

    if not is_valid_transaction(txn):
        return GemmResult(
            status=INVALID_SIZE_STATUS,
            memory=expected_memory,
            c_matrix=None,
        )

    a = read_packed_int8_matrix(expected_memory, txn.a_base, txn.m, txn.k)
    b = read_packed_int8_matrix(expected_memory, txn.b_base, txn.k, txn.n)
    c = golden_gemm(a, b)
    write_int32_matrix(expected_memory, txn.c_base, c)

    return GemmResult(
        status=VALID_DONE_STATUS,
        memory=expected_memory,
        c_matrix=c,
    )
