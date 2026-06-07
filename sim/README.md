# GEMM Simulation / Verification

실제 검증 산출물을 새로 만들 때는 아래 4개 명령을 repository root에서 실행한다.

```bash
python3 sim/scripts/run_gemm_regression.py --target rtl --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_AT --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_v2 --jobs 1
python3 sim/scripts/run_gemm_system_verification.py --jobs 1
```

`sim/scripts/run_gemm_regression.py`는 GEMM accelerator RTL target 하나에 대해 표준 vector 검증 묶음을 실행하는 상위 파이프라인이다. 내부적으로 `run_gemm_verification.py`를 반복 호출해 target별 TB, MAC mode, directed/random/mixed vector set 조합을 실행하고, batch 단위 `report.md`와 `summary.tsv`를 만든다.

개별 실행이 필요하면 `run_gemm_verification.py`로 `single`, `compat`, `dual` vector TB를 직접 실행한다. `rtl_v2/gemm_system_top.v`까지 포함한 CPU-driven 통합 검증은 별도 runner인 `run_gemm_system_verification.py`를 사용한다.

## 표준 검증 파이프라인

아래 명령은 repository root로 이동한 뒤 실행한다.

```bash
python3 sim/scripts/run_gemm_regression.py --target rtl
python3 sim/scripts/run_gemm_regression.py --target rtl_AT
python3 sim/scripts/run_gemm_regression.py --target rtl_v2
```

| Target | RTL dir | TB | MAC mode | Vector set |
| --- | --- | --- | --- | --- |
| `rtl` | `rtl/gemm_accelerator` | `single` | `1`, `4` | directed, random, mixed |
| `rtl_AT` | `rtl_AT/gemm_accelerator` | `compat` | `0` | directed, random, mixed |
| `rtl_v2` | `rtl_v2/gemm_accelerator` | `dual` | `4` | directed, random, mixed |

파이프라인 요약은 `sim/results/regression/<batch_id>/report.md`와 `summary.tsv`에 기록된다. 이 파이프라인은 GEMM accelerator 단독 vector 검증용이며, `system_v2` 통합 TB는 포함하지 않는다.

## Testbench별 사용법

| 구분 | Testbench | Runner | 대표 대상 | 용도 |
| --- | --- | --- | --- | --- |
| `single` | `tb_gemm_vectors_single.sv` | `run_gemm_verification.py` | `rtl/gemm_accelerator` | single-port GEMM transaction 검증 |
| `compat` | `tb_gemm_vectors_compat.sv` | `run_gemm_verification.py` | `rtl_AT/gemm_accelerator` | `MEMORY_PORTS` 호환형 GEMM top 검증 |
| `dual` | `tb_gemm_vectors_dual.sv` | `run_gemm_verification.py` | `rtl_v2/gemm_accelerator` | fixed dual-port GEMM top 검증 |
| `system_v2` | `tb_gemm_system_v2.sv` | `run_gemm_system_verification.py` | `rtl_v2/gemm_system_top.v` | CPU-driven system-level 통합 검증 |

### 1. `single` TB

`single`은 기본 vector TB이다. `rtl/gemm_accelerator`를 single-port memory interface 기준으로 검증한다.

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb single \
  --mac-mode 4
```

`--vector-dir`는 `sim/vectors/directed_case`, `sim/vectors/random_case`, `sim/vectors/mixed_case` 중 하나로 바꿔 실행한다. `rtl` target의 표준 regression은 `MAC_MODE=1/4`와 세 vector set을 모두 돌린다.

### 2. `compat` TB

`compat`은 `MEMORY_PORTS` parameter를 가진 호환형 top을 검증한다. 현재 대표 대상은 `rtl_AT/gemm_accelerator`이다.

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl_AT/gemm_accelerator \
  --vector-dir sim/vectors/mixed_case \
  --tb compat \
  --mac-mode 0
```

`compat` 결과의 `case_results.tsv`에는 공통 cycle 정보에 더해 `port_a_read_cycles`, `port_b_read_cycles`, `port_a_write_cycles`, `dual_read_cycles`가 기록된다.

### 3. `dual` TB

`dual`은 fixed dual-port interface를 가진 GEMM top을 검증한다. 현재 대표 대상은 `rtl_v2/gemm_accelerator`이다.

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl_v2/gemm_accelerator \
  --vector-dir sim/vectors/mixed_case \
  --tb dual \
  --mac-mode 4
```

`dual`은 `MEMORY_PORTS` parameter를 쓰지 않는 fixed dual-port RTL에 맞춘 TB이다. `rtl_v2` GEMM accelerator 단독 검증은 이 TB를 사용한다.

### 4. `system_v2` TB

`system_v2`는 GEMM 단독이 아니라 `rtl_v2/gemm_system_top.v` 전체를 검증한다. TB가 CPU instruction과 A/B data를 shared memory에 preload하고, CPU가 MMIO register write, `CTRL.start`, `GEMM_STATUS` 확인, `CTRL.clear_done` sequence를 실행한다.

```bash
python3 sim/scripts/run_gemm_system_verification.py --jobs 1
```

이 검증은 directed valid 2개, random valid 10개, invalid dimension 6개를 실행한다. Valid case는 C memory를 golden 결과와 비교하고, invalid case는 `done|error|invalid_size` status, C memory 미변경, `load/compute/store_cycles=0`을 확인한다. A/B/C base address는 case별로 달라진다. 결과는 `sim/results/system_v2/<run_id>/report.md`에 기록된다.

Waveform까지 생성하려면 vector TB 명령에 `--trace-fst`를 추가한다.

```bash
python3 sim/scripts/run_gemm_verification.py \
  --vector-dir sim/vectors/directed_case \
  --trace-fst
