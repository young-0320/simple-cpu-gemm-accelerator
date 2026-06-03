from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

MODEL_DIR = Path(__file__).resolve().parents[3] / "model" / "python"
sys.path.insert(0, str(MODEL_DIR))

from gen_gemm_vectors import MEMORY_WORDS, build_arg_parser, generate_vectors, main, resolve_case_counts, resolve_out_dir, words_for_valid_dims  # noqa: E402


def read_mem_words(path: Path) -> list[int]:
    return [int(line, 16) for line in path.read_text().splitlines()]


class TestGemmVectorGeneration(unittest.TestCase):
    def test_valid_word_counts_use_row_based_packing(self) -> None:
        self.assertEqual(words_for_valid_dims(m=4, n=2, k=3), (4, 3, 8))

    def test_directed_only_generation_writes_manifest_tsv_and_full_mem(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            directed_file = tmp_path / "directed.json"
            directed_file.write_text(
                json.dumps(
                    [
                        {
                            "name": "small_negative",
                            "m": 1,
                            "n": 1,
                            "k": 2,
                            "a": [[-3, 4]],
                            "b": [[5], [-6]],
                            "a_base": "00000080",
                            "b_base": "00000084",
                            "c_base": "00000088",
                        }
                    ]
                )
            )
            out_dir = tmp_path / "vectors"

            manifest = generate_vectors(out_dir=out_dir, directed_file=directed_file)

            self.assertIsNone(manifest["seed"])
            self.assertEqual(manifest["cases"][0]["name"], "directed_000")
            self.assertEqual(manifest["cases"][0]["directed_label"], "small_negative")
            self.assertEqual(manifest["cases"][0]["expected_status"]["word"], "00000002")
            self.assertEqual(manifest["cases"][0]["c_matrix"], [[-39]])

            cases_tsv = (out_dir / "cases.tsv").read_text().splitlines()
            self.assertEqual(
                cases_tsv[0].split("	"),
                [
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
                ],
            )
            self.assertEqual(
                cases_tsv[1].split("	"),
                [
                    "directed_000",
                    "directed_000_init.mem",
                    "directed_000_expected.mem",
                    "00000080",
                    "00000084",
                    "00000088",
                    "1",
                    "1",
                    "2",
                    "00000002",
                ],
            )

            init_words = read_mem_words(out_dir / "directed_000_init.mem")
            expected_words = read_mem_words(out_dir / "directed_000_expected.mem")
            self.assertEqual(len(init_words), MEMORY_WORDS)
            self.assertEqual(len(expected_words), MEMORY_WORDS)
            self.assertEqual(init_words[0x084], 0x00000005)
            self.assertEqual(init_words[0x085], 0x000000FA)
            self.assertNotEqual(init_words[0x088], expected_words[0x088])
            self.assertEqual(expected_words[0x088], 0xFFFF_FFD9)

    def test_seeded_random_generation_is_reproducible(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            out_a = tmp_path / "a"
            out_b = tmp_path / "b"

            generate_vectors(out_dir=out_a, seed=1234, valid_cases=2, invalid_cases=1)
            generate_vectors(out_dir=out_b, seed=1234, valid_cases=2, invalid_cases=1)

            self.assertEqual((out_a / "cases.tsv").read_text(), (out_b / "cases.tsv").read_text())
            self.assertEqual((out_a / "manifest.json").read_text(), (out_b / "manifest.json").read_text())
            self.assertEqual(
                (out_a / "random_000_init.mem").read_text(),
                (out_b / "random_000_init.mem").read_text(),
            )

    def test_directed_invalid_case_allows_placeholder_bases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            directed_file = tmp_path / "directed_invalid.json"
            directed_file.write_text(
                json.dumps(
                    [
                        {
                            "name": "invalid_size_placeholder_bases",
                            "m": 0,
                            "n": 1,
                            "k": 1,
                            "a_base": "00000000",
                            "b_base": "00000000",
                            "c_base": "00000000",
                        }
                    ]
                )
            )
            out_dir = tmp_path / "vectors"

            manifest = generate_vectors(out_dir=out_dir, directed_file=directed_file)
            case = manifest["cases"][0]

            self.assertEqual(case["kind"], "invalid")
            self.assertEqual(case["expected_status"]["word"], "0000000e")
            self.assertIsNone(case["c_matrix"])
            self.assertEqual(
                (out_dir / "directed_000_init.mem").read_text(),
                (out_dir / "directed_000_expected.mem").read_text(),
            )

    def test_invalid_random_case_has_invalid_status_and_unchanged_memory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "vectors"

            manifest = generate_vectors(out_dir=out_dir, seed=99, valid_cases=0, invalid_cases=1)
            case = manifest["cases"][0]

            self.assertEqual(case["kind"], "invalid")
            self.assertEqual(case["expected_status"]["word"], "0000000e")
            self.assertIsNone(case["c_matrix"])
            self.assertEqual(
                (out_dir / "random_000_init.mem").read_text(),
                (out_dir / "random_000_expected.mem").read_text(),
            )

    def test_generation_cleans_previous_generated_outputs_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "vectors"
            out_dir.mkdir()
            stale_files = [
                out_dir / "manifest.json",
                out_dir / "cases.tsv",
                out_dir / "random_999_init.mem",
                out_dir / "random_999_expected.mem",
            ]
            for path in stale_files:
                path.write_text("stale")
            keep_file = out_dir / "notes.txt"
            keep_file.write_text("keep")

            manifest = generate_vectors(out_dir=out_dir, seed=99, valid_cases=1, invalid_cases=0)

            self.assertEqual(manifest["mode"], "random")
            for path in stale_files[2:]:
                self.assertFalse(path.exists())
            self.assertEqual(keep_file.read_text(), "keep")
            self.assertTrue((out_dir / "manifest.json").exists())
            self.assertTrue((out_dir / "cases.tsv").exists())

    def test_manifest_keeps_seed_near_top(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "vectors"

            generate_vectors(out_dir=out_dir, seed=1234, valid_cases=1, invalid_cases=0)
            manifest_lines = (out_dir / "manifest.json").read_text().splitlines()

            self.assertIn('  "mode": "random",', manifest_lines[:4])
            self.assertIn('  "seed": 1234,', manifest_lines[:5])

    def test_default_out_dir_depends_on_generation_mode(self) -> None:
        parser = build_arg_parser()

        args = parser.parse_args(["--directed-file", "directed.json"])
        valid_cases, invalid_cases = resolve_case_counts(args)
        self.assertEqual(resolve_out_dir(args, valid_cases, invalid_cases), Path("sim/vectors/directed_case"))

        args = parser.parse_args(["--seed", "1234"])
        valid_cases, invalid_cases = resolve_case_counts(args)
        self.assertEqual((valid_cases, invalid_cases), (50, 20))
        self.assertEqual(resolve_out_dir(args, valid_cases, invalid_cases), Path("sim/vectors/random_case"))

        args = parser.parse_args(["--directed-file", "directed.json", "--seed", "1234"])
        valid_cases, invalid_cases = resolve_case_counts(args)
        self.assertEqual(resolve_out_dir(args, valid_cases, invalid_cases), Path("sim/vectors/mixed_case"))

        args = parser.parse_args(["--seed", "1234", "--out-dir", "custom/out"])
        valid_cases, invalid_cases = resolve_case_counts(args)
        self.assertEqual(resolve_out_dir(args, valid_cases, invalid_cases), Path("custom/out"))

    def test_cli_rejects_missing_case_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                with self.assertRaises(SystemExit) as excinfo:
                    main(["--out-dir", str(Path(tmp) / "vectors")])

        self.assertEqual(excinfo.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
