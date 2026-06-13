# Nitro P&R Summary — step1 / mode4 / 15000ps

Generated: 2026-06-13

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step1 |
| Mode | mode4 |
| Top Module | `step1_gemm_accelerator_top_mode4` |
| Clock Period | 15000 ps (15 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25°C |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 15000.0 ps |
| Clock Network Latency | 997.0 ps |
| Data Arrival Time | 15068.0 ps |
| Data Required Time | 15768.0 ps |
| **WNS (Worst Negative Slack)** | **+710 ps ✅** |

**타이밍 만족.** Critical path는 `u_gemm/u_mmio_r_k_reg[2]` → `u_gemm/u_mac/acc1_reg[20]` 경로 (MAC 연산/누산 경로).

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 431,638 μm² (85.12%) |
| Buffers / Inverters | 17,875.5 μm² (3.52%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **507,047 μm²** |
| **Total Utilization** | **~88.6%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---|---|
| Registers (DFF) | 1174 | 17.25% |
| Complex Cells | 2600 | 38.21% |
| Inverters | 709 | 10.42% |
| Buffers | 129 | 1.89% |
| Clock Cells | 87 | - |
| **Total Leaf Cells** | **6804** | 100% |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---|---|
| Total Nets | 6993 | 100% |
| 1 Fanout | 3562 | 50.93% |
| 2 Fanouts | 2155 | 30.81% |
| 3~30 Fanouts | 1061 | 15.17% |
| 30~127 Fanouts | 41 | 0.58% |
| Orphaned | 174 | 2.48% |

---

## 6. 출력 파일

| 파일 | 설명 |
|---|---|
| `step1_mode4_15000ps_nitro.v` | Post-route gate-level netlist |
| `step1_mode4_15000ps_timing.rpt` | Timing 분석 결과 |
| `step1_mode4_15000ps_area.rpt` | Area / Utilization 결과 |

---

## 7. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS ≥ 0) | ✅ +710 ps 여유 |
| Utilization | ✅ ~89% (적정 범위) |
| Unplaced Cells | ✅ 0 |
| Multi Driver Nets | ✅ 0 |

> WNS +710 ps 여유가 있으므로 현재 결과를 post-route 검증에 사용할 수 있습니다.