#!/usr/bin/env python3
"""Merge an assembled program with A/B matrix data into one $readmemh image.

Packing follows docs/spec/data_memory.md: row-major, 4 signed int8 lanes per
32-bit word, lane 0 = word[7:0] .. lane 3 = word[31:24], remaining lanes in a
row's last word zero-padded.
"""
import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))
from assembler import assemble_file, write_hex


def auto_int(text):
    return int(text, 0)


def parse_values(text):
    return [auto_int(x) for x in text.split(",")]


def pack_matrix(values, rows, cols, base):
    row_words = (cols + 3) // 4
    words = {}
    for r in range(rows):
        for c in range(cols):
            word_addr = base + r * row_words + c // 4
            lane = c % 4
            words[word_addr] = words.get(word_addr, 0) | ((values[r * cols + c] & 0xFF) << (lane * 8))
    return {addr: format(val, "08X") for addr, val in words.items()}


def main():
    parser = argparse.ArgumentParser(description="Merge assembled program + A/B matrix data into one $readmemh hex image")
    parser.add_argument("program", help="input .asm path")
    parser.add_argument("output", help="merged output hex path")
    parser.add_argument("--a-base", type=auto_int, required=True, help="A matrix base word address")
    parser.add_argument("--b-base", type=auto_int, required=True, help="B matrix base word address")
    parser.add_argument("--m", type=int, required=True, help="A rows / C rows")
    parser.add_argument("--n", type=int, required=True, help="B cols / C cols")
    parser.add_argument("--k", type=int, required=True, help="A cols / B rows")
    parser.add_argument("--a", required=True, help="M*K signed int8 values, comma-separated, row-major")
    parser.add_argument("--b", required=True, help="K*N signed int8 values, comma-separated, row-major")
    args = parser.parse_args()

    a_values = parse_values(args.a)
    b_values = parse_values(args.b)
    if len(a_values) != args.m * args.k:
        parser.error(f"--a expects {args.m * args.k} values (M*K), got {len(a_values)}")
    if len(b_values) != args.k * args.n:
        parser.error(f"--b expects {args.k * args.n} values (K*N), got {len(b_values)}")

    machine_codes = assemble_file(args.program)
    machine_codes.update(pack_matrix(a_values, args.m, args.k, args.a_base))
    machine_codes.update(pack_matrix(b_values, args.k, args.n, args.b_base))

    write_hex(machine_codes, args.output)


if __name__ == "__main__":
    main()
