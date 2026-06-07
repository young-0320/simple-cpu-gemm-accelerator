# Project2 Item 1 GEMM Transactional Verification Report

작성일: 2026-06-07

## 1. 검증 목적

Project2 1번 요구사항은 Verilator를 이용해 CPU와 GEMM co-processor를 transaction-level로 검증하는 것이다.

본 검증의 목적은 다음을 확인하는 것이다.

- CPU-facing MMIO transaction으로 GEMM을 설정하고 시작할 수 있는가
- GEMM accelerator가 A/B memory layout을 읽어 `C = A x B`를 계산하고 C memory에 writeback하는가
- valid dimension에서 golden model과 동일한 C 결과를 만드는가
- invalid dimension에서 memory access 없이 `done=1`, `error=1`, `invalid_size=1`로 종료하는가
- 1-MAC baseline, 4-MAC 확장, AT datapath, dual-port memory 구조의 최적화 흐름을 cycle breakdown으로 설명할 수 있는가
- `rtl`, `rtl_AT`, `rtl_v2` 구현 차이에 맞는 testbench로 동일 transaction contract를 검증할 수 있는가

이 문서는 사용법 문서가 아니라 검증 결과 보고서이다. 실행 방법의 상세 설명은 `sim/README.md`가 담당한다.

## 2. 검증 범위

| 구분          | 검증 대상                    | Testbench                | Runner                              | 검증 성격                                    |
| ------------- | ---------------------------- | ------------------------ | ----------------------------------- | -------------------------------------------- |
| `rtl`       | `rtl/gemm_accelerator`     | `single`               | `run_gemm_regression.py`          | GEMM accelerator 단독 transaction 검증       |
| `rtl_AT`    | `rtl_AT/gemm_accelerator`  | `compat`               | `run_gemm_regression.py`          | single/dual memory port 호환형 GEMM top 검증 |
| `rtl_v2`    | `rtl_v2/gemm_accelerator`  | `dual`                 | `run_gemm_regression.py`          | fixed dual-port GEMM top 검증                |
| `system_v2` | `rtl_v2/gemm_system_top.v` | `tb_gemm_system_v2.sv` | `run_gemm_system_verification.py` | CPU-driven system-level 통합 검증            |

`single`, `compat`, `dual`은 GEMM accelerator 단독 검증이다. CPU를 직접 실행하지 않고 TB가 MMIO protocol과 external memory를 transaction 단위로 구동한다.

`system_v2`는 `rtl_v2/gemm_system_top.v`를 대표 system target으로 잡고 CPU instruction memory와 shared data memory를 preload한 뒤, CPU가 MMIO register write, `CTRL.start`, status 확인, `CTRL.clear_done` sequence를 실행하도록 검증한다.

## 3. 검증 트랜잭션

공통 GEMM transaction은 아래 순서로 정의했다.

1. A/B/C base address와 M/N/K dimension을 MMIO register에 기록한다.
2. A/B matrix는 packed int8 memory layout으로 준비한다.
3. `CTRL.start`를 통해 GEMM transaction을 시작한다.
4. GEMM busy 기간 동안 load, compute, store phase가 진행된다.
5. 완료 후 status register와 C memory를 확인한다.
6. C memory는 Python golden model의 int32 GEMM 결과와 비교한다.
7. invalid dimension은 C memory를 sentinel 값으로 초기화한 뒤 변경되지 않았는지 확인한다.

지원 dimension은 `1 <= M,N,K <= 4`이다. invalid transaction은 M/N/K가 0이거나 4를 초과하는 경우를 포함한다.

## 4. 최적화 발전 과정

본 프로젝트의 특정 연산의 최적화 흐름은 다음 순서로 진행됐다.

1. `rtl` 1-MAC baseline으로 가장 단순한 serial GEMM 구조를 검증한다.
2. 같은 memory interface에서 `MAC_MODE=4`로 확장해 compute 병목을 줄인다.
3. `rtl_AT`에서 AT datapath를 검증해 다른 연산 구조의 cycle 특성을 확인한다.
4. `rtl_v2`에서 fixed dual-port memory interface를 적용해 4-MAC 이후 남는 A/B load 병목을 줄인다.
5. 최종적으로 `rtl_v2/gemm_system_top.v`를 대표 target으로 잡아 CPU-driven system-level transaction까지 검증한다.

