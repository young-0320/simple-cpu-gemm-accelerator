from __future__ import annotations

import sys
import unittest
from pathlib import Path

MODEL_DIR = Path(__file__).resolve().parents[3] / "model" / "python"
sys.path.insert(0, str(MODEL_DIR))

from golden_gemm import (  # noqa: E402
    GemmStatus,
    GemmTransaction,
    pack_int8x4,
    read_int32_matrix,
    read_packed_int8_matrix,
    run_gemm_transaction,
    to_uint32,
    unpack_int8x4,
    write_packed_int8_matrix,
)


class TestGoldenGemm(unittest.TestCase):
    def test_status_word_matches_mmio_bit_contract(self) -> None:
        self.assertEqual(GemmStatus(busy=0, done=1, error=0, invalid_size=0).to_word(), 0x00000002)
        self.assertEqual(GemmStatus(busy=0, done=1, error=1, invalid_size=1).to_word(), 0x0000000E)
        self.assertEqual(GemmStatus(busy=1, done=0, error=0, invalid_size=0).to_word(), 0x00000001)

    def test_packed_int8_matrix_uses_row_based_packing_and_zero_padding(self) -> None:
        memory = {0x100: 0xFFFF_FFFF, 0x101: 0xFFFF_FFFF}
        matrix = [[-1, 2, -3], [4, 5, -6]]

        write_packed_int8_matrix(memory, 0x100, matrix)

        self.assertEqual(memory[0x100], pack_int8x4([-1, 2, -3]))
        self.assertEqual(memory[0x101], pack_int8x4([4, 5, -6]))
        self.assertEqual(unpack_int8x4(memory[0x100]), [-1, 2, -3, 0])
        self.assertEqual(unpack_int8x4(memory[0x101]), [4, 5, -6, 0])
        self.assertEqual(read_packed_int8_matrix(memory, 0x100, 2, 3), matrix)

    def test_valid_transaction_writes_expected_c_matrix(self) -> None:
        memory: dict[int, int] = {}
        a = [[1, -2, 3], [-4, 5, -6]]
        b = [[7, -8], [9, 10], [-11, 12]]
        write_packed_int8_matrix(memory, 0x080, a)
        write_packed_int8_matrix(memory, 0x084, b)
        memory[0x088] = 0xDEAD_BEEF
        txn = GemmTransaction(a_base=0x080, b_base=0x084, c_base=0x088, m=2, n=2, k=3)

        result = run_gemm_transaction(memory, txn)

        self.assertEqual(result.status.to_word(), 0x00000002)
        self.assertEqual(result.c_matrix, [[-44, 8], [83, 10]])
        self.assertEqual(read_int32_matrix(result.memory, 0x088, 2, 2), [[-44, 8], [83, 10]])
        self.assertEqual(result.memory[0x088], to_uint32(-44))

    def test_invalid_dimension_sets_status_and_leaves_memory_unchanged(self) -> None:
        memory = {addr: addr ^ 0xCAFE_BABE for addr in range(0x080, 0x090)}
        txn = GemmTransaction(a_base=0x080, b_base=0x084, c_base=0x088, m=0, n=2, k=3)

        result = run_gemm_transaction(memory, txn)

        self.assertEqual(result.status.to_word(), 0x0000000E)
        self.assertIsNone(result.c_matrix)
        self.assertEqual(result.memory, memory)


if __name__ == "__main__":
    unittest.main()
