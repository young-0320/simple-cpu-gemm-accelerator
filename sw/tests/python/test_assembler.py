from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[3] / "sw" / "tools"
sys.path.insert(0, str(TOOLS_DIR))

from assembler import (  # noqa: E402
    AssemblerError,
    assemble,
    assemble_file,
    assemble_line,
    parse_labels,
)

REPO_ROOT = Path(__file__).resolve().parents[3]


def decode(word):
    """Inverse of assemble_line's bit layout, for round-trip checks."""
    bits = format(int(word, 16), "032b")
    return {
        "opcode": bits[0:4],
        "addr12": int(bits[20:32], 2),
        "imm28": int(bits[4:32], 2),
        "operand4": int(bits[28:32], 2),
    }


class TestUnknownMnemonic(unittest.TestCase):
    """Bug 1: a typo mnemonic was silently dropped by assemble() but still
    counted by parse_labels(), shifting every later label by one word."""

    def test_typo_mnemonic_raises_in_parse_labels(self):
        lines = ["LOADD 5\n", "LOOP:\n", "  NOP\n"]
        with self.assertRaises(AssemblerError):
            parse_labels(lines)

    def test_typo_mnemonic_raises_in_assemble(self):
        # Even with a hand-built (correct) label_map, assemble() must not
        # silently skip an unknown mnemonic -- the two passes must agree.
        lines = ["LOADD 5\n"]
        with self.assertRaises(AssemblerError):
            assemble(lines, {})

    def test_typo_before_label_no_longer_silently_shifts_the_label(self):
        # Before the fix this produced LOOP=1 with only one real
        # instruction emitted at address 0 -- a label pointing past the
        # end of the program. Now it must fail loudly instead.
        lines = ["LOADD 5\n", "LOOP:\n", "  JMP LOOP\n"]
        with self.assertRaises(AssemblerError):
            parse_labels(lines)


class TestOperandRange(unittest.TestCase):
    """Bug 2: format(dec_val, '0Nb') does not truncate -- an out-of-range
    operand silently widened bin_32 past 32 bits, corrupting the hex word."""

    def test_out_100_reported_bug_raises(self):
        with self.assertRaises(AssemblerError):
            assemble_line("OUT", "100", {})

    def test_4bit_boundary(self):
        self.assertEqual(len(assemble_line("OUT", "15", {})), 8)
        with self.assertRaises(AssemblerError):
            assemble_line("OUT", "16", {})

    def test_12bit_boundary(self):
        self.assertEqual(len(assemble_line("LOAD", "4095", {})), 8)
        with self.assertRaises(AssemblerError):
            assemble_line("LOAD", "4096", {})

    def test_28bit_boundary(self):
        self.assertEqual(len(assemble_line("LOADI", str(2**28 - 1), {})), 8)
        with self.assertRaises(AssemblerError):
            assemble_line("LOADI", str(2**28), {})

    def test_negative_operand_raises_instead_of_corrupting_output(self):
        # format(-1, '04b') == '-1', which used to inject a literal '-'
        # into the middle of the bit string instead of raising.
        with self.assertRaises(AssemblerError):
            assemble_line("OUT", "-1", {})


class TestUnimplementedOpcode(unittest.TestCase):
    """Bug 3: ADDITION is in OPCODE_MAP but assemble_line() has no branch
    for it, so bin_32 was read before assignment (UnboundLocalError)."""

    def test_addition_raises_assembler_error_not_unbound_local(self):
        with self.assertRaises(AssemblerError):
            assemble_line("ADDITION", "0", {})


class TestMalformedOperand(unittest.TestCase):
    """int() failures must surface as AssemblerError (which main() catches
    and prints cleanly), not as a raw ValueError traceback."""

    def test_bad_numeric_operand_raises_assembler_error(self):
        with self.assertRaises(AssemblerError):
            assemble_line("LOADI", "Ox20", {})  # capital O typo, not 0x20

    def test_bad_org_address_raises_assembler_error(self):
        with self.assertRaises(AssemblerError):
            parse_labels(["ORG xyz\n"])
        with self.assertRaises(AssemblerError):
            assemble(["ORG xyz\n"], {})


class TestRoundTrip(unittest.TestCase):
    def test_label_address_round_trips_through_jump_operand(self):
        lines = [
            "LOOP:\n",
            "  NOP\n",
            "  JZ LOOP\n",
            "  JMP DONE\n",
            "DONE:\n",
            "  NOP\n",
        ]
        label_map = parse_labels(lines)
        codes = assemble(lines, label_map)

        self.assertEqual(label_map["LOOP"], 0)
        self.assertEqual(label_map["DONE"], 3)
        self.assertEqual(decode(codes[1])["addr12"], label_map["LOOP"])
        self.assertEqual(decode(codes[2])["addr12"], label_map["DONE"])

    def test_immediate_and_out_operand_round_trip(self):
        self.assertEqual(decode(assemble_line("LOADI", "0x123", {}))["imm28"], 0x123)
        self.assertEqual(decode(assemble_line("OUT", "8", {}))["operand4"], 8)

    def test_every_encoded_word_is_exactly_32_bits(self):
        for cmd, operand in [
            ("LOAD", "4095"), ("STORE", "0"), ("ADD", "1"), ("SUB", "1"),
            ("CMP", "1"), ("LOADI", str(2**28 - 1)), ("ADDI", "1"),
            ("CMPI", "1"), ("JMP", "1"), ("JZ", "1"), ("JNZ", "1"),
            ("NOP", "0"), ("OUT", "15"), ("IN", "15"), ("SHL", "1"),
            ("SHR", "1"), ("AND", "1"),
        ]:
            word = assemble_line(cmd, operand, {})
            self.assertEqual(len(word), 8, f"{cmd} {operand} -> {word!r}")

    def test_doorlock_program_still_assembles_and_jumps_land_correctly(self):
        asm_path = REPO_ROOT / "sw" / "programs" / "doorlock.asm"
        codes = assemble_file(asm_path)

        with asm_path.open("r", encoding="utf-8") as f:
            label_map = parse_labels(f.readlines())

        # JZ FINISH / JMP POLL / JMP HALT must decode back to the real
        # instruction addresses those labels resolved to.
        jz_finish = decode(codes[16])
        jmp_poll = decode(codes[17])
        jmp_halt = decode(codes[22])
        self.assertEqual(jz_finish["addr12"], label_map["FINISH"])
        self.assertEqual(jmp_poll["addr12"], label_map["POLL"])
        self.assertEqual(jmp_halt["addr12"], label_map["HALT"])
        self.assertTrue(all(len(w) == 8 for w in codes.values()))


if __name__ == "__main__":
    unittest.main()
