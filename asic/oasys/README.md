# Oasys Synthesis Guide

## 실행명령어

**export synthesized Verilog netlist 명령어**

```
write_verilog "step*_mode*_synth.v"
```

**export timing, area, power report 명령어**

```
report_timing > "step*_mode*_timing.rpt"
report_area > "step*_mode*_area.rpt"
report_power > "step*_mode*_power.rpt"
```

## 2. 단계별 합성 타겟

Oasys에서 먼저 결정해야 하는 것은 합성 top module이다. 이번 프로젝트의
Verilator 검증은 이미 RTL 기능 검증에 해당하고, Oasys에서는 같은 RTL을
대상으로 timing, area, power를 분석한다.

### 2.1 1단계: `rtl_v2` GEMM accelerator-only

1차 필수 타겟은 `rtl_v2/gemm_accelerator/gemm_accelerator_top.v`이다.
`rtl_v2`는 dual-memory access 구조를 기준으로 하므로, 이 단계에서는
dual-memory 구조 안에서 MAC datapath 3종을 비교한다.

| Mode           | 조합                | 의미                   |
| -------------- | ------------------- | ---------------------- |
| `MAC_MODE=0` | dual-memory + AT    | K 방향 adder-tree 구조 |
| `MAC_MODE=1` | dual-memory + 1-MAC | 기준 구조              |
| `MAC_MODE=4` | dual-memory + 4-MAC | N 방향 병렬 MAC 구조   |

### 2.2 2단계: `rtl` GEMM accelerator-only

memory access 구조에 따른 변화를 추가로 보고 싶으면 기존 `rtl/gemm_accelerator`
타겟을 합성한다. 이 타겟은 single-memory access 계열 비교 후보이다.

| Mode           | 조합                  | 의미                         |
| -------------- | --------------------- | ---------------------------- |
| `MAC_MODE=1` | single-memory + 1-MAC | single-memory 기준 구조      |
| `MAC_MODE=4` | single-memory + 4-MAC | single-memory에서 MAC 병렬화 |

이 단계는 `rtl_v2` 결과와 비교해 memory access 변경이 area/power/timing에
어떤 영향을 주는지 보기 위한 후속 분석이다. 이번 1차 실행 범위는 `rtl_v2`로
고정하므로, 이 단계는 시간이 남을 때 진행한다.

### 2.3 3단계: `rtl_v2` full-system

1. 마지막 선택 타겟은 `rtl_v2/gemm_system_top.v`이다. CPU, glue logic, GEMM을
   포함한 전체 통합 구조의 참고용 PPA를 확인할 수 있다.

주의할 점은 `gemm_system_top.v` 내부의 behavioral BRAM이다. 실제 ASIC memory
macro 없이 합성하면 register array로 합성되어 area/power가 크게 왜곡될 수 있다.
따라서 full-system 결과는 주 비교가 아니라 integration overhead 참고값으로 둔다.

## 3. 합성 타겟 파일

각 단계의 source list는 `step1.f`, `step2.f`, `step3.f`에 정리하였다.
Mode별 parameter override 실수를 줄이기 위해 단계별 wrapper top을 함께 둔다.

### 3.1 1단계 wrapper

`step1_gemm_accelerator_top_mode*.v`는 `rtl_v2` dual-port GEMM accelerator 전용이다.
Oasys에서는 `step1.f`의 파일들을 추가한 뒤 다음 top module 중 하나를 선택한다.

```text
step1_gemm_accelerator_top_mode0  -> MAC_MODE=0
step1_gemm_accelerator_top_mode1  -> MAC_MODE=1
step1_gemm_accelerator_top_mode4  -> MAC_MODE=4
```

### 3.2 2단계 wrapper

`step2_gemm_accelerator_top_mode*.v`는 `rtl` single-port GEMM accelerator 전용이다.
`rtl` 계열에는 AT datapath가 없으므로 1-MAC과 4-MAC만 선택한다.

```text
step2_gemm_accelerator_top_mode1  -> MAC_MODE=1
step2_gemm_accelerator_top_mode4  -> MAC_MODE=4
```

### 3.3 3단계 wrapper

`step3_system_top_mode*.v`는 `rtl_v2` full-system top 전용이다.
Full-system 결과는 behavioral BRAM 영향을 받으므로 주 비교값이 아니라 참고값으로 둔다.

```text
step3_system_top_mode0  -> MAC_MODE=0
step3_system_top_mode1  -> MAC_MODE=1
step3_system_top_mode4  -> MAC_MODE=4
```

### 3.4 Config 파일

각 합성 target은 독립 config로 고정한다. Oasys에서는 아래 config 중 하나만 골라 실행하면 된다.

