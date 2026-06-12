# Nitro P&R Guide

## 1. Nitro에서 하는 일

Nitro는 Oasys가 만든 gate-level Verilog netlist를 실제 칩 영역 위에 배치하고 배선하는 P&R(place and route) 도구이다.

작업 순서

1. Oasys 결과 중 Nitro로 넘길 후보 netlist를 선택한다.
2. 후보 clock period에 맞는 SDC constraint를 준비한다.
3. `step*/mode*_*ps_nitro.tcl` 파일을 작성한다.
4. Nitro에서 Tcl을 실행해 placement, clock timing, routing을 수행한다.
5. post-route Verilog, SDF, timing 결과를 확인한다.
6. Nitro WNS가 부족하면 period, chip area, floorplan, RTL 구조를 다시 조정한다.

## 2. Tcl 입력

Nitro Tcl이 읽는 주요 입력은 다음과 같다.

| 입력                          | 역할                               |
| ----------------------------- | ---------------------------------- |
| `Generic250nm_tech.lef`     | 공정 metal/routing rule 정보       |
| `Generic250nm_StdCells.lef` | standard-cell physical layout 정보 |
| `TANNER_TT_2P50V_25C.lib`   | standard-cell timing/power library |
| `Generic250nm_typ.ptf`      | process technology file            |
| Oasys `*_synth.v`           | P&R 대상 gate-level netlist        |
| `*.sdc`                     | clock period constraint            |
| `*_nitro.tcl`               | Nitro 실행 flow                    |

공정 파일 경로는 교수님 예제 Tcl을 기준으로 유지한다. 우리 프로젝트에서 주로 바꾸는
부분은 Oasys netlist 경로, SDC 경로, partition 이름, 결과 출력 경로이다.

## 3. Tcl 파일 구조

Nitro Tcl은 Oasys보다 파일 수가 많아질 수 있으므로 step별 폴더 아래에 둔다.
파일명에는 mode와 clock period를 넣는다.

```text
asic/nitro/
├── README.md
├── myscript_nitro.tcl
├── step1/
│   ├── mode0_20000ps_nitro.tcl
│   ├── mode1_15000ps_nitro.tcl
│   └── mode4_15000ps_nitro.tcl
├── step2/
│   ├── mode1_15000ps_nitro.tcl
│   └── mode4_15000ps_nitro.tcl
├── step3/
│   ├── mode0_100000ps_nitro.tcl
│   ├── mode1_100000ps_nitro.tcl
│   └── mode4_100000ps_nitro.tcl
└── results/
    ├── step1/
    ├── step2/
    └── step3/
```

`myscript_nitro.tcl`은 교수님 예제로 원본으로 보관하고, 실제 실행용 Tcl은
`step1/`, `step2/`, `step3/` 아래에 개별 파일로 만든다.

## 4. 예제 Tcl에서 수정해야 하는 부분

교수님 예제 Tcl의 기본 flow는 유지하되, 다음 항목은 우리 프로젝트에 맞게 수정한다.

| Tcl 명령                     | 수정 내용                                       |
| ---------------------------- | ----------------------------------------------- |
| `read_verilog`             | Oasys 결과 `*_synth.v` 경로로 변경            |
| `create_chip`              | chip/core 크기 조정 후보                        |
| `create_floorplan_regions` | `-partition`을 실제 top module 이름으로 변경  |
| `create_rows`              | `-partition`을 실제 top module 이름으로 변경  |
| `read_constraint`          | 후보 period에 맞는 SDC 파일로 변경              |
| `write_sdf`                | 결과 폴더 아래 후보별 SDF 이름으로 변경         |
| `write_verilog`            | 결과 폴더 아래 post-route netlist 이름으로 변경 |

예시:

```tcl
read_verilog /mnt/NewHDD/home/ddl2026/ddl2026_2023104135/ddl2026_folder/simple-cpu-gemm-accelerator/asic/oasys/results/step1/mode0_20000ps/step1_mode0_synth.v

create_floorplan_regions -partition step1_gemm_accelerator_top_mode0 -min_cells 0 -max_cells 1000000000 -min_area_percent 1 -max_area_percent 100 -core_cell_util 70

create_rows -partition step1_gemm_accelerator_top_mode0 -core_site CORE -orient north -start_from core -gap 50a -xl_margin 0a -yb_margin 0a -xr_margin 0a -yt_margin 0a

read_constraint step1_mode0_20000ps.sdc

write_sdf ../results/step1/mode0_20000ps/step1_mode0_20000ps.sdf -skip_backslash true
write_verilog -file "../results/step1/mode0_20000ps/step1_mode0_20000ps_nitro.v"
```

## 5. 결과 보관 기준

Nitro 결과는 `asic/nitro/results/<step>/<mode>_<period>ps/` 아래에 둔다.

예시:

```text
asic/nitro/results/step1/mode0_20000ps/
├── step1_mode0_20000ps.sdf
├── step1_mode0_20000ps_nitro.v
├── step1_mode0_20000ps_timing.rpt
├── step1_mode0_20000ps_area.rpt
└── step1_mode0_20000ps_summary.md
```

최소로 확인할 항목:

| 항목                  | 의미                              |
| --------------------- | --------------------------------- |
| post-route WNS/slack  | 실제 배선 이후 timing 만족 여부   |
| routed netlist        | 배치배선 이후 Verilog             |
| SDF                   | back-annotation용 delay 정보      |
| chip/core area        | 사용한 물리 영역                  |
| utilization           | core 안에 cell이 얼마나 차 있는지 |
| congestion/route 상태 | 배선이 정상적으로 완료되었는지    |

## 6. Chip area 조정

교수님 예제는 다음과 같은 chip area에서 시작한다.

```tcl
create_chip -xl_area 0a -yb_area 0a -xr_area 3000000a -yt_area 3000000a -core_site CORE ...
create_floorplan_regions ... -core_cell_util 70
```

처음에는 이 값을 그대로 사용해 flow를 검증한다. 이후 placement 실패, routing congestion,
또는 post-route timing 실패가 발생하면 chip 크기, utilization, floorplan을 조정한다.

일반적인 방향:

```text
utilization이 너무 높거나 routing이 막힘 -> chip/core area 증가
timing이 배선 지연 때문에 나빠짐        -> area/floorplan/placement 조건 조정
area가 너무 널널함                      -> chip/core area를 줄여 재시도
```

최종 면적은 한 번에 정하는 값이 아니라, Nitro 결과를 보면서 조정하는 값이다.
