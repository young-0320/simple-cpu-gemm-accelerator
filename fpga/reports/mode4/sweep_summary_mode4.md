# Vivado Synthesis+Implementation Frequency Sweep — Zybo Z7-20 (MAC_MODE=4, 4-MAC)

대상: `zybo_top` (wraps `gemm_system_top` -> CPU + glue + GEMM accelerator + 4096-word
external memory), 원본 4096-word `mem` 배열 그대로 사용 (ASIC용 256-word 데모
워크어라운드 없음).
합성/PnR 도구: Vivado 2024.2, part `xc7z020clg400-1` (raw part; board file 미등록,
mode1과 동일한 사유 — `fpga/reports/mode1/sweep_summary_mode1.md` 참고).
측정 기준: top instance `u_system` (gemm_system_top), report 시점은
`route_design` 완료 후 (`open_run impl_1`).
작성일: 2026-06-17

## Sweep 결과

margin(%) = WNS / period x 100. route_design 이후 WNS이므로 배선 지연 반영됨.

| period(ns) | freq(MHz) | WNS(ns) | margin(%) | LUT | FF | BRAM Tile | total power(mW) | dynamic power(mW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100 | 10.0 | 84.847 | 84.8  | 1472 | 981 | 4 | 140 | 34 | pass |
| 50  | 20.0 | 34.415 | 68.8  | 1444 | 979 | 4 | 123 | 16 | pass |
| 30  | 33.3 | 15.866 | 52.9  | 1444 | 979 | 4 | 117 | 11 | pass |
| 20  | 50.0 |  6.596 | 33.0  | 1445 | 979 | 4 | 113 |  7 | pass |
| 16  | 62.5 |  2.867 | 17.9  | 1444 | 979 | 4 | 127 | 21 | pass |
| 15  | 66.7 |  2.255 | 15.0  | 1444 | 979 | 4 | 128 | 22 | pass |
| 14  | 71.4 |  1.054 |  7.5  | 1444 | 979 | 4 | 130 | 24 | pass |
| 13  | 76.9 |  0.553 |  4.3  | 1445 | 979 | 4 | 132 | 26 | pass |
| 12  | 83.3 |  0.006 |  0.05 | 1451 | 979 | 4 | 135 | 28 | pass |
| 11  | 90.9 | -0.567 | -5.2  | 1470 | 984 | 4 | 137 | 31 | fail |
| 10  | 100.0| -1.961 | -19.6 | 1472 | 981 | 4 | 140 | 34 | fail |

- WNS = worst negative slack (route_design 기준)
- margin(%) = WNS / period x 100
- result: WNS >= 0 이면 pass, < 0 이면 fail
- BRAM Tile: 모든 지점에서 4 (mode1과 동일하게 4096-word `mem`이 4x
  RAMB36E1로 매핑됨, FF로 펼쳐지지 않음)
- power: vectorless 추정치. mode1과 동일한 caveat — ASIC switching-activity
  기반 power와 절대값 비교 금지, sweep 추이만 비교 축으로 사용.

## 해석

- **timing closure 한계**: 12ns(83.3MHz, margin 0.05%)까지는 통과하지만
  사실상 한계치이고, 11ns(90.9MHz)에서 WNS=-0.567ns(margin -5.2%)로 실패한다.
- margin이 10~20% 구간에 들어오는 가장 빠른 지점은 **15ns(66.7MHz, margin
  15.0%)** 다. 14ns(71.4MHz)는 margin 7.5%로 권장 범위 아래다.
- **mode1과 비교**: 같은 period에서 대부분 mode4의 margin이 mode1보다 약간
  작다(예: 12ns에서 mode1 2.2% vs mode4 0.05%, 100ns에서 85.6% vs 84.8%).
  단 14ns/15ns 두 지점은 반대로 mode4가 약간 더 크다(15ns: 13.1% vs 15.0%).
  차이가 매 지점 1~2%p 수준으로 작고 순위가 뒤집히는 지점도 있어, 이는
  P&R 결과의 지점별 변동(noise)으로 보는 게 맞고 4-MAC이 1-MAC보다
  체계적으로 더 빠르거나 느리다고 결론 내리긴 어렵다. 두 mode가 같은
  15ns(66.7MHz)에서 권장 margin 구간에 들어온다는 사실 자체가, **critical
  path가 MAC datapath 차이로 크게 갈리지 않는다**는 것을 보여준다 — ASIC
  step3_demo sweep에서 확인된 "full-system critical path가 CPU
  accumulator에 있다(MAC 종류와 무관)"는 결론과 같은 방향이다.
- LUT는 mode1(1076~1102) 대비 mode4가 1444~1472로 약 34% 더 많이 쓴다(4-MAC
  병렬 datapath 때문). FF는 882~890 대비 979~984로 약 11% 더 많다. DSP는
  두 mode 모두 0개 사용(곱셈기가 LUT 로직으로 추론됨, DSP48 미사용).

## 권장 동작점

**15ns (66.7MHz)**. margin 15.0%로 mode1과 동일한 권장 주파수다. 두 mode가
독립적으로 측정한 결과가 우연히 같은 Fmax로 수렴했다 — critical path가
GEMM MAC datapath가 아니라 CPU 쪽에 있기 때문으로 해석된다.

## 비고

- Zybo 보드의 실제 오실레이터는 125MHz(8ns) 고정이므로, 여기서 찾은
  66.7MHz Fmax를 그대로 보드에 줄 수 없다(MMCM 없이는). 이번 작업은 보드
  프로그래밍을 하지 않으므로 MMCM은 추가하지 않았다.
- mode1/mode4 모두 같은 grid에서 독립적으로 측정했다(동일하다고 가정하지
  않음). 결과적으로 Fmax가 같게 나온 것은 측정 결과이지 가정이 아니다.
