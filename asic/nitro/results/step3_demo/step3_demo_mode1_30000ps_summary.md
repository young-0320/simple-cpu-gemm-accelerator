# Nitro P&R Summary — step3_demo / mode1 / 30000ps

Generated: 2026-06-14

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step3_demo |
| Mode | mode1 |
| Top Module | `step3_system_top_mode1` |
| Clock Period | 30000 ps (30 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25°C |
| double_backed | false |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 30000.0 ps |
| Clock Network Latency | 2030.0 ps |
| Data Arrival Time | 23183.0 ps |
| Data Required Time | 31802.0 ps |
| **WNS (Worst Negative Slack)** | **+8643 ps ✅** |

**타이밍 만족.** Critical path는 `u_cpu/u_inst_reg_instr_out_reg[29]` → `u_cpu/u_accumulator_acc_out_reg[30]` 경로 (CPU ALU 연산 경로).

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 2,957,240 μm² (51.18%) |
| Buffers / Inverters | 101,701 μm² (1.76%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **5,777,440 μm²** |
| **Total Utilization** | **~52.9%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---|---|
| Registers (DFF) | 9401 | 24.58% |
| Complex Cells | 21841 | 57.10% |
| Inverters | 1499 | 3.91% |
| Buffers | 2581 | 6.74% |
| Clock Cells | 355 | - |
| **Total Leaf Cells** | **38246** | 100% |
| Unplaced Cells | 0 | ✅ |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---|---|
| Total Nets | 38391 | 100% |
| 1 Fanout | 24344 | 63.41% |
| 2 Fanouts | 2104 | 5.48% |
| 3~30 Fanouts | 11323 | 29.49% |
| 30~127 Fanouts | 130 | 0.33% |
| Orphaned | 490 | 1.27% |
| Multi Driver | 0 | ✅ |

---

## 6. 출력 파일

| 파일 | 설명 |
|---|---|
| `step3_demo_mode1_30000ps_nitro.v` | Post-route gate-level netlist |
| `step3_demo_mode1_30000ps.sdf` | Back-annotation용 delay 정보 |
| `step3_demo_mode1_30000ps_timing.rpt` | Timing 분석 결과 |
| `step3_demo_mode1_30000ps_area.rpt` | Area / Utilization 결과 |

---

## 7. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS ≥ 0) | ✅ +8643 ps 여유 |
| Utilization | ✅ ~52.9% |
| Unplaced Cells | ✅ 0 |
| Multi Driver Nets | ✅ 0 |

> WNS +8643 ps로 여유가 매우 큼 (30000ps 중 8643ps, 약 28.8% 여유). mode0(+5331ps) 대비 critical path가 CPU/ALU 경로로 이동했으며 slack도 더 여유로움. 더 짧은 clock period로 재합성/재P&R 도전 가능.

---

## 8. mode0 vs mode1 비교

| 항목 | mode0 | mode1 |
|---|---|---|
| WNS | +5331 ps | +8643 ps |
| Critical Path | gemm MAC accumulator | CPU ALU/accumulator |
| Total Leaf Cells | 40395 | 38246 |
| Standard Cell Area | 3,037,620 μm² | 2,957,240 μm² |
| Clock Cells | 321 | 355 |
| Utilization | ~54.5% | ~52.9% |