```

## Vector TB 주요 옵션

| 옵션               | 기본값                      | 설명                                                 |
| ------------------ | --------------------------- | ---------------------------------------------------- |
| `--vector-dir`     | `sim/vectors/directed_case` | `cases.tsv`와 `.mem` 파일이 있는 vector set 디렉토리 |
| `--tb`             | `single`                    | 사용할 testbench: `single`, `compat`, `dual`         |
| `--results-root`   | `sim/results`               | 검증 산출물 root 디렉토리                            |
| `--run-id`         | 실행 시각 기반 자동 생성    | 한 번의 검증 실행을 구분하는 이름                    |
| `--rtl-dir`        | `rtl/gemm_accelerator`      | Verilator에 넘길 GEMM RTL 디렉토리                   |
| `--mac-mode`       | `4`                         | `MAC_MODE` parameter 값                              |
| `--jobs`           | `0`                         | Verilator build parallel job 수                      |
| `--trace-fst`      | off                         | FST waveform 생성                                    |
| `--no-clean-build` | off                         | 기존 `sim/build/...`를 재사용                        |

이 표는 `single`, `compat`, `dual` vector TB runner 기준이다. `system_v2`는 `run_gemm_system_verification.py`를 사용하며 `--tb`와 `--vector-dir`를 받지 않는다.

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

`case_results.tsv`는 transaction당 한 줄의 검증 결과이다. 공통 주요 컬럼은 `txn_name`, `m/n/k`, `expected_status`, `actual_status`, `cycles`, `busy_cycles`, `load_cycles`, `compute_cycles`, `store_cycles`, `mem_read_cycles`, `mem_write_cycles`, `mem_write_count`, `c_compare_count`, `c_mismatch_count`, `timeout`, `result`, `fail_reason`이다. `compat` 모드는 `port_a_read_cycles`, `port_b_read_cycles`, `port_a_write_cycles`, `dual_read_cycles`도 추가로 기록한다.

`failure_details.tsv`는 FAIL transaction의 상세 원인만 기록한다. PASS만 있는 실행에서는 header만 존재한다.

`build.log`는 Verilator build 원본 로그이다. `%Warning-*`, `%Error-*`, `%Fatal-*` 문구는 이 파일에 그대로 남는다.

`warning_summary.tsv`는 `build.log`를 파싱한 warning/error/fatal type별 count이다.

`run.log`는 simulation runtime 요약 로그이다. 각 transaction의 PASS/FAIL, phase별 cycle, memory access count, C mismatch count가 기록된다.

`report.md`는 위 산출물을 사람이 읽기 쉬운 보고서 형태로 묶은 최종 검증 보고서이다. Cycle Breakdown section은 `state_debug`의 baseline phase encoding을 기준으로 집계한다. Dual TB의 port read cycle은 별도 read-enable이 없는 인터페이스 특성상 load phase에서 read가 발생한다고 보고 산출한 관측값이다.

`tb_gemm_vectors_<tb>.fst`는 `--trace-fst`를 사용했을 때 유효한 waveform 파일이다. Trace를 켜지 않은 실행에서는 Verilator가 `$dumpvars`를 무시하므로 waveform 내용이 생성되지 않을 수 있다.

System-level 통합 검증 산출물도 같은 파일 이름을 사용하되 경로는 `sim/results/system_v2/<run_id>/`이다. `case_results.tsv`는 `cpu_done`, `pc_at_done`, `gemm_state_at_done`, `c_compare_count`, `c_mismatch_count`를 포함해 CPU-driven completion과 C memory 비교 결과를 기록한다.

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

Invalid dimension transaction은 `done=1`, `error=1`, `invalid_size=1` status를 기대한다. System-level TB에서는 C result 영역 16 word를 sentinel 값으로 초기화한 뒤 그대로 유지되는지 비교하므로, invalid case의 `c_compare_count=16`, `c_mismatch_count=0`, `load/compute/store_cycles=0`이면 invalid input에서 result memory와 GEMM data phase를 건드리지 않았다는 근거가 된다.

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
tb_gemm_vectors_compat.mem_addr_a
tb_gemm_vectors_compat.mem_addr_b
tb_gemm_vectors_compat.mem_en
tb_gemm_vectors_dual.mem_addr_a
tb_gemm_vectors_dual.mem_addr_b
tb_gemm_vectors_dual.mem_we
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

rtl_AT compatibility verification runner smoke:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl_AT/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb compat \
  --mac-mode 0 \
  --run-id smoke_compat_at
```

Fixed dual-port rtl_v2 verification runner smoke:

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl_v2/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb dual \
  --mac-mode 4 \
  --run-id smoke_dual_v2
```

rtl_v2 system-level verification runner smoke:

```bash
python3 sim/scripts/run_gemm_system_verification.py \
  --run-id smoke_system_v2 \
  --jobs 1
```
