# Oasys Synthesis Frequency Sweep — step1 (MAC_MODE=0, AT)

대상: `step1_gemm_accelerator_top_mode0` (GEMM accelerator, AT, K-reduction 방향 adder-tree)
합성 도구: Oasys-RTL
측정 기준: top instance `u_gemm` (gemm_accelerator_top)
작성일: 2026-06-12

## Sweep 결과

margin(%) = WNS / period x 100. 

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---------: | --------: | ------: | --------: | ----------: | --------------: | ------ |
|     100000 |      10.0 | 79510.7 |      79.5 |      408183 |        11877979 | pass   |
|      50000 |      20.0 | 29510.7 |      59.0 |      408183 |        21325672 | pass   |
|      30000 |      33.3 |  9510.7 |      31.7 |      408183 |        33922418 | pass   |
|      20000 |      50.0 |  6503.6 |      32.5 |      406367 |        48449828 | pass   |
|      15000 |      66.7 |  1503.6 |      10.0 |      406367 |        63789414 | pass   |
|      10000 |     100.0 |    23.9 |       0.2 |      458084 |       113485008 | pass   |
|       8000 |     125.0 |  -709.7 |      -8.9 |      521780 |       150341906 | fail   |

- WNS = worst slack (양수 = 여유, 음수 = timing violation)
- margin(%) = WNS / period x 100
- result: WNS >= 0 이면 pass, < 0 이면 fail

## 해석

- **timing closure 한계**: 10ns(100.0MHz)까지는 통과하지만,
  WNS=23.9ps(margin 0.2%)로 거의 경계점에 가깝다. 8ns(125.0MHz)에서는
  WNS=-709.7ps(margin -8.9%)로 실패한다.
- **Nitro P&R을 고려한 실사용 후보**는 10ns나 15ns보다 20ns 쪽이 자연스럽다.
  15ns는 pass이지만 margin이 10.0%로 작고, 10ns는 margin이 0.2%라 배선 지연이
  추가되면 실패할 가능성이 높다. 20ns는 margin이 32.5%로 P&R 여유가 더 크다.
- **area는 100ns에서 15ns 구간까지 406K 수준으로 거의 유지된다.**
  주파수 constraint가 매우 공격적으로 바뀌는 10ns부터는 timing을 맞추기 위해
  셀과 버퍼가 늘어나면서 area가 크게 증가한다.

  - 100ns~30ns: 408183
  - 20ns~15ns: 406367 (동일 수준, 합성 최적화 차이로 소폭 감소)
  - 10ns: 458084 (+12.2%)
  - 8ns: 521780 (+27.8%, 그럼에도 timing fail)
    즉 8ns는 area를 크게 늘려도 timing을 맞추지 못한 over-constrained 지점이다.
- **power는 주파수에 비례해 증가**한다.

  - 10MHz: 11.9 mW
  - 20MHz: 21.3 mW
  - 33.3MHz: 33.9 mW
  - 50MHz: 48.4 mW
  - 66.7MHz: 63.8 mW
  - 100MHz: 113.5 mW
  - 125MHz: 150.3 mW (fail)

## 권장 동작점 (Nitro P&R margin 고려)

Oasys(논리합성) WNS는 배선 지연을 충분히 반영하지 못하므로, Nitro(배치배선)
단계에서 slack이 줄어든다. 일반적으로 P&R margin은 period의 20~30% 이상을
권장한다.

| period | freq(MHz) | margin(%) | P&R 안전도 |
| -----: | --------: | --------: | ---------- |
|  100ns |      10.0 |      79.5 | 매우 안전  |
|   50ns |      20.0 |      59.0 | 매우 안전  |
|   30ns |      33.3 |      31.7 | 안전       |
|   20ns |      50.0 |      32.5 | 안전       |
|   15ns |      66.7 |      10.0 | 빠듯       |
|   10ns |     100.0 |       0.2 | 매우 빠듯  |
|    8ns |     125.0 |      -8.9 | fail       |

권장: **20ns(50.0MHz)**. 15ns(66.7MHz)도 Oasys 기준으로는 pass이지만
margin이 10.0%라 Nitro 배치배선 이후 timing 실패 가능성이 있다. 20ns는
margin이 32.5%로 권장 범위(20~30%) 이상을 확보하면서, 30ns보다 높은 주파수를
제공한다. 보수적으로 가려면 30ns(33.3MHz, margin 31.7%)가 안전하다.
단, 최종 확정은 Nitro 결과로 검증해야 한다.

## 비고

- 본 sweep은 MAC_MODE=0(AT, adder-tree) 기준이다.
- AT는 하나의 C[i][j]를 계산할 때 K-reduction 방향의 여러 곱셈 항을 병렬로 만들고
  adder-tree로 더하는 구조이다. 따라서 특정 GEMM shape에서 cycle 수를 줄일 수 있지만,
  병렬 multiplier와 adder-tree 비용으로 면적/전력이 증가한다.
- 동일 동작점(15ns)에서 1-MAC 대비 area가 더 크고(약 328k -> 406k, +23.9%)
  power도 더 높다(52.8 -> 63.8 mW). 4-MAC 대비로는 area가 약간 작고
  (427k -> 406k, -4.8%), power도 낮다(67.5 -> 63.8 mW).
  면적-성능 trade-off는 mode별 비교표(별도)에서 정리한다.
