# Vivado Synthesis+Implementation Frequency Sweep — Zybo Z7-20 (MAC_MODE=1, 1-MAC)

대상: `zybo_top` (wraps `gemm_system_top` -> CPU + glue + GEMM accelerator + 4096-word
external memory), 원본 4096-word `mem` 배열 그대로 사용 (ASIC용 256-word 데모
워크어라운드 없음).
합성/PnR 도구: Vivado 2024.2, part `xc7z020clg400-1` (raw part; 이 머신
Vivado에는 Digilent Zybo Z7 board file이 등록돼 있지 않음 — 수동 다운로드된
board_store는 있으나 기본 board.repopaths에 없어 board_part 대신 raw part +
기존 `fpga/Zybo-Z7.xdc`로 진행).
측정 기준: top instance `u_system` (gemm_system_top), report 시점은
`route_design` 완료 후 (`open_run impl_1`).
작성일: 2026-06-17

## Sweep 결과

margin(%) = WNS / period x 100. ASIC(Oasys) sweep과 달리 이 값은 실제
place&route(route_design) 이후의 WNS이므로 배선 지연이 이미 반영돼 있다.

| period(ns) | freq(MHz) | WNS(ns) | margin(%) | LUT | FF | BRAM Tile | total power(mW) | dynamic power(mW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100 | 10.0 | 85.629 | 85.6  | 1076 | 882 | 4 | 110 |  3 | pass |
| 50  | 20.0 | 36.079 | 72.2  | 1076 | 882 | 4 | 113 |  7 | pass |
| 30  | 33.3 | 16.427 | 54.8  | 1077 | 882 | 4 | 118 | 12 | pass |
| 20  | 50.0 |  7.081 | 35.4  | 1076 | 882 | 4 | 113 |  7 | pass |
| 15  | 66.7 |  1.972 | 13.1  | 1077 | 882 | 4 | 130 | 24 | pass |
| 14  | 71.4 |  0.872 |  6.2  | 1077 | 882 | 4 | 132 | 25 | pass |
| 13  | 76.9 |  0.592 |  4.5  | 1079 | 882 | 4 | 134 | 27 | pass |
| 12  | 83.3 |  0.267 |  2.2  | 1080 | 882 | 4 | 136 | 29 | pass |
| 11  | 90.9 | -0.379 | -3.4  | 1095 | 890 | 4 | 139 | 32 | fail |
| 10  | 100.0| -1.030 | -10.3 | 1102 | 884 | 4 | 142 | 35 | fail |

- WNS = worst negative slack (route_design 기준, 양수 = 여유, 음수 = timing violation)
- margin(%) = WNS / period x 100
- result: WNS >= 0 이면 pass, < 0 이면 fail
- BRAM Tile: `report_utilization`의 Block RAM Tile 카운트. 모든 지점에서 4
  (gemm_system_top.v의 `reg [31:0] mem[0:4095]`가 4x RAMB36E1로 정상 매핑됨,
  FF로 펼쳐지지 않음)
- power: `report_power` vectorless(activity-less) 추정치. 이 머신 Vivado에는
  VCD→SAIF 변환 도구가 없어 switching-activity 기반 측정(Oasys/Nitro 방식)을
  쓰지 못했다. 따라서 ASIC power 절대값과 직접 비교하지 말 것 — 같은 sweep
  방법론(주파수 대비 power 추이)을 비교 축으로만 쓴다.

## 해석

- **timing closure 한계**: 12ns(83.3MHz)까지 통과하고 11ns(90.9MHz)에서
  WNS=-0.379ns(margin -3.4%)로 실패한다.
- margin이 10~20% 구간에 들어오는 가장 빠른 지점은 **15ns(66.7MHz, margin
  13.1%)** 다. 14ns(71.4MHz)는 margin 6.2%로 권장 범위 아래다.
- LUT/FF는 주파수가 올라갈수록 소폭 증가한다(1076~1077 -> 1102, +2.4%).
  ASIC sweep에서 본 "주파수를 올리면 면적이 커진다" 패턴과 같은 방향이지만
  FPGA LUT 매핑이라 절대적인 비례는 아니다.
- dynamic power는 주파수에 거의 비례해 증가한다(10MHz 3mW -> 100MHz 35mW,
  약 12배). total power는 static(~106~107mW)이 dominant라 10MHz 110mW ->
  100MHz 142mW로 29% 증가에 그친다.

## 권장 동작점

**15ns (66.7MHz)**. margin 13.1%로 10~20% 목표 범위를 만족하면서 이 RTL이
닫을 수 있는 가장 빠른 지점이다. 더 빠른 지점(12~14ns)도 timing은 닫히지만
margin이 2~6%로 빠듯해 권장하지 않는다.

## 비고

- 이 sweep은 "이 RTL이 해당 주기에서 route_design까지 timing을 닫을 수
  있는가"를 보는 측정이다. Zybo 보드의 실제 오실레이터(`clk`, K17)는
  **125MHz(8ns) 고정**이라, 여기서 찾은 더 느린 Fmax(66.7MHz)를 실제 보드에
  그대로 줄 수는 없다 — MMCM/Clocking Wizard로 분주해야 한다. 이번 작업
  범위는 보드 프로그래밍이 아니므로 MMCM은 추가하지 않았다.
- MAC_MODE=4와의 비교는 `fpga/reports/mode4/sweep_summary_mode4.md` 참고.