아래 표는 `mixed_case` 산출물 기준이다. Mixed case는 valid와 invalid transaction을 함께 포함하므로, 성능 해석에는 valid-only average도 같이 기록했다.

| 단계           | 대상                       | 목적                | total cycles | valid avg cycles | load total | compute total | store total |
| -------------- | -------------------------- | ------------------- | -----------: | ---------------: | ---------: | ------------: | ----------: |
| 1-MAC baseline | `rtl`, `MAC_MODE=1`    | serial MAC 기준점   |         5022 |            61.92 |       2161 |          1656 |         676 |
| 4-MAC 확장     | `rtl`, `MAC_MODE=4`    | compute 병목 완화   |         4664 |            57.33 |       2161 |          1307 |         676 |
| AT datapath    | `rtl_AT`, `MAC_MODE=0` | 추가 연산 구조 검증 |         4076 |            49.79 |       2688 |           442 |         442 |
| dual-port v2   | `rtl_v2`, `MAC_MODE=4` | A/B load 병목 완화  |         3886 |            47.36 |       1394 |          1307 |         676 |

1-MAC에서 4-MAC으로 확장하면 같은 `rtl` target과 같은 mixed vector set 기준으로 compute total cycle이 `1656 -> 1307`로 줄었다. 이는 MAC 병렬화가 compute phase 병목을 줄인다는 근거이다. 다만 load total cycle은 `2161`로 그대로 남아 있어, MAC 병렬화 이후에는 memory load가 다음 병목으로 남는다.

`rtl_v2`는 이 병목을 줄이기 위해 fixed dual-port memory interface를 적용한 target이다. `rtl 4-MAC`과 비교하면 compute/store total은 각각 `1307`, `676`으로 같고, load total만 `2161 -> 1394`로 줄었다. 따라서 `rtl_v2`의 cycle 감소는 연산 datapath 자체가 다시 바뀐 효과라기보다 A/B load 병목을 줄인 효과로 해석할 수 있다.

`rtl_AT`는 AT datapath의 별도 연산 구조를 검증하기 위한 target이다. 이 target은 compute/store cycle이 크게 줄어드는 특성을 보였지만, 최종 대표 system-level target은 fixed dual-port 4-MAC 구조인 `rtl_v2`로 잡았다. PPA 전체 최적해 여부는 Project2 2번의 Oasys/Nitro 합성 결과까지 같이 봐야 하므로, 이 문서에서는 Verilator cycle 기준의 최적화 흐름으로만 해석한다.

## 5. 실행 명령

최종 검증 산출물은 repository root에서 아래 네 명령으로 재생성한다.

```bash
python3 sim/scripts/run_gemm_regression.py --target rtl --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_AT --jobs 1
python3 sim/scripts/run_gemm_regression.py --target rtl_v2 --jobs 1
python3 sim/scripts/run_gemm_system_verification.py --jobs 1 --trace-fst --run-id project2_item1_system_v2_trace
```

각 runner는 Verilator build log, simulation log, transaction 결과, warning summary, 사람이 읽을 수 있는 `report.md`를 `sim/results` 아래에 생성한다.

## 6. 결과 요약

아래 표는 2026-06-07에 생성된 최종 산출물을 기준으로 한다.

| Target        | Run group                     | 실행 수 |  Transaction | 결과 | 산출물                                                        |
| ------------- | ----------------------------- | ------: | -----------: | ---- | ------------------------------------------------------------- |
| `rtl`       | `20260607_222646_rtl`       |       6 | 504/504 PASS | PASS | `sim/results/regression/20260607_222646_rtl/report.md`      |
| `rtl_AT`    | `20260607_222703_rtl_at`    |       3 | 252/252 PASS | PASS | `sim/results/regression/20260607_222703_rtl_at/report.md`   |
| `rtl_v2`    | `20260607_222712_rtl_v2`    |       3 | 252/252 PASS | PASS | `sim/results/regression/20260607_222712_rtl_v2/report.md`   |
| `system_v2` | `project2_item1_system_v2_trace` |       1 |   18/18 PASS | PASS | `sim/results/system_v2/project2_item1_system_v2_trace/report.md` |

