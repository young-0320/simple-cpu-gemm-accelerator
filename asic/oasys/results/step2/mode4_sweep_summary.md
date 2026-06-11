# Oasys Synthesis Frequency Sweep — step2 (MAC_MODE=4, 4-MAC)

대상: `step2_gemm_accelerator_top_mode4` (GEMM accelerator, 4-MAC, N방향 병렬)
합성 도구: Oasys-RTL
측정 기준: top instance `u_gemm` (gemm_accelerator_top)
작성일: 2026-06-11

## Sweep 결과

margin(%) = WNS / period × 100. 논리합성(Oasys) 후 배치배선(Nitro)에서
배선 지연이 추가되므로, margin이 클수록 Nitro에서 timing을 유지할 가능성이 높다.

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---------: | --------: | ------: | --------: | ----------: | --------------: | ------ |
|     100000 |      10.0 | 83595.1 |      83.6 |   339473.78 |        11501117 | pass   |
|      50000 |      20.0 | 33595.1 |      67.2 |   399473.78 |        20505828 | pass   |
|      20000 |      50.0 |  3595.1 |      18.0 |   399473.78 |        47520008 | pass   |
|      15000 |      66.7 |  3780.8 |      25.2 |   414415.03 |        64452052 | pass   |
|      13000 |      76.9 |  1780.8 |      13.7 |   414415.03 |        73983592 | pass   |
|      10000 |     100.0 |    20.5 |       0.2 |   420907.59 |        97357816 | pass   |
|       8000 |     125.0 |    -9.4 |      -0.1 |   462797.16 |       132852928 | fail   |

- WNS = worst slack (양수 = 여유, 음수 = timing violation)
- margin(%) = WNS / period × 100
- result: WNS >= 0 이면 pass, < 0 이면 fail

## 해석

- **timing closure 한계**: 10000ps(100MHz)까지 통과하고,
  8000ps(125MHz)에서 WNS=-9.4ps(margin -0.1%)로 실패한다.
- **area는 주파수가 높아질수록 증가**한다. period를 줄이면 합성기가
  timing을 맞추려고 더 빠른(=면적이 큰) 셀과 버퍼를 투입하기 때문이다.
  - 100ns: 339474 (초기값)
  - 50ns~20ns: 399474 (+17.7%, 셀 교체 발생)
  - 15ns~13ns: 414415 (+22.1%)
  - 10ns: 420908 (+24.0%)
  - 8ns: 462797 (+36.3%, 그럼에도 timing fail)
    즉 8ns는 area를 36.3% 더 써도 timing을 못 맞춘 over-constrained 지점.
- **power는 주파수에 비례해 증가**한다.
  - 10MHz:  11.5 mW
  - 20MHz:  20.5 mW
  - 50MHz:  47.5 mW
  - 66.7MHz: 64.5 mW
  - 76.9MHz: 74.0 mW
  - 100MHz:  97.4 mW
  - 125MHz: 132.9 mW (fail)

## 권장 동작점 (Nitro P&R margin 고려)

Oasys(논리합성) WNS는 배선 지연을 충분히 반영하지 못하므로, Nitro(배치배선)
단계에서 slack이 줄어든다. 일반적으로 P&R margin은 period의 20~30% 이상을
권장한다.

| period | freq(MHz) | margin(%) | P&R 안전도 |
| -----: | --------: | --------: | ---------- |
|  100ns |      10.0 |      83.6 | 매우 안전  |
|   50ns |      20.0 |      67.2 | 매우 안전  |
|   20ns |      50.0 |      18.0 | 다소 빠듯  |
|   15ns |      66.7 |      25.2 | 안전       |
|   13ns |      76.9 |      13.7 | 빠듯       |
|   10ns |     100.0 |       0.2 | 매우 빠듯  |
|    8ns |     125.0 |      -0.1 | fail       |

권장: **15ns(66.7MHz)**. margin이 25.2%로 권장 범위(20~30%)를 만족하면서
충분한 여유를 확보한다. 10ns(100MHz)는 margin이 0.2%로 매우 빠듯하여
Nitro에서 timing 실패 가능성이 높다. 단, 최종 확정은 Nitro 결과로 검증해야 한다.

## 비고

- 본 sweep은 MAC_MODE=4(4-MAC) 기준이다.
- step2는 single-memory access 구조이며, rtl_v2(dual-memory) 대비
  memory access 방식의 차이가 area/power/timing에 미치는 영향을
  비교하기 위한 후속 분석 타겟이다.
- 동일 동작점(15ns)에서 1-MAC(step2 mode1) 대비 area가 더 크고(414k vs 315k, +31%)
  power도 더 높다(64.5 vs 50.2 mW). 4-MAC은 곱셈기/누산기를 늘린 만큼
  면적/전력이 크지만 COMPUTE 사이클이 짧다. 면적-성능 trade-off는 mode별
  비교표(별도)에서 정리한다.
