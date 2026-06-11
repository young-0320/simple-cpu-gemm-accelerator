# Oasys Synthesis Frequency Sweep — step2 (MAC_MODE=1, 1-MAC)

대상: `step2_gemm_accelerator_top_mode1` (GEMM accelerator, 1-MAC, 기준 구조)
합성 도구: Oasys-RTL
측정 기준: top instance `u_gemm` (gemm_accelerator_top)
작성일: 2026-06-11

## Sweep 결과

margin(%) = WNS / period × 100. 논리합성(Oasys) 후 배치배선(Nitro)에서
배선 지연이 추가되므로, margin이 클수록 Nitro에서 timing을 유지할 가능성이 높다.

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0  | 83743.3 | 83.7 | 311670.59 |   9505319 | pass |
| 50000  | 20.0  | 33743.3 | 67.5 | 311670.59 |  16595076 | pass |
| 20000  | 50.0  |  3743.3 | 18.7 | 311670.59 |  37864568 | pass |
| 15000  | 66.7  |  3880.6 | 25.9 | 315405.91 |  50150304 | pass |
| 10000  | 100.0 |   100.4 |  1.0 | 318796.56 |  74661344 | pass |
| 8500   | 117.6 |    34.8 |  0.4 | 326341.72 |  89441000 | pass |
| 7000   | 142.9 |   -32.6 | -0.5 | 353923.44 | 119812136 | fail |

- WNS = worst slack (양수 = 여유, 음수 = timing violation)
- margin(%) = WNS / period × 100
- result: WNS >= 0 이면 pass, < 0 이면 fail

## 해석

- **timing closure 한계**: 8500ps(117.6MHz)까지 통과하고,
  7000ps(142.9MHz)에서 WNS=-32.6ps(margin -0.5%)로 실패한다.
- **area는 주파수가 높아질수록 증가**한다. period를 줄이면 합성기가
  timing을 맞추려고 더 빠른(=면적이 큰) 셀과 버퍼를 투입하기 때문이다.
  - 100ps~20ns: 311671 (여유가 커서 area 동일)
  - 15ns: 315406 (+1.2%)
  - 10ns: 318797 (+2.3%)
  - 8.5ns: 326342 (+4.7%)
  - 7ns: 353923 (+13.5%, 그럼에도 timing fail)
  즉 7ns는 area를 13.5% 더 써도 timing을 못 맞춘 over-constrained 지점.
- **power는 주파수에 비례해 증가**한다.
  - 10MHz:   9.5 mW
  - 20MHz:  16.6 mW
  - 50MHz:  37.9 mW
  - 66.7MHz: 50.2 mW
  - 100MHz:  74.7 mW
  - 117.6MHz: 89.4 mW
  - 142.9MHz: 119.8 mW (fail)

## 권장 동작점 (Nitro P&R margin 고려)

Oasys(논리합성) WNS는 배선 지연을 충분히 반영하지 못하므로, Nitro(배치배선)
단계에서 slack이 줄어든다. 일반적으로 P&R margin은 period의 20~30% 이상을
권장한다.

| period | freq(MHz) | margin(%) | P&R 안전도 |
| ---: | ---: | ---: | --- |
| 100ns | 10.0  | 83.7 | 매우 안전 |
| 50ns  | 20.0  | 67.5 | 매우 안전 |
| 20ns  | 50.0  | 18.7 | 다소 빠듯 |
| 15ns  | 66.7  | 25.9 | 안전 |
| 10ns  | 100.0 |  1.0 | 매우 빠듯 |
| 8.5ns | 117.6 |  0.4 | 매우 빠듯 |
| 7ns   | 142.9 | -0.5 | fail |

권장: **15ns(66.7MHz)**. margin이 25.9%로 권장 범위(20~30%)를 만족하면서
충분한 여유를 확보한다. 보수적으로 가려면 20ns(50MHz, margin 18.7%)도
고려할 수 있으나 margin이 다소 빠듯하다. 단, 최종 확정은 Nitro 결과로 검증해야 한다.

## 비고

- 본 sweep은 MAC_MODE=1(1-MAC) 기준이다.
- step2는 single-memory access 구조이며, rtl_v2(dual-memory) 대비
  memory access 방식의 차이가 area/power/timing에 미치는 영향을
  비교하기 위한 후속 분석 타겟이다.
- 동일 동작점(15ns)에서 4-MAC(step1) 대비 area가 더 작고(315k vs 427k, -26%)
  power도 더 낮다(50.2 vs 67.5 mW). 1-MAC은 곱셈기/누산기가 적은 만큼
  면적/전력이 작지만 COMPUTE 사이클이 길다. 면적-성능 trade-off는 mode별
  비교표(별도)에서 정리한다.
