# GEMM Simulation / Verification

`sim/tb/tb_gemm_vectors_single.sv`와 `sim/tb/tb_gemm_vectors_dual.sv`는 vector set을 transaction 단위로 replay하는 SystemVerilog transaction testbench이다. Generator, mailbox, driver, monitor, scoreboard 흐름으로 분리되어 있으며, DUT는 MMIO register와 external memory interface만 통해 검증한다.

`sim/scripts/run_gemm_verification.py`는 Verilator build, simulation 실행, log capture, warning parsing, report 생성을 한 번에 수행하는 verification runner이다.

## 실행 모드

| 모드       | Testbench                    | 용도                                            | Report 지원 |
| ---------- | ---------------------------- | ----------------------------------------------- | ----------- |
| `single` | `tb_gemm_vectors_single.sv` | single-port transaction-level 검증 기본 모드 | Yes         |
| `dual`   | `tb_gemm_vectors_dual.sv`   | dual-port memory interface transaction-level 검증 | Yes         |

기본 모드는 `single`이다. 보고서 산출물은 `single`, `dual` 모드에서 모두 생성한다.

## 표준 실행 예시

아래 명령은 repository root로 이동한 뒤 실행한다.

Directed vector set 검증:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/directed_case
```

Random vector set 검증:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/random_case
```

Mixed vector set 검증:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/mixed_case
```

Run id를 직접 지정:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/directed_case \
  --run-id demo_directed_single
```

Dual-port rtl_AT 검증:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl_AT/gemm_accelerator \
  --vector-dir sim/vectors/mixed_case \
  --tb dual \
  --mac-mode 0
```

Waveform까지 생성:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/directed_case \
  --trace-fst
```

## 주요 옵션

| 옵션                 | 기본값                        | 설명                                                     |
| -------------------- | ----------------------------- | -------------------------------------------------------- |
| `--vector-dir`     | `sim/vectors/directed_case` | `cases.tsv`와 `.mem` 파일이 있는 vector set 디렉토리 |
| `--tb`             | `single`                    | 사용할 testbench: `single` 또는 `dual`                |
| `--results-root`   | `sim/results`               | 검증 산출물 root 디렉토리                                |
| `--run-id`         | 실행 시각 기반 자동 생성      | 한 번의 검증 실행을 구분하는 이름                        |
| `--rtl-dir`        | `rtl/gemm_accelerator`      | Verilator에 넘길 GEMM RTL 디렉토리                       |
| `--mac-mode`       | `4`                         | `MAC_MODE` parameter 값                                |
| `--jobs`           | `0`                         | Verilator build parallel job 수                          |
| `--trace-fst`      | off                           | FST waveform 생성                                        |
| `--no-clean-build` | off                           | 기존 `sim/build/...`를 재사용                          |

Runner는 기본적으로 clean build를 수행한다. 이렇게 해야 `build.log`에 Verilator warning이 매 실행마다 다시 기록되고, warning summary가 재현 가능하게 생성된다. 빠른 반복 실행이 필요하면 `--no-clean-build`를 사용할 수 있다.

## 산출물

각 모드의 산출물은 아래 경로에 생성된다.

```text
sim/results/<vector_set>/<run_id>/
```

예:

```text
sim/results/directed_case/20260605_153000_single/
```

각 run 디렉토리에는 다음 파일이 생성된다.

```text
metadata.json
summary.json
case_results.tsv
failure_details.tsv
warning_summary.tsv
build.log
run.log
report.md
tb_gemm_vectors_<tb>.fst
```

`metadata.json`은 run id, vector set, Verilator version, git commit, build/simulation command 같은 실행 metadata를 기록한다.

`summary.json`은 전체 transaction 수, pass/fail 수, timeout 수, cycle 요약, phase별 cycle breakdown, memory write count, C mismatch count를 기록한다.

