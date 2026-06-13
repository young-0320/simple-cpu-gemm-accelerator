# Oasys Synthesis Frequency Sweep - step3 (MAC_MODE=0, full-system)

대상: step3 full-system, MAC_MODE=0  
합성 도구: Oasys-RTL  
측정 기준: top area/power/timing report  
작성일: 2026-06-13

## Sweep 결과

margin(%) = WNS / period x 100. step3는 CPU, GEMM, memory가 모두 포함된 full-system 합성이므로 합성 시간이 매우 길다. 따라서 촘촘한 sweep보다는 10MHz 기준점과 고주파 참고점만 기록한다.

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | cells | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0 | 79511.8 | 79.5 | 485039 | 40166940 | 1264801625 | pass |
| 30000 | 33.3 | 9511.7 | 31.7 | 485039 | 40166940 | 4214635500 | pass |
| 10000 | 100.0 | 17.2 | 0.2 | 487316 | 40225264 | 12351953000 | pass |

- WNS = worst slack. 양수면 timing pass, 음수면 timing violation.
- margin(%) = WNS / period x 100.
- result: WNS >= 0이면 pass, WNS < 0이면 fail.

## 해석

- 100000ps(10MHz)는 WNS가 79511.8ps라 매우 널널하다.
- 30000ps(33.3MHz)는 WNS가 9511.7ps, margin이 31.7%라 step3 고주파 참고 후보로 볼 수 있다.
- 10000ps(100MHz)는 WNS가 17.2ps뿐이라 Oasys에서는 pass지만 Nitro P&R으로 넘기기에는 margin이 거의 없다.
- 100000ps와 30000ps는 cells/area가 동일하다. 10000ps에서는 timing을 맞추기 위해 cells가 2277개, area가 58324 sq um 증가했다.
- full-system step3 area는 약 40.17M sq um로 step1/step2의 accelerator-only 면적보다 훨씬 크다. 이는 memory까지 standard cell로 합성된 영향이 커서, accelerator-only 결과와 직접 비교하면 안 된다.

## 권장 동작점

| period | freq(MHz) | margin(%) | P&R 안전도 |
| ---: | ---: | ---: | --- |
| 100ns | 10.0 | 79.5 | 매우 안전 |
| 30ns | 33.3 | 31.7 | 고주파 참고 후보 |
| 10ns | 100.0 | 0.2 | 매우 빡빡함 |

권장: 기본 결과는 100000ps(10MHz)를 사용한다. 고주파 후보를 보여줘야 한다면 30000ps(33.3MHz)를 같이 남긴다. 10000ps(100MHz)는 Oasys pass 확인용으로만 보고, Nitro 후보에서는 제외하는 것이 안전하다.

## Critical path

| period(ps) | startpoint | endpoint | logic depth |
| ---: | --- | --- | ---: |
| 100000 | u_system/u_gemm/u_mmio_r_k_reg[2]/Q | u_system/u_gemm/u_mac/acc_reg[31]/DATA | 87 |
| 30000 | u_system/u_gemm/u_mmio_r_k_reg[2]/Q | u_system/u_gemm/u_mac/acc_reg[31]/DATA | 87 |
| 10000 | u_system/u_gemm/u_mmio_r_k_reg[0]/Q | u_system/u_gemm/u_mac/acc_reg[22]/DATA | 54 |

## 검증 메모

- mode0_100000ps
  - timing: step3_mode0_timing.rpt, Clock shift 100000.0ps, Slack 79511.8ps
  - area: step3_mode0_area.rpt, Cells 485039, Cell Area 40166940
  - power: step3_mode0_power.rpt, Total Power 1264801.625uW = 1264801625nW
- mode0_30000ps
  - timing: step3_mode0_timing.rpt, Clock shift 30000.0ps, Slack 9511.7ps
  - area: step3_mode0_area.rpt, Cells 485039, Cell Area 40166940
  - power: step3_mode0_power.rpt, Total Power 4214635.5uW = 4214635500nW
- mode0_10000ps
  - timing: step3_mode0_timing.rpt, Clock shift 10000.0ps, Slack 17.2ps
  - area: step3_mode0_area.rpt, Cells 487316, Cell Area 40225264
  - power: step3_mode0_power.rpt, Total Power 12351953uW = 12351953000nW
