# Oasys Synthesis Frequency Sweep - step3 (MAC_MODE=1, full-system)

대상: step3 full-system, MAC_MODE=1  
합성 도구: Oasys-RTL  
측정 기준: top area/power/timing report  
작성일: 2026-06-13

## Sweep 결과

margin(%) = WNS / period x 100. step3는 CPU, GEMM, memory가 모두 포함된 full-system 합성이므로 합성 시간이 매우 길다. 현재는 10MHz 기준점과 33.3MHz 참고점만 기록한다.

| period(ps) | freq(MHz) | WNS(ps) | margin(%) | cells | area(sq um) | total_power(nW) | result |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 100000 | 10.0 | 83095.5 | 83.1 | 482747 | 40082996 | 1245425625 | pass |
| 30000 | 33.3 | 13095.5 | 43.7 | 482747 | 40082996 | 4150035000 | pass |

- WNS = worst slack. 양수면 timing pass, 음수면 timing violation.
- margin(%) = WNS / period x 100.
- result: WNS >= 0이면 pass, WNS < 0이면 fail.

## 해석

- (수정) 이전 버전에는 results/step3/mode1_30000ps 합성 결과가 누락되어 있었고, 그 결과 정상 동작 주파수가 10MHz 한 지점만으로 표기되어 있었다. 실제로는 30000ps 합성 결과도 존재하므로 이번에 표에 추가했다.
- 100000ps(10MHz)에서 WNS가 83095.5ps(margin 83.1%)라 매우 널널하다.
- 30000ps(33.3MHz)에서도 WNS가 13095.5ps, margin 43.7%로 여전히 안전한 영역이다. 같은 30000ps 조건의 mode0(margin 31.7%)보다도 여유가 크다.
- critical path는 두 조건 모두 GEMM MAC 내부가 아니라 CPU 경로(u_inst_reg_instr_out_reg[28] -> u_accumulator_acc_out_reg[30])에서 동일하게 잡혔고, cells/area도 482747 / 40082996으로 동일하다.
- full-system step3 area는 약 40.08M sq um로 매우 크다. 이는 memory까지 standard cell로 합성된 영향이 커서, step1/step2의 accelerator-only 결과와 직접 비교하면 안 된다.
- margin이 43.7%로 충분히 크기 때문에, 10MHz보다 33.3MHz(30000ps)를 mode1의 정상 동작 주파수로 보는 것이 더 타당한 해석이다. 10000ps급 이상 sweep도 추가로 시도해볼 여지가 있으나, step3 합성 시간이 길어 현재는 두 지점만 기록한다.

## 권장 동작점

| period | freq(MHz) | margin(%) | P&R 안전도 |
| ---: | ---: | ---: | --- |
| 100ns | 10.0 | 83.1 | 매우 안전(보수적 기준점) |
| 30ns | 33.3 | 43.7 | 안전, 정상 동작 주파수 후보 |

권장: mode1 step3는 30000ps(33.3MHz)를 정상 동작 주파수로 사용한다. WNS margin이 43.7%로 충분히 안전하기 때문이다. 100000ps(10MHz)는 보수적 기준점으로 함께 남긴다. step3 합성 시간이 길기 때문에, 10000ps급 추가 sweep은 Nitro에서 실제로 필요한 후보가 생겼을 때만 수행한다.

## Critical path

| period(ps) | startpoint | endpoint | logic depth |
| ---: | --- | --- | ---: |
| 100000 | u_system/u_cpu/u_inst_reg_instr_out_reg[28]/Q | u_system/u_cpu/u_accumulator_acc_out_reg[30]/DATA | 73 |
| 30000 | u_system/u_cpu/u_inst_reg_instr_out_reg[28]/Q | u_system/u_cpu/u_accumulator_acc_out_reg[30]/DATA | 73 |

## 검증 메모

- mode1_100000ps
  - timing: step3_mode1_timing.rpt, Clock shift 100000.0ps, Slack 83095.5ps
  - area: step3_mode1_area.rpt, Cells 482747, Cell Area 40082996
  - power: step3_mode1_power.rpt, Total Power 1245425.625uW = 1245425625nW
- mode1_30000ps
  - timing: step3_mode1_timing.rpt, Clock shift 30000.0ps, Slack 13095.5ps
  - area: step3_mode1_area.rpt, Cells 482747, Cell Area 40082996
  - power: step3_mode1_power.rpt, Total Power 4150035.0uW = 4150035000nW
