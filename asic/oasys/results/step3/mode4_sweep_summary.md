# Oasys Synthesis Frequency Sweep - step3 (MAC_MODE=4, full-system)

대상: step3 full-system, MAC_MODE=4
합성 도구: Oasys-RTL
측정 기준: top area/power/timing report
작성일: 2026-06-13

## Sweep 결과

margin(%) = WNS / period x 100.

| report folder | period(ps) | freq(MHz) | WNS(ps) | margin(%) |  cells | area(sq um) | total_power(nW) | result |
| ------------- | ---------: | --------: | ------: | --------: | -----: | ----------: | --------------: | ------ |
| mode4_35000ps |      35000 |      28.6 | 18095.5 |      51.7 | 482747 |    40082996 |      3557242250 | pass   |

- WNS = worst slack. 양수면 timing pass, 음수면 timing violation.
- margin(%) = WNS / period x 100.
- result: WNS >= 0이면 pass, WNS < 0이면 fail.

## 해석

- 35000ps(28.6MHz)에서 WNS가 18095.5ps, margin이 51.7%라 timing 여유는 충분하다.
- critical path는 mode1과 동일하게 CPU 경로에서 잡혔다.
- area/cell 수가 mode1_100000ps와 동일하게 나온다.

## 권장 동작점

| period | freq(MHz) | margin(%) | P&R 안전도 |
| -----: | --------: | --------: | ---------- |
|   35ns |      28.6 |      51.7 | 안전       |

권장: 현재 결과는 35000ps 고주파 참고 결과로 취급한다. 10MHz 기준 mode4 결과가 필요하면 폴더명만 믿지 말고 SDC를 100000ps로 다시 맞춘 뒤 재합성하는 것이 좋다.

## Critical path

| period(ps) | startpoint                                    | endpoint                                          | logic depth |
| ---------: | --------------------------------------------- | ------------------------------------------------- | ----------: |
|      35000 | u_system/u_cpu/u_inst_reg_instr_out_reg[28]/Q | u_system/u_cpu/u_accumulator_acc_out_reg[30]/DATA |          73 |

## 검증 메모

- mode4_35000ps
  - timing: step3_mode4_timing.rpt, Clock shift 35000.0ps, Slack 18095.5ps
  - area: step3_mode4_area.rpt, Cells 482747, Cell Area 40082996
  - power: step3_mode4_power.rpt, Total Power 3557242.25uW = 3557242250nW