```text
step1_mode0_config.tcl  -> step1.f + step1_gemm_accelerator_top_mode0
step1_mode1_config.tcl  -> step1.f + step1_gemm_accelerator_top_mode1
step1_mode4_config.tcl  -> step1.f + step1_gemm_accelerator_top_mode4
step2_mode1_config.tcl  -> step2.f + step2_gemm_accelerator_top_mode1
step2_mode4_config.tcl  -> step2.f + step2_gemm_accelerator_top_mode4
step3_mode0_config.tcl  -> step3.f + step3_system_top_mode0
step3_mode1_config.tcl  -> step3.f + step3_system_top_mode1
step3_mode4_config.tcl  -> step3.f + step3_system_top_mode4
```

## 4. Constraint

강의5 PDF의 예시는 10 MHz clock이다. 첫 합성 constraint는 다음처럼 둔다.

```tcl
create_clock -name clk -period 100000.0 {get_ports clk}
```

속도 비교를 하려면 10 MHz에서 한 번 합성한 뒤 clock period를 줄여가며 timing이
깨지는 지점을 찾는다. 예를 들어 100 ns, 50 ns, 20 ns, 10 ns 순서로 줄여 볼 수 있다.
최종 보고서에는 각 mode의 slack과 가장 빠른 passing clock을 기록한다.

Frequency sweep은 주로 `step1`/`step2` accelerator-only 비교에 사용한다.
`step3` full-system은 합성 시간이 길고 behavioral BRAM의 영향이 크므로, 기본적으로
10 MHz 기준 결과를 남기고 여건이 될 때만 30000 ps 또는 40000 ps 수준의 고주파 참고
결과를 추가한다. 결과 보관 기준은 `results/README.md`를 따른다.

## 5. 결과에서 봐야 하는 항목

각 mode마다 최소한 다음 항목을 기록한다.

| 항목                 | 의미                      |
| -------------------- | ------------------------- |
| clock period         | 사용한 timing constraint  |
| slack 또는 WNS       | timing 만족 여부          |
| critical path        | 가장 느린 경로            |
| cell count           | 사용된 standard cell 개수 |
| area                 | 합성 면적                 |
| dynamic power        | 스위칭 전력               |
| leakage/static power | 정적 전력                 |
| total power          | 전체 전력                 |

분석은 단순히 "빠르다"가 아니라 다음 tradeoff로 정리한다.

```text
1-MAC  : 면적/전력은 작지만 cycle 수가 많음
4-MAC  : cycle 수는 줄지만 MAC 병렬화로 면적/전력 증가 예상
AT     : K 방향 병렬화로 특정 shape에서 유리하지만 adder-tree 비용 발생
```

합성 후 netlist와 report 산출물은 `asic/oasys/results/` 아래에 둔다.
권장 폴더 구조와 raw report 보관 기준은 `asic/oasys/results/README.md`에 정리한다.

## 6. 우리가 준비해야 하는 파일

```text
asic/oasys/
├── README.md
├── clk.sdc
├── step1_mode0_config.tcl
├── step1_mode1_config.tcl
├── step1_mode4_config.tcl
├── step2_mode1_config.tcl
├── step2_mode4_config.tcl
├── step3_mode0_config.tcl
├── step3_mode1_config.tcl
├── step3_mode4_config.tcl
├── step1_gemm_accelerator_top_mode0.v
├── step1_gemm_accelerator_top_mode1.v
├── step1_gemm_accelerator_top_mode4.v
├── step2_gemm_accelerator_top_mode1.v
├── step2_gemm_accelerator_top_mode4.v
├── step3_system_top_mode0.v
├── step3_system_top_mode1.v
├── step3_system_top_mode4.v
├── step1.f
├── step2.f
├── step3.f
```

각 파일의 역할은 다음과 같다.

| 파일                                   | 역할                                          |
| -------------------------------------- | --------------------------------------------- |
| `clk.sdc`                            | 10 MHz clock constraint                       |
| `step*_mode*_config.tcl`             | step/mode별 독립 Oasys 실행 config            |
| `step1_gemm_accelerator_top_mode*.v` | 1단계 `rtl_v2` accelerator mode top 제공    |
| `step2_gemm_accelerator_top_mode*.v` | 2단계 `rtl` accelerator mode top 제공       |
| `step3_system_top_mode*.v`           | 3단계 `rtl_v2` system mode top 제공         |
| `step1.f`                            | 1단계 `rtl_v2` accelerator-only source list |
| `step2.f`                            | 2단계 `rtl` accelerator-only source list    |
| `step3.f`                            | 3단계 `rtl_v2` full-system source list      |

`.f` 파일은 강의 PDF에서 요구한 형식은 아니지만, 학교 서버에서 repo를 clone한 뒤
Oasys GUI에 추가할 RTL 목록을 일관되게 관리하기 위한 기준 파일로 사용한다.