`case_results.tsv`는 transaction당 한 줄의 검증 결과이다. 주요 컬럼은 `txn_name`, `m/n/k`, `expected_status`, `actual_status`, `cycles`, `busy_cycles`, `load_cycles`, `compute_cycles`, `store_cycles`, `mem_read_cycles`, `mem_write_cycles`, `port_a_read_cycles`, `port_b_read_cycles`, `port_a_write_cycles`, `dual_read_cycles`, `mem_write_count`, `c_compare_count`, `c_mismatch_count`, `timeout`, `result`, `fail_reason`이다.

`failure_details.tsv`는 FAIL transaction의 상세 원인만 기록한다. PASS만 있는 실행에서는 header만 존재한다.

`build.log`는 Verilator build 원본 로그이다. `%Warning-*`, `%Error-*`, `%Fatal-*` 문구는 이 파일에 그대로 남는다.

`warning_summary.tsv`는 `build.log`를 파싱한 warning/error/fatal type별 count이다.

`run.log`는 simulation runtime 요약 로그이다. 각 transaction의 PASS/FAIL, phase별 cycle, memory access count, C mismatch count가 기록된다.

`report.md`는 위 산출물을 사람이 읽기 쉬운 보고서 형태로 묶은 최종 검증 보고서이다. Cycle Breakdown section은 `state_debug`의 baseline phase encoding을 기준으로 집계한다. Dual TB의 port read cycle은 별도 read-enable이 없는 인터페이스 특성상 load phase에서 read가 발생한다고 보고 산출한 관측값이다.

`tb_gemm_vectors_<tb>.fst`는 `--trace-fst`를 사용했을 때 유효한 waveform 파일이다. Trace를 켜지 않은 실행에서는 Verilator가 `$dumpvars`를 무시하므로 waveform 내용이 생성되지 않을 수 있다.

## 결과 해석

정상 실행의 summary 예시는 다음과 같다.

```json
{
  "total_transactions": 56,
  "passed_transactions": 56,
  "failed_transactions": 0,
  "timeout_transactions": 0,
  "pass_rate": 1.0,
  "total_c_mismatch_count": 0
}
```

Invalid dimension transaction은 `done=1`, `error=1`, `invalid_size=1` status를 기대한다. 이 경우 `c_compare_count=0`이고, `mem_write_count=0`이면 invalid input에서 result memory를 건드리지 않았다는 근거가 된다.

Valid GEMM transaction은 `c_compare_count = M * N`이고, `c_mismatch_count=0`이어야 PASS이다.

## Waveform 확인

FST waveform을 생성한 뒤 GTKWave로 확인한다.

```bash
gtkwave sim/results/directed_case/<run_id>/tb_gemm_vectors_<tb>.fst
```

주로 볼 신호는 다음과 같다.

```text
tb_gemm_vectors_<tb>.mmio_*
tb_gemm_vectors_<tb>.mem_*
tb_gemm_vectors_<tb>.busy
tb_gemm_vectors_<tb>.state_debug
tb_gemm_vectors_single.dut.u_fsm.*
tb_gemm_vectors_single.dut.u_lsu.*
tb_gemm_vectors_single.dut.g_mac4.u_mac.*
tb_gemm_vectors_dual.mem_addr_a
tb_gemm_vectors_dual.mem_addr_b
tb_gemm_vectors_dual.mem_en
```

## Vector 생성 후 검증

검증 전에 vector를 새로 생성할 수 있다.

Directed:

```bash
python3 model/python/gen_gemm_vectors.py \
  --directed-file model/gemm_directed_cases.json
```

Mixed:

```bash
python3 model/python/gen_gemm_vectors.py \
  --directed-file model/gemm_directed_cases.json \
  --seed 20260603 \
  --valid-cases 50 \
  --invalid-cases 20
```

생성 후 같은 vector directory를 runner에 넘기면 된다.

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/mixed_case
```

## 테스트

Python golden model과 vector generator 테스트:

```bash
python3 -m unittest discover -s sim/tests/python -p 'test_*.py'
```

Single-port verification runner smoke:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/directed_case \
  --run-id smoke_single
```

Dual-port rtl_AT verification runner smoke:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl_AT/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb dual \
  --mac-mode 0 \
  --run-id smoke_dual_at
```
