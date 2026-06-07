# Simple CPU GEMM Accelerator

디지털회로설계및언어 Project2

Project1에서 설계한 Simple CPU를 확장해, CPU가 MMIO로 제어하는 int8 GEMM co-processor를 구현하고 검증한다. 현재 repository는 Project2 1번 항목인 Verilator 기반 transactional verification을 중심으로 정리되어 있다.

## Current Status

| 항목                                 | 상태                                               |
| ------------------------------------ | -------------------------------------------------- |
| GEMM accelerator RTL                 | 구현 및 transaction 검증 완료                      |
| CPU-GEMM MMIO integration            | `rtl_v2` 대표 target 기준 system-level 검증 완료 |
| Verilator transactional verification | 완료                                               |
| Oasys/Nitro synthesis analysis       | 진행 예정                                          |
| Zybo Z7-20 FPGA validation           | 진행 예정                                          |

검증 완료의 의미는 `rtl`, `rtl_AT`, `rtl_v2` GEMM accelerator target에 대한 vector regression과 `rtl_v2/gemm_system_top.v` 기준 CPU-driven system-level testbench가 통과했다는 것이다. 실제 FPGA bring-up과 합성 결과 분석까지 완료됐다는 의미는 아니다.

## Quick Verification

아래 명령은 repository root에서 실행한다.

```bash
python3 sim/scripts/run_gemm_regression.py --target rtl --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_AT --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_v2 --jobs 1
python3 sim/scripts/run_gemm_system_verification.py --jobs 1
```

각 명령은 `sim/results` 아래에 `report.md`, `summary.json`, `case_results.tsv`, `warning_summary.tsv`, build/run log를 생성한다.

자세한 실행법은 [sim/README.md](sim/README.md)를 본다.

## Verification Summary

현재 표준 검증 구성은 다음과 같다.

| Target        | RTL                          | Testbench                | 검증 내용                                          |
| ------------- | ---------------------------- | ------------------------ | -------------------------------------------------- |
| `rtl`       | `rtl/gemm_accelerator`     | `single`               | single-port GEMM transaction 검증,`MAC_MODE=1/4` |
| `rtl_AT`    | `rtl_AT/gemm_accelerator`  | `compat`               | `MEMORY_PORTS` 호환형 GEMM top 검증              |
| `rtl_v2`    | `rtl_v2/gemm_accelerator`  | `dual`                 | fixed dual-port GEMM top 검증                      |
| `system_v2` | `rtl_v2/gemm_system_top.v` | `tb_gemm_system_v2.sv` | CPU-driven system-level 통합 검증                  |

최종 검증 report는 [docs/report/project2_gemm_verification_report.md](docs/report/project2_gemm_verification_report.md)에 정리되어 있다.

## Design Scope

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

| 경로             | 내용                                                                 |
| ---------------- | -------------------------------------------------------------------- |
| `rtl/`         | baseline GEMM accelerator and simple CPU integration                 |
| `rtl_AT/`      | `MEMORY_PORTS` 호환형 GEMM accelerator variant                     |
| `rtl_v2/`      | fixed dual-port GEMM accelerator와 대표 system integration target    |
| `model/`       | Python golden model and vector generator                             |
| `sim/`         | SystemVerilog/C++ testbench, verification runners, generated vectors |
| `sw/`          | Simple CPU assembly programs and assembler tool                      |
| `docs/spec/`   | 설계 contract와 interface specification                              |
| `docs/report/` | 검증 결과 report                                                     |
| `asic/`        | ASIC synthesis 관련 작업 공간                                       |
| `fpga/`        | FPGA 관련 작업 공간                                                 |

## Important Documents

| 문서                                                                                              | 역할                                               |
| ------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| [docs/project2.md](docs/project2.md)                                                                 | Project2 요구사항                                  |
| [docs/spec/gemm_accelerator.md](docs/spec/gemm_accelerator.md)                                       | GEMM accelerator architecture and transaction flow |
| [docs/spec/interface_cpu_gemm.md](docs/spec/interface_cpu_gemm.md)                                   | CPU-facing MMIO register contract                  |
| [docs/spec/interface_gemm_memory.md](docs/spec/interface_gemm_memory.md)                             | GEMM-memory interface contract                     |
| [docs/spec/data_memory.md](docs/spec/data_memory.md)                                                 | A/B/C memory layout                                |
| [docs/spec/simple_cpu.md](docs/spec/simple_cpu.md)                                                   | Simple CPU integration responsibility              |
| [sim/README.md](sim/README.md)                                                                       | Simulation and verification usage                  |
| [docs/report/project2_gemm_verification_report.md](docs/report/project2_gemm_verification_report.md) | Project2 item 1 verification report                |

## Waveform

Waveform이 필요하면 검증 명령에 `--trace-fst`를 추가한다.

```bash
python3 sim/scripts/run_gemm_system_verification.py --jobs 1 --trace-fst
```

생성된 `.fst` 파일은 GTKWave로 확인한다.

```bash
gtkwave sim/results/system_v2/<run_id>/tb_gemm_system_v2.fst
```

Waveform은 pass/fail 판정 자체보다는 CPU MMIO sequence, GEMM busy/state transition, memory access 흐름을 설명하는 증빙으로 사용한다.

## Team And Roles

2조: 박성모, 유경민, 한영웅

| 구분                         | 담당           | 역할                                                                                                            |
| ---------------------------- | -------------- | --------------------------------------------------------------------------------------------------------------- |
| Item 1 RTL 설계/구현         | 박성모, 유경민 | GEMM accelerator RTL 구현, CPU-GEMM MMIO integration, memory interface 구조 개선                                |
| Item 1 검증/문서화           | 한영웅         | Python golden model, vector generation, SystemVerilog testbench, regression runner, waveform/report 산출물 정리 |
| Item 2 Oasys/Nitro 합성 분석 | 진행 예정      | `rtl_v2` 대표 target 기준 synthesis/PNR 환경 구성, area/timing/power report 분석                              |
| Item 3 FPGA 검증             | 진행 예정      | Zybo Z7-20 bring-up, FPGA 동작 검증, board-level 속도/전력 비교                                                 |
