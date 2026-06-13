# Oasys Synthesis Frequency Sweep - step3 (MAC_MODE=1, full-system)

대상: step3 full-system, MAC_MODE=1  
합성 도구: Oasys-RTL  
측정 기준: top area/power/timing report  
작성일: 2026-06-13

## Sweep 결과

margin(%) = WNS / period x 100. step3는 full-system 합성 시간이 길기 때문에 현재는 10MHz 기준 합성 결과만 기록한다.

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | cells | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0 | 83095.5 | 83.1 | 482747 | 40082996 | 1245425625 | pass |

- WNS = worst slack. 양수면 timing pass, 음수면 timing violation.
- margin(%) = WNS / period x 100.
- result: WNS >= 0이면 pass, WNS < 0이면 fail.

## 해석

- 100000ps(10MHz)에서 WNS가 83095.5ps라 매우 널널하다.
- critical path는 GEMM MAC 내부가 아니라 CPU 경로에서 잡혔다.
- full-system step3 area는 약 40.08M sq um로 매우 크다. 이는 memory까지 standard cell로 합성된 영향이 커서, step1/step2의 accelerator-only 결과와 직접 비교하면 안 된다.
- 현재 mode1은 step3에서 10MHz 기준점만 있으므로, 고주파 비교가 필요하면 별도 합성이 필요하다.

## 권장 동작점

| period | freq(MHz) | margin(%) | P&R 안전도 |
| ---: | ---: | ---: | --- |
| 100ns | 10.0 | 83.1 | 매우 안전 |

권장: mode1 step3는 100000ps(10MHz)를 기준 결과로 사용한다. step3 합성 시간이 길기 때문에, 추가 sweep은 Nitro에서 실제로 필요한 후보가 생겼을 때만 수행한다.

## Critical path

| period(ps) | startpoint | endpoint | logic depth |
| ---: | --- | --- | ---: |
| 100000 | u_system/u_cpu/u_inst_reg_instr_out_reg[28]/Q | u_system/u_cpu/u_accumulator_acc_out_reg[30]/DATA | 73 |

## 검증 메모

- mode1_100000ps
  - timing: step3_mode1_timing.rpt, Clock shift 100000.0ps, Slack 83095.5ps
  - area: step3_mode1_area.rpt, Cells 482747, Cell Area 40082996
  - power: step3_mode1_power.rpt, Total Power 1245425.625uW = 1245425625nW
