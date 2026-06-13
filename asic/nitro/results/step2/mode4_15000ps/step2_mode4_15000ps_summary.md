# Nitro P&R Summary — step2 / mode4 / 15000ps

Generated: 2026-06-13

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step2 |
| Mode | mode4 |
| Top Module | `step2_gemm_accelerator_top_mode4` |
| Clock Period | 15000 ps (15 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25°C |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 15000.0 ps |
| Clock Network Latency | 909.0 ps |
| Data Arrival Time | 14999.0 ps |
| Data Required Time | 15677.0 ps |
| **WNS (Worst Negative Slack)** | **+685 ps ✅** |

**타이밍 만족.** Critical path는 `u_gemm/u_mac/i_reg[0]` → `u_gemm/u_mac/acc1_reg[30]` 경로 (MAC 연산 내부).

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 419,734 μm² (82.75%) |
| Buffers / Inverters | 18,639.3 μm² (3.67%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **507,197 μm²** |
| **Total Utilization** | **~86.4%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---|---|
| Registers (DFF) | 1121 | 16.72% |
| Complex Cells | 2540 | 37.89% |
| Inverters | 714 | 10.65% |
| Buffers | 152 | 2.26% |
| Clock Cells | 115 | - |
| **Total Leaf Cells** | **6702** | 100% |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---|---|
| Total Nets | 6748 | 100% |
| 1 Fanout | 3471 | 51.43% |
| 2 Fanouts | 2069 | 30.66% |
| 3~30 Fanouts | 1076 | 15.94% |
| 30~127 Fanouts | 41 | 0.60% |
| Orphaned | 91 | 1.34% |

---

## 6. 출력 파일

| 파일 | 설명 |
|---|---|
| `step2_mode4_15000ps_nitro.v` | Post-route gate-level netlist |
| `step2_mode4_15000ps.sdf` | Back-annotation용 delay 정보 |
| `step2_mode4_15000ps_timing.rpt` | Timing 분석 결과 |
| `step2_mode4_15000ps_area.rpt` | Area / Utilization 결과 |

---

## 7. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS ≥ 0) | ✅ +685 ps 여유 |
| Utilization | ✅ ~86% (적정 범위) |
| Unplaced Cells | ✅ 0 |
| Multi Driver Nets | ✅ 0 |

> WNS +685 ps 여유가 있으나 mode1(+755ps) 대비 조금 타이트함. mode4는 cell 수(6702)가 mode1(4263)보다 많아 설계 규모가 더 큰 것을 확인할 수 있음.

---

## 8. mode1 vs mode4 비교

| 항목 | mode1 | mode4 |
|---|---|---|
| WNS | +755 ps | +685 ps |
| Total Leaf Cells | 4263 | 6702 |
| Standard Cell Area | 318,042 μm² | 419,734 μm² |
| Clock Cells | 46 | 115 |
| Utilization | ~84.5% | ~86.4% |
