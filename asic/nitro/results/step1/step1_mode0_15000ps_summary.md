# Nitro P&R Summary — step1 / mode0 / 15000ps

Generated: 2026-06-13

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step1 |
| Mode | mode0 |
| Top Module | `step1_gemm_accelerator_top_mode0` |
| Clock Period | 15000 ps (15 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25°C |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 15000.0 ps |
| Clock Network Latency | 813.0 ps |
| Data Arrival Time | 15581.0 ps |
| Data Required Time | 15581.0 ps |
| **WNS (Worst Negative Slack)** | **+6 ps ✅** |

**타이밍 만족.** Critical path는 `u_gemm/u_mmio_r_n_reg[0]` → `u_gemm/u_mac/acc_reg[19]` 경로 (MAC 연산/누산 경로).

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 410,661 μm² (78.97%) |
| Buffers / Inverters | 18,313.3 μm² (3.52%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **519,968 μm²** |
| **Total Utilization** | **~82.5%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---|---|
| Registers (DFF) | 1076 | 16.4% |
| Complex Cells | 2594 | 39.54% |
| Inverters | 749 | 11.41% |
| Buffers | 124 | 1.89% |
| Clock Cells | 76 | - |
| **Total Leaf Cells** | **6560** | 100% |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---|---|
| Total Nets | 7008 | 100% |
| 1 Fanout | 3476 | 49.6% |
| 2 Fanouts | 2035 | 29.03% |
| 3~30 Fanouts | 1035 | 14.76% |
| 30~127 Fanouts | 40 | 0.57% |
| Orphaned | 422 | 6.02% |

---

## 6. 출력 파일

| 파일 | 설명 |
|---|---|
| `step1_mode0_15000ps_nitro.v` | Post-route gate-level netlist |
| `step1_mode0_15000ps_timing.rpt` | Timing 분석 결과 |
| `step1_mode0_15000ps_area.rpt` | Area / Utilization 결과 |

---

## 7. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS ≥ 0) | ✅ +6 ps 여유 |
| Utilization | ✅ ~82% (적정 범위) |
| Unplaced Cells | ✅ 0 |
| Multi Driver Nets | ✅ 0 |

> WNS +6 ps 여유가 있으므로 현재 결과를 post-route 검증에 사용할 수 있습니다.