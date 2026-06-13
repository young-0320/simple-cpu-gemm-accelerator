# Oasys Synthesis  step3 Full-System (BRAM 256-word DEMO)

대상: `step3_system_top_mode*` (CPU + glue + GEMM + memory 전체 통합)
메모리: behavioral BRAM을 4096 -> 256 word로 축소한 데모 버전
합성 도구: Oasys-RTL
측정 기준: top instance `u_system` (gemm_system_top)
작성일: 2026-06-13

## 메모리 축소 효과 (왜 데모인가)

원래 full-system은 BRAM 4096x32 = 131072 FF로 합성되어 전체 cell이 약
480,000개까지 폭증, Nitro P&R에서 congestion으로 배치배선이 끝나지 않았다.
256 word로 줄이자 cell이 약 14,000개 수준으로 감소하여 합성/P&R이 정상적으로
완료된다.

## mode별 frequency sweep

### MAC_MODE=0 (AT)

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0  | 79517.5 | 79.5 | 2968141.00 | 86059448  | pass |
| 30000  | 33.3  | 9517.5  | 31.7 | 2968141.00 | 286177888 | pass |
| 10000  | 100.0 | 5.3     | 0.1  | 3022335.50 | 873961856 | pass |

### MAC_MODE=1 (1-MAC)

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0  | 83095.5 | 83.1 | 2884194.25 | 84326776  | pass |
| 30000  | 33.3  | 13095.5 | 43.7 | 2884194.25 | 280403328 | pass |

### MAC_MODE=4 (4-MAC)

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0  | 83095.5 | 83.1 | 2971988.00 | 87667048  | pass |
| 30000  | 33.3  | 13095.5 | 43.7 | 2971988.00 | 291348352 | pass |

- margin(%) = WNS / period x 100
- mode0의 10ns는 margin 0.1%로 사실상 한계, Nitro 배선 지연 고려 시 실패 위험.

## 세 mode 비교

### 100ns (10MHz)

| mode | WNS(ps) | margin(%) | area(sq um) | total_power(nW) |
| --- | ---: | ---: | ---: | ---: |
| 0 (AT)    | 79517.5 | 79.5 | 2968141.00 | 86059448 |
| 1 (1-MAC) | 83095.5 | 83.1 | 2884194.25 | 84326776 |
| 4 (4-MAC) | 83095.5 | 83.1 | 2971988.00 | 87667048 |

### 30ns (33.3MHz)

| mode | WNS(ps) | margin(%) | area(sq um) | total_power(nW) |
| --- | ---: | ---: | ---: | ---: |
| 0 (AT)    | 9517.5  | 31.7 | 2968141.00 | 286177888 |
| 1 (1-MAC) | 13095.5 | 43.7 | 2884194.25 | 280403328 |
| 4 (4-MAC) | 13095.5 | 43.7 | 2971988.00 | 291348352 |

## 해석

- **세 mode 모두 100ns/30ns에서 충분한 여유로 통과**한다. full-system은
  CPU/glue/memory 오버헤드가 area의 대부분(약 2.9M sq um)을 차지하므로,
  MAC datapath 차이(AT/1-MAC/4-MAC)에 따른 area/power 변화가 작다.
  - area: 2.88M ~ 2.97M (mode간 차이 ~3%)
  - power(100ns): 84.3 ~ 87.7 mW (mode간 차이 ~4%)
- accelerator-only(step1)에서는 mode간 area 차이가 30% 수준이었으나,
  full-system에서는 CPU+memory가 분모를 키워 그 차이가 희석된다.
- 1-MAC과 4-MAC의 WNS가 동일(83095.5 / 13095.5)한 것은, critical path가
  MAC datapath가 아니라 CPU(u_accumulator)에 있기 때문이다(Timing Path의
  endpoint가 u_cpu/u_accumulator). 즉 full-system 속도는 MAC 종류가 아니라
  CPU가 결정한다.
- 따라서 mode별 PPA 비교는 step1(accelerator-only)이 적합하고, step3는
  "전체 시스템이 물리적으로 합성/배치 가능하다"는 integration 참고값으로 본다.

## 권장 동작점

full-system 데모는 **30ns(33.3MHz)** 또는 100ns 기준으로 남긴다. margin이
30~80%대로 안전해 Nitro P&R도 무리 없이 완료된다. mode0의 10ns(0.1%)는
한계라 권장하지 않는다.

## 비고

- 이 결과는 BRAM 256-word 데모 기준이다. behavioral BRAM은 실제 ASIC에서는
  SRAM macro로 대체되어야 하므로, 여기의 area/power는 memory를 register array로
  합성한 값이 포함된 참고치다(oasys/README.md 2.3절의 한계와 동일).
- accelerator-only PPA 비교는 sweep_summary.md(1-MAC), sweep_summary_mode4.md
  (4-MAC) 참고.

