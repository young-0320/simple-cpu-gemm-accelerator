# Simple CPU GEMM Accelerator

디지털회로설계및언어 Project2

Project1에서 설계한 Simple CPU를 확장해, CPU가 MMIO로 제어하는 int8 GEMM co-processor를 구현하고 검증한 repository다. Verilator 기반 transactional verification, Oasys/Nitro ASIC 합성·P&R 분석, Zybo Z7-20 FPGA 검증까지 Project2 1~3번 항목을 모두 포함한다.

Project1 GitHub URL: https://github.com/young-0320/simple-cpu-smart-doorlock

설계·검증·ASIC/FPGA 분석·결론을 모두 종합한 최종 보고서는 [docs/reports/GEMM_accelerator_project2_report.md](docs/reports/GEMM_accelerator_project2_report.md)에 있다.

> **실행 환경**: Python 3.8+ (표준 라이브러리만 사용, 별도 패키지 설치 불필요), Verilator.

## 작업 흐름 요약

1. [Golden vector 생성](#1-golden-vector-생성)
2. [Quick verification](#2-quick-verification)
3. [Oasys 합성](#3-oasys-합성)
4. [Nitro PnR](#4-nitro-pnr)
5. [FPGA 검증](#5-fpga-검증)

## 1. Golden Vector 생성

`model/python/gen_gemm_vectors.py`가 Python golden model(`golden_gemm.py`)로 SystemVerilog testbench가 읽을 vector를 생성한다. Random/Directed/Mixed 세 모드가 있다.

```bash
# Directed (model/gemm_directed_cases.json 기준) -> sim/vectors/directed_case/
python3 model/python/gen_gemm_vectors.py --directed-file model/gemm_directed_cases.json

# Random valid 50개 + invalid 20개 -> sim/vectors/random_case/
python3 model/python/gen_gemm_vectors.py --seed 20260603

# Mixed (directed + random valid 50개 + invalid 20개) -> sim/vectors/mixed_case/
python3 model/python/gen_gemm_vectors.py --directed-file model/gemm_directed_cases.json --seed 20260603
```

각 출력 디렉토리에 `manifest.json`(상세 metadata), `cases.tsv`(testbench가 읽는 case table), `*_init.mem`/`*_expected.mem`(4096-word memory image)가 생성된다. 옵션과 directed file 포맷은 [model/README.md](model/README.md)를 본다.

## 2. Quick Verification

아래 명령은 repository root에서 실행한다.

```bash
python3 sim/scripts/run_gemm_regression.py --target rtl --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_AT --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_v2 --jobs 1
python3 sim/scripts/run_gemm_system_verification.py --jobs 1
```

벡터 생성부터 위 회귀 전체와 Python 단위테스트까지 한 번에 돌리려면
`python3 run_all.py` 하나로 충분하다(CI가 실행하는 것과 동일, [.github/workflows/ci.yml](.github/workflows/ci.yml) 참고).

regression 명령은 배치 요약을 `sim/results/regression/<batch_id>/`의 `report.md`/`summary.tsv`에 남기고, 개별 run은 `sim/results/<vector_set>/<run_id>/` 아래에 `report.md`, `summary.json`, `case_results.tsv`, `warning_summary.tsv`, build/run log를 생성한다.

자세한 실행법은 [sim/README.md](sim/README.md)를 본다.

## Verification Summary

현재 표준 검증 구성은 다음과 같다.

| Target        | RTL                          | Testbench                | 검증 내용                                          |
| ------------- | ---------------------------- | ------------------------ | -------------------------------------------------- |
| `rtl`       | `rtl/gemm_accelerator`     | `single`               | single-port GEMM transaction 검증, `MAC_MODE=1/4` |
| `rtl_AT`    | `rtl_AT/gemm_accelerator`  | `compat`               | `MEMORY_PORTS` 호환형 GEMM top 검증, Adder-Tree(AT, `MAC_MODE=0`) datapath 검증 |
| `rtl_v2`    | `rtl_v2/gemm_accelerator`  | `dual`                 | fixed dual-port GEMM top 검증                      |
| `system_v2` | `rtl_v2/gemm_system_top.v` | `tb_gemm_system_v2.sv` | CPU-driven system-level 통합 검증                  |

최종 검증 report는 [docs/reports/project2_gemm_verification_report.md](docs/reports/project2_gemm_verification_report.md)에 정리되어 있다.

## 3. Oasys 합성

Generic 250nm 라이브러리로 clock period를 sweep해 논리합성 가능한 동작점을 찾는다. 실행 가이드와 합성 target/config 네이밍 규칙은 [asic/oasys/README.md](asic/oasys/README.md)를 본다.

**결과 요약**: accelerator-only(step1/step2)는 15 ns(66.7 MHz)에서 margin 25~26%로 pass(`MAC_MODE=1/4`), Adder-Tree(`MAC_MODE=0`)는 20 ns(margin 32.5%)를 권장 동작점으로 선택했다. CPU+GEMM 통합 시스템(step3, 256-word 데모)은 30 ns에서 margin 43.7%로 pass했고, 이 단계에서부터 critical path가 GEMM datapath가 아니라 CPU ALU 경로(`inst_reg`→accumulator)로 확인됐다. mode별 전체 sweep 수치는 `asic/oasys/results/step{1,2,3}/mode*_sweep_summary.md`에, 메모리 구조(dual/single) 비교 결론은 [docs/reports/speed_power_architecture_comparison_report.md](docs/reports/speed_power_architecture_comparison_report.md)에 정리되어 있다.

## 4. Nitro PnR

Oasys 합성 결과를 입력으로 place & route를 수행하고 post-route timing을 확인한다. 실행 가이드는 [asic/nitro/README.md](asic/nitro/README.md)를 본다.

**결과 요약**: step1/2/3 모든 mode 조합에서 post-route WNS가 양수로 timing을 만족했다(예: step1 1-MAC +846ps/5.6%, step3 데모 1-MAC +8,643ps/28.8%). area·leaf cell 수·net 수·utilization 등 물리적 구현 품질로 비교하면 step2(single-memory)가 더 작고 정돈된 결과를 보여 이 기준에서는 step2를 최종 후보로 채택했다 — 자세한 비교는 [docs/reports/nitro_step1_step2_comparison_report.md](docs/reports/nitro_step1_step2_comparison_report.md)에 정리되어 있다. 단, 속도·전력(에너지) 기준으로는 dual-memory+4-MAC이 더 우수하다는 다른 결론이 나오는데, 그 이유는 [docs/reports/speed_power_architecture_comparison_report.md](docs/reports/speed_power_architecture_comparison_report.md) 5절에 정리되어 있다. `project2.md` 과제 원문이 명시한 평가 기준이 속도·전력이므로, 본 레포지토리는 최종적으로 dual-memory+4-MAC(`rtl_v2`)을 대표 구성으로 채택했다 — Nitro 비교(single-memory 우위)는 물리적 구현 품질이라는 별도 기준에서의 참고 결론이다.

## 5. FPGA 검증

Zybo Z7-20(`xc7z020clg400-1`)에 `rtl_v2/gemm_system_top.v`를 그대로 합성·구현하고, MMCM(Clocking Wizard)으로 보드 오실레이터(125 MHz)를 회로 동작 주파수로 분주해 실물 보드에서 동작을 확인한다. 빌드/스윕 스크립트와 BRAM 초기화 hex 생성 절차는 [fpga/README.md](fpga/README.md)를 본다.

**결과 요약**: `MAC_MODE=1/4` 모두 12 ns(83.3 MHz)까지 timing pass, 11 ns(90.9 MHz)부터 fail했다. margin 10~20%대인 가장 빠른 지점은 두 mode 모두 15 ns(66.7 MHz)로 수렴해 권장 동작점으로 선정했다. 모든 sweep 지점에서 Block RAM Tile = 4(RAMB36E1 4개)로 정상 매핑됨을 확인했고, MMCM(125→66.7 MHz)을 추가해 실물 보드에서 2×2 GEMM 연산이 정상 종료(`led[3]` 점등)함을 확인했다. 자세한 sweep 표는 [fpga/reports/mode1/sweep_summary_mode1.md](fpga/reports/mode1/sweep_summary_mode1.md), [fpga/reports/mode4/sweep_summary_mode4.md](fpga/reports/mode4/sweep_summary_mode4.md)에 있다.

## Design Specification

기준 연산은 `C = A x B`이다.

| 항목                 | 내용                                    |
| -------------------- | --------------------------------------- |
| Matrix shape         | A:`M x K`, B: `K x N`, C: `M x N` |
| Supported dimensions | `1 <= M,N,K <= 4`                     |
| Input type           | signed int8                             |
| Output type          | signed int32                            |
| A/B memory format    | 32-bit word에 signed int8 4개 packing   |
| C memory format      | 32-bit word당 signed int32 1개          |
| Addressing           | word address                            |
| CPU control          | MMIO register write/read                |

Invalid dimension은 GEMM data phase를 시작하지 않고 `done=1`, `error=1`, `invalid_size=1` 상태로 종료해야 한다.

## Repository Layout

| 경로              | 내용                                                                 |
| ----------------- | -------------------------------------------------------------------- |
| `rtl/`          | baseline GEMM accelerator and simple CPU integration                 |
| `rtl_AT/`       | `MEMORY_PORTS` 호환형 GEMM accelerator variant                     |
| `rtl_v2/`       | fixed dual-port GEMM accelerator와 대표 system integration target    |
| `model/`        | Python golden model and vector generator                             |
| `sim/`          | SystemVerilog/C++ testbench, verification runners, generated vectors |
| `sw/`           | Simple CPU assembly programs and assembler tool                      |
| `docs/spec/`    | 설계 contract와 interface specification                              |
| `docs/reports/` | 검증 결과 report                                                     |
| `asic/`         | ASIC synthesis 관련 작업 공간                                       |
| `fpga/`         | FPGA 관련 작업 공간                                                 |

## Important Documents

| 문서                                                                                                | 역할                                               |
| --------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| [docs/project2.md](docs/project2.md)                                                                   | Project2 요구사항                                  |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)                                                           | 팀 협업 규칙 (폴더 배치 기준, 파일 네이밍 규칙, Git 커밋 컨벤션) |
| [docs/reports/GEMM_accelerator_project2_report.md](docs/reports/GEMM_accelerator_project2_report.md)   | Project2 최종 종합 보고서 (설계/검증/ASIC·FPGA 분석/결론) |
| [docs/spec/gemm_accelerator.md](docs/spec/gemm_accelerator.md)                                         | GEMM accelerator architecture and transaction flow |
| [docs/spec/interface_cpu_gemm.md](docs/spec/interface_cpu_gemm.md)                                     | CPU-facing MMIO register contract                  |
| [docs/spec/interface_gemm_memory.md](docs/spec/interface_gemm_memory.md)                               | GEMM-memory interface contract                     |
| [docs/spec/data_memory.md](docs/spec/data_memory.md)                                                   | A/B/C memory layout                                |
| [docs/spec/simple_cpu.md](docs/spec/simple_cpu.md)                                                     | Simple CPU integration responsibility              |
| [sim/README.md](sim/README.md)                                                                         | Simulation and verification usage                  |
| [docs/reports/project2_gemm_verification_report.md](docs/reports/project2_gemm_verification_report.md) | Project2 item 1 verification report                |
| [docs/reports/speed_power_architecture_comparison_report.md](docs/reports/speed_power_architecture_comparison_report.md) | 속도·전력(에너지) 기준 dual/single memory × 1-MAC/4-MAC 비교 |
| [docs/reports/nitro_step1_step2_comparison_report.md](docs/reports/nitro_step1_step2_comparison_report.md) | Nitro P&R 물리적 구현 품질 기준 dual/single memory 비교 |
| [docs/log/verification_method_revision.md](docs/log/verification_method_revision.md) | single/dual-port 검증 방식 전환 배경과 phase별 cycle 비교 결정 기록 |
| [docs/log/golden_model_decisions.md](docs/log/golden_model_decisions.md) | golden model/vector generator 역할 분리와 산출물 형식 결정 기록 |

## Waveform

Waveform이 필요하면 검증 명령에 `--trace-fst` 또는 `--trace-vcd`를 추가한다.

```bash
python3 sim/scripts/run_gemm_system_verification.py --jobs 1 --trace-fst
```

생성된 `.fst` 파일은 GTKWave로 확인한다.

```bash
gtkwave sim/results/system_v2/<run_id>/tb_gemm_system_v2.fst
```

Waveform은 pass/fail 판정 자체보다는 CPU MMIO sequence, GEMM busy/state transition, memory access 흐름을 설명하는 증빙으로 사용한다.

### VCD (ASIC power 분석용)

`--trace-vcd`는 GTKWave 확인용이 아니라, Oasys/Nitro의 switching-activity 기반 power 추정에 입력으로 넣을 실제 toggle 데이터를 뽑기 위한 옵션이다. `--trace-fst`와 동시에 쓸 수 없고, 결과 위치도 `sim/results/system_v2/`가 아니라 `sim/results/power/<run_id>/`로 바뀐다. `<run_id>`는 `step3_mode<N>_<case-name>` 형식으로 자동 지정된다(`--run-id`로 직접 지정 가능).

```bash
# system-level(step3) VCD: sim/results/power/step3_mode1_directed4x4x4/tb_gemm_system_v2.vcd
python3 sim/scripts/run_gemm_system_verification.py --mac-mode 1 --trace-vcd

# accelerator-only(step2) VCD: run_gemm_verification.py로 직접 실행, sim/results/power/step2_mode1_directed006/tb_gemm_vectors_single.vcd
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl/gemm_accelerator --vector-dir sim/vectors/directed_case \
  --tb single --mac-mode 1 --trace-vcd --case-name directed_006
```

`run_gemm_regression.py --target ...` 래퍼는 `--trace-vcd`를 지원하지 않으므로, VCD가 필요하면 위처럼 `run_gemm_verification.py`/`run_gemm_system_verification.py`를 직접 호출한다. 생성된 `.vcd`를 Oasys `config.tcl`의 `vcd_file`/`vcd_scope`에 연결해 실측 power를 뽑는 전체 절차는 [asic/README.md](asic/README.md)를 본다.

## Team And Roles

2조: 박성모, 유경민, 한영웅

| 구분                         | 담당           | 역할                                                                                                            |
| ---------------------------- | -------------- | --------------------------------------------------------------------------------------------------------------- |
| Item 1 RTL 설계/구현         | 박성모, 유경민 | GEMM accelerator RTL 구현, CPU-GEMM MMIO integration, memory interface 구조 개선                                |
| Item 1 검증/문서화           | 한영웅         | Python golden model, vector generation, SystemVerilog testbench, regression runner, waveform/report 산출물 정리 |
| Item 2 Oasys/Nitro 합성 분석 | 박성모, 유경민, 한영웅      | `rtl_v2` 대표 target 기준 synthesis/PNR 환경 구성, area/timing/power report 분석                              |
| Item 3 FPGA 합성/스윕 분석   | 한영웅         | BRAM 초기화 hex 생성, Vivado 빌드/스윕 스크립트 작성, synthesis/implementation 실행, timing/power/utilization 분석 |
| Item 3 FPGA 보드 구현        | 박성모, 유경민 | XDC 제약(`Zybo-Z7.xdc`), Clocking Wizard(MMCM) 분주 IP 설계, 실물 보드 LED 데모    |     