Accelerator 단독 vector 검증은 총 1008개 transaction을 모두 통과했다. `system_v2` 통합 검증은 valid 12개와 invalid 6개, 총 18개 case를 모두 통과했다.

`system_v2` 최종 report 기준 주요 결과는 다음과 같다.

| 항목                   |    값 |
| ---------------------- | ----: |
| total_cases            |    18 |
| passed_cases           |    18 |
| failed_cases           |     0 |
| timeout_cases          |     0 |
| pass_rate              | 1.000 |
| total_c_compare_count  |   190 |
| total_c_mismatch_count |     0 |

Verilator build warning은 최종 `system_v2` report에서 warning, error, fatal 모두 검출되지 않았다. `rtl`, `rtl_AT`, `rtl_v2` regression report의 warning column도 비어 있다.

## 7. `system_v2` 통합 검증 상세

`system_v2`는 GEMM accelerator만 직접 두드리는 TB가 아니라 `gemm_system_top`을 통해 CPU와 GEMM의 연결을 함께 검증한다.

CPU program은 다음 MMIO sequence를 실행한다.

| 순서 | 동작                                     |
| ---- | ---------------------------------------- |
| 1    | A base address write                     |
| 2    | B base address write                     |
| 3    | C base address write                     |
| 4    | M/N/K dimension write                    |
| 5    | `CTRL.start` write                     |
| 6    | `GEMM_STATUS` polling                  |
| 7    | status 확인 후 `CTRL.clear_done` write |
| 8    | completion marker 출력                   |

Valid case에서는 TB가 C memory를 직접 읽어 golden C와 비교한다. Invalid case에서는 C memory 16 word를 sentinel 값으로 초기화하고, transaction 이후에도 그대로 유지되는지 확인한다. Invalid case의 `load_cycles`, `compute_cycles`, `store_cycles`가 모두 0이면 invalid input에서 GEMM data phase가 시작되지 않았다는 근거가 된다.

현재 invalid coverage는 다음 6개이다.

| Case                   | M | N | K |
| ---------------------- | -: | -: | -: |
| `invalid_m_zero`     | 0 | 2 | 2 |
| `invalid_n_zero`     | 2 | 0 | 2 |
| `invalid_k_zero`     | 2 | 2 | 0 |
| `invalid_m_overflow` | 5 | 2 | 2 |
| `invalid_n_overflow` | 2 | 5 | 2 |
| `invalid_k_overflow` | 2 | 2 | 5 |

## 8. Waveform 확인

Pass/fail의 1차 근거는 scoreboard와 golden memory compare 산출물이다. Waveform은 transaction이 의도한 순서로 진행되는지 설명하기 위한 보조 증빙으로 사용한다.

대표 waveform은 system-level 검증 명령에 `--trace-fst`를 추가해 생성한다. 현재 제출용 대표 waveform 산출물은 아래 경로이다.

```text
sim/results/system_v2/project2_item1_system_v2_trace/tb_gemm_system_v2.fst
```

재생성 명령은 다음과 같다.

```bash
python3 sim/scripts/run_gemm_system_verification.py --jobs 1 --trace-fst --run-id project2_item1_system_v2_trace
```

Vector TB waveform이 필요하면 개별 vector runner에 `--trace-fst`를 추가한다.

```bash
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl_v2/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb dual \
  --mac-mode 4 \
  --trace-fst
```

Waveform에서 우선 확인할 신호는 다음과 같다.

