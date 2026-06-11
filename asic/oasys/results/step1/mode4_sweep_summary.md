# Oasys Synthesis Frequency Sweep  step1 (MAC_MODE=4, 4-MAC)

대상: `step1_gemm_accelerator_top_mode4` (GEMM accelerator, 4-MAC, N방향 병렬)
합성 도구: Oasys-RTL
측정 기준: top instance `u_gemm` (gemm_accelerator_top)
작성일: 2026-06-11

## Sweep 결과

margin(%) = WNS / period x 100. 논리합성(Oasys) 후 배치배선(Nitro)에서
배선 지연이 추가되므로, margin이 클수록 Nitro에서 timing을 유지할 가능성이 높다.

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---------: | --------: | ------: | --------: | ----------: | --------------: | ------ |
|     100000 |      10.0 | 83577.5 |      83.6 |   412030.41 |        11887015 | pass   |
|      50000 |      20.0 | 33577.5 |      67.2 |   412030.41 |        21263352 | pass   |
|      30000 |      33.3 | 13577.5 |      45.3 |   412030.41 |        33765156 | pass   |
|      20000 |      50.0 |  3577.5 |      17.9 |   412030.41 |        49392248 | pass   |
|      15000 |      66.7 |  3761.6 |      25.1 |   426971.66 |        67469224 | pass   |
|       7000 |     142.9 |  -223.6 |      -3.2 |   524779.12 |       167515536 | fail   |

- WNS = worst slack (양수 = 여유, 음수 = timing violation)
- margin(%) = WNS / period x 100
- result: WNS >= 0 이면 pass, < 0 이면 fail

## 해석

- **timing closure 한계**: 15ns(66.7MHz)까지 여유 있게 통과하고,
  7ns(142.9MHz)에서 WNS=-223.6ps(margin -3.2%)로 실패한다.
- **area는 주파수가 높아질수록 증가**한다. period를 줄이면 합성기가
  timing을 맞추려고 더 빠른(=면적이 큰) 셀과 버퍼를 투입하기 때문이다.

  - 100ns~20ns: 412030 (여유가 커서 area 동일)
  - 15ns: 426972 (+3.6%)
  - 7ns: 524779 (+27.4%, 그럼에도 timing fail)
    즉 7ns는 area를 27%나 더 써도 timing을 못 맞춘 over-constrained 지점.
- **power는 주파수에 비례해 증가**한다.

  - 10MHz: 11.9 mW
  - 20MHz: 21.3 mW
  - 33.3MHz: 33.8 mW
  - 50MHz: 49.4 mW
  - 66.7MHz: 67.5 mW
  - 142.9MHz: 167.5 mW (fail)

## 권장 동작점 (Nitro P&R margin 고려)

Oasys(논리합성) WNS는 배선 지연을 충분히 반영하지 못하므로, Nitro(배치배선)
단계에서 slack이 줄어든다. 일반적으로 P&R margin은 period의 20~30% 이상을
권장한다.

| period | margin(%) | P&R 안전도 |
| -----: | --------: | ---------- |
|  100ns |      83.6 | 매우 안전  |
|   50ns |      67.2 | 매우 안전  |
|   30ns |      45.3 | 안전       |
|   20ns |      17.9 | 다소 빠듯  |
|   15ns |      25.1 | 안전       |
|    7ns |      -3.2 | fail       |

권장: **15ns(66.7MHz)**. margin이 25.1%로 권장 범위(20~30%)를 만족하면서
가장 높은 주파수를 확보한다. 보수적으로 가려면 30ns(33.3MHz, margin 45.3%)
또는 50ns가 안전하다. 단, 최종 확정은 Nitro 결과로 검증해야 한다.

## 비고

- 본 sweep은 MAC_MODE=4(4-MAC) 기준이다.
- 동일 동작점(15ns)에서 1-MAC 대비 area가 더 크다(약 328k -> 427k, +30%)
  고 power도 더 높다(52.8 -> 67.5 mW). 4-MAC은 곱셈기/누산기를 늘린 만큼
  면적/전력이 크지만 COMPUTE 사이클이 짧다. 면적-성능 trade-off는 mode별
  비교표(별도)에서 정리한다.
