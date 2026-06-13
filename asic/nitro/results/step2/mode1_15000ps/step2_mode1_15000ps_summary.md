# Nitro P&R Summary — step2 / mode1 / 15000ps

Generated: 2026-06-12

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step2 |
| Mode | mode1 |
| Top Module | `step2_gemm_accelerator_top_mode1` |
| Clock Period | 15000 ps (15 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25°C |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 15000.0 ps |
| Clock Network Latency | 908.0 ps |
| Data Arrival Time | 14927.0 ps |
| Data Required Time | 15676.0 ps |
| **WNS (Worst Negative Slack)** | **+755 ps ✅** |

**타이밍 만족.** Critical path는 `u_gemm/u_mmio_r_k_reg[1]` → `u_gemm/u_mac/c_wdata_reg[30]` 경로 (MAC 연산 내부).

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 318,042 μm² (82.28%) |
| Buffers / Inverters | 8,504.6 μm² (2.20%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **386,535 μm²** |
| **Total Utilization** | **~84.5%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---|---|
| Registers (DFF) | 1024 | 24.02% |
| Complex Cells | 1840 | 43.16% |
| Inverters | 314 | 7.36% |
| Buffers | 73 | 1.71% |
| Clock Cells | 46 | - |
| **Total Leaf Cells** | **4263** | 100% |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---|---|
| Total Nets | 4441 | 100% |
| 1 Fanout | 2347 | 52.84% |
| 2 Fanouts | 1347 | 30.33% |
| 3~30 Fanouts | 570 | 12.83% |
| 30~127 Fanouts | 23 | 0.51% |
| Orphaned | 154 | 3.46% |

---

## 6. 출력 파일

| 파일 | 설명 |
|---|---|
| `step2_mode1_15000ps_nitro.v` | Post-route gate-level netlist |
| `step2_mode1_15000ps.sdf` | Back-annotation용 delay 정보 |
| `step2_mode1_15000ps_timing.rpt` | Timing 분석 결과 |
| `step2_mode1_15000ps_area.rpt` | Area / Utilization 결과 |

---

## 7. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS ≥ 0) | ✅ +755 ps 여유 |
| Utilization | ✅ ~84% (적정 범위) |
| Unplaced Cells | ✅ 0 |
| Multi Driver Nets | ✅ 0 |

> WNS +755 ps 여유가 있으므로 clock period를 더 줄이거나 (예: 14000ps) 현재 결과를 post-route 시뮬레이션에 사용 가능.
