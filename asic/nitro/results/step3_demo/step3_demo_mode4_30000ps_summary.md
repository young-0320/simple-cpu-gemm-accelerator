# Nitro P&R Summary — step3_demo / mode4 / 30000ps

Generated: 2026-06-14

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step3_demo |
| Mode | mode4 |
| Top Module | `step3_system_top_mode4` |
| Clock Period | 30000 ps (30 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25°C |
| double_backed | false |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 30000.0 ps |
| Clock Network Latency | 2108.0 ps |
| Data Arrival Time | 23367.0 ps |
| Data Required Time | 31867.0 ps |
| **WNS (Worst Negative Slack)** | **+8552 ps ✅** |

**타이밍 만족.** Critical path는 `u_cpu/u_inst_reg_instr_out_reg[31]` → `u_cpu/u_accumulator_acc_out_reg[30]` 경로 (CPU ALU/accumulator 경로).

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 3,038,920 μm² (52.45%) |
| Buffers / Inverters | 102,772 μm² (1.77%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **5,793,630 μm²** |
| **Total Utilization** | **~54.2%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---|---|
| Registers (DFF) | 9498 | 23.79% |
| Complex Cells | 22580 | 56.57% |
| Inverters | 1885 | 4.72% |
| Buffers | 2359 | 5.91% |
| Clock Cells | 388 | - |
| **Total Leaf Cells** | **39909** | 100% |
| Unplaced Cells | 0 | ✅ |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---|---|
| Total Nets | 39941 | 100% |
| 1 Fanout | 25027 | 62.65% |
| 2 Fanouts | 2903 | 7.26% |
| 3~30 Fanouts | 11437 | 28.63% |
| 30~127 Fanouts | 164 | 0.41% |
| Orphaned | 410 | 1.02% |
| Multi Driver | 0 | ✅ |

---

## 6. 출력 파일

| 파일 | 설명 |
|---|---|
| `step3_demo_mode4_30000ps_nitro.v` | Post-route gate-level netlist |
| `step3_demo_mode4_30000ps.sdf` | Back-annotation용 delay 정보 |
| `step3_demo_mode4_30000ps_timing.rpt` | Timing 분석 결과 |
| `step3_demo_mode4_30000ps_area.rpt` | Area / Utilization 결과 |

---

## 7. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS ≥ 0) | ✅ +8552 ps 여유 |
| Utilization | ✅ ~54.2% |
| Unplaced Cells | ✅ 0 |
| Multi Driver Nets | ✅ 0 |

> WNS +8552 ps로 여유가 매우 큼 (30000ps 중 8552ps, 약 28.5% 여유). mode1(+8643ps)과 거의 동일한 수준이며, 둘 다 critical path가 CPU ALU/accumulator 경로에 위치함.

---

## 8. mode0 / mode1 / mode4 비교

| 항목 | mode0 | mode1 | mode4 |
|---|---|---|---|
| WNS | +5331 ps | +8643 ps | +8552 ps |
| Critical Path | gemm MAC accumulator | CPU ALU/accumulator | CPU ALU/accumulator |
| Total Leaf Cells | 40395 | 38246 | 39909 |
| Standard Cell Area | 3,037,620 μm² | 2,957,240 μm² | 3,038,920 μm² |
| Clock Cells | 321 | 355 | 388 |
| Utilization | ~54.5% | ~52.9% | ~54.2% |