| 구분         | 주요 신호                                 | 확인 목적                                                           |
| ------------ | ----------------------------------------- | ------------------------------------------------------------------- |
| CPU progress | `pc_debug`, `acc_debug`, `out_port` | CPU가 MMIO 설정, status 확인, completion marker까지 진행하는지 확인 |
| GEMM control | `gemm_busy_debug`, `gemm_state_debug` | GEMM busy와 phase 전이가 transaction 단위로 발생하는지 확인         |
| MMIO         | MMIO address/data/write 관련 신호         | A/B/C base, M/N/K, start, clear_done write 순서 확인                |
| Memory       | memory address/data/write 관련 신호       | A/B load와 C store가 기대 주소 범위에서 발생하는지 확인             |
| Invalid case | status, busy, memory write 관련 신호      | invalid dimension에서 data phase와 C write가 발생하지 않는지 확인   |

Waveform 파일은 크기가 커질 수 있으므로 기본 산출물로 항상 보관하지 않는다. 제출 시 waveform 증빙이 필요하면 대표 case 1개를 `--trace-fst`로 재실행하고, 해당 `.fst` 경로와 캡처 이미지만 별도로 첨부하는 방식이 적절하다.

## 9. 산출물 관리

기본 산출물 위치는 `sim/results`이다. 이 디렉토리는 재생성 가능한 실행 결과를 보관한다.

문서 제출용으로 결과를 고정해야 하는 경우에는 전체 `sim/results`를 복사하지 말고, 핵심 파일만 snapshot으로 보관한다.

권장 snapshot 위치는 다음과 같다.

```text
docs/report/artifacts/project2_item1/
```

권장 포함 파일은 다음과 같다.

- `report.md`
- `summary.json`
- `case_results.tsv`
- `warning_summary.tsv`

`build.log`, `run.log`, `.fst` waveform은 크기가 커질 수 있으므로 필요한 경우에만 포함한다.

## 10. 현재 한계

이번 검증은 Project2 1번의 Verilator transactional verification을 닫기 위한 범위에 집중했다. 따라서 아래 항목은 별도 작업으로 남는다.

- `sw/`의 실제 프로그램 바이너리를 CPU instruction memory에 적재해 실행하는 방식은 아니다.
- CPU가 A/B matrix를 직접 store하지 않고, TB가 shared memory에 preload한다.
- CPU가 C memory를 직접 읽어 결과를 확인하지 않고, TB scoreboard가 memory를 읽어 golden model과 비교한다.
- system-level 통합 검증은 대표 target인 `rtl_v2`만 대상으로 한다.
- Verilator cycle 비교는 simulation 기준의 구조 비교이며, 면적/전력까지 포함한 최종 최적해 판단은 Oasys/Nitro 합성 결과가 필요하다.
- Oasys/Nitro 합성 결과 분석과 FPGA 검증은 Project2 2번, 3번 범위이다.

위 한계는 현재 검증이 부족하다는 의미가 아니라, 검증 범위를 transaction-level과 system-level smoke/integration verification으로 명확히 제한했다는 의미이다.

## 11. 결론

Project2 1번 기준의 Verilator transactional verification은 다음 근거로 완료로 판단한다.

- `rtl`, `rtl_AT`, `rtl_v2` GEMM accelerator target별 표준 vector regression이 모두 PASS
- directed, random, mixed vector set에서 총 1008개 accelerator transaction PASS
- 1-MAC에서 4-MAC으로 확장하며 compute cycle 감소 확인
- 4-MAC 이후 `rtl_v2` dual-port 구조에서 load cycle 감소 확인
- `rtl_v2/gemm_system_top.v` 기준 CPU-driven system-level 검증 18개 case PASS
- valid GEMM case에서 C memory mismatch 0
- invalid dimension case에서 expected error status 확인, C memory 미변경, data phase cycle 0 확인
- 최종 산출물 기준 Verilator warning/error/fatal 없음

따라서 현재 repo는 GEMM accelerator transaction 검증과 `rtl_v2` 대표 system integration 검증까지 완료된 상태로 볼 수 있다. 이후 작업은 합성 분석, FPGA 검증, 필요 시 실제 `sw/` 프로그램 실행 기반 system verification으로 분리한다.
