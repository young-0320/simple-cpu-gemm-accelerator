# Oasys Synthesis Frequency Sweep  step1 (MAC_MODE=1, 1-MAC)

대상: `step1_gemm_accelerator_top_mac1` (GEMM accelerator, 1-MAC)
합성 도구: Oasys-RTL
측정 기준: top instance `u_gemm` (gemm_accelerator_top)
작성일: 2026-06-11

## Sweep 결과

margin(%) = WNS / period x 100. 논리합성(Oasys) 후 배치배선(Nitro)에서
배선 지연이 추가되므로, margin이 클수록 Nitro에서 timing을 유지할 가능성이 높다.

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0  | 83749.6 | 83.7 | 324236.53 | 9850876   | pass |
| 50000  | 20.0  | 33749.6 | 67.5 | 324236.53 | 17271910  | pass |
| 30000  | 33.3  | 13749.6 | 45.8 | 324236.53 | 27166724  | pass |
| 20000  | 50.0  | 3749.6  | 18.7 | 324236.53 | 39535204  | pass |
| 15000  | 66.7  | 3933.1  | 26.2 | 327971    | 52765272  | pass |
| 7000   | 142.9 | -64.0   | -0.9 | 363080.06 | 122008816 | fail |

- WNS = worst slack (양수 = 여유, 음수 = timing violation)
- margin(%) = WNS / period x 100
- result: WNS >= 0 이면 pass, < 0 이면 fail

## 해석

- **timing closure 한계**: 15ns(66.7MHz)까지 여유 있게 통과하고,
  7ns(142.9MHz)에서 WNS=-64.0ps(margin -0.9%)로 실패한다.

- **area는 주파수가 높아질수록 증가**한다. period를 줄이면 합성기가
  timing을 맞추려고 더 빠른(=면적이 큰) 셀과 버퍼를 투입하기 때문이다.
  - 100ns~20ns: 324236 (여유가 커서 area 동일)
  - 15ns: 327971 (+1.2%)
  - 7ns: 363080 (+12.0%, 그럼에도 timing fail)
  즉 7ns는 area를 12%나 더 써도 timing을 못 맞춘 over-constrained 지점.

- **power는 주파수에 비례해 증가**한다. switching power가 주파수에 거의
  선형적으로 커진다.
  - 10MHz: 9.85 mW
  - 20MHz: 17.3 mW
  - 33.3MHz: 27.2 mW
  - 50MHz: 39.5 mW
  - 66.7MHz: 52.8 mW
  - 142.9MHz: 122.0 mW (fail)

## 권장 동작점 (Nitro P&R margin 고려)

Oasys(논리합성) WNS는 배선 지연을 충분히 반영하지 못하므로, Nitro(배치배선)
단계에서 배선 지연이 더해지면 slack이 줄어든다. 따라서 Oasys margin이 한
자리수%로 빠듯한 동작점은 Nitro에서 실패할 위험이 크다. 일반적으로 P&R
margin은 period의 20~30% 이상을 권장한다.

| period | margin(%) | P&R 안전도 |
| ---: | ---: | --- |
| 100ns | 83.7 | 매우 안전 |
| 50ns  | 67.5 | 매우 안전 |
| 30ns  | 45.8 | 안전 |
| 20ns  | 18.7 | 다소 빠듯 |
| 15ns  | 26.2 | 안전 |
| 7ns   | -0.9 | fail |

권장: **15ns(66.7MHz)**. margin이 26.2%로 권장 범위(20~30%)를 만족하면서
가장 높은 주파수를 확보한다. 보수적으로 가려면 30ns(33.3MHz, margin 45.8%)
또는 50ns가 안전하다. 단, 최종 확정은 Nitro 결과로 검증해야 한다.

## 비고

- 본 sweep은 MAC_MODE=1(1-MAC) 기준이다. MAC_MODE=0(AT), 4(4-MAC)도 동일
  방식으로 sweep하면 세 모드의 PPA(속도-면적-전력)를 비교할 수 있다.

