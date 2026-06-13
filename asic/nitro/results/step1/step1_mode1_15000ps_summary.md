# Nitro P&R Summary - step1 / mode1 / 15000ps

Generated: 2026-06-13

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step1 |
| Mode | mode1 |
| Top Module | `step1_gemm_accelerator_top_mode1` |
| Clock Period | 15000 ps (15 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25C |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 15000.0 ps |
| Clock Network Latency | 979.0 ps |
| Data Arrival Time | 14897.0 ps |
| Data Required Time | 15739.0 ps |
| **WNS (Worst Negative Slack)** | **+846 ps** |

**타이밍 만족.** Critical path는 `u_gemm/u_mmio_r_n_reg[1]`에서 `u_gemm/u_mac/c_wdata_reg[31]`로 이어지는 경로이다. MMIO 설정값에서 MAC write-data 레지스터로 이어지는 1-MAC 연산 경로가 post-route 기준 최장 경로로 잡혔다.

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 332,024 um^2 (90.85%) |
| Buffers / Inverters | 9,845.96 um^2 (2.69%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **365,438 um^2** |
| **Total Utilization** | **~93.5%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---:|---:|
| Registers (DFF) | 1077 | 24.26% |
| Complex Cells | 1897 | 42.74% |
| Inverters | 311 | 7.00% |
| Buffers | 122 | 2.74% |
| Clock Cells | 92 | - |
| **Total Leaf Cells** | **4438** | 100% |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---:|---:|
| Total Nets | 4675 | 100% |
| 1 Fanout | 2437 | 52.12% |
| 2 Fanouts | 1435 | 30.69% |
| 3~30 Fanouts | 555 | 11.87% |
| 30~127 Fanouts | 21 | 0.44% |
| Orphaned | 227 | 4.85% |

---

## 6. 출력 파일

| 파일 | 설명 |
|---|---|
| `step1_mode1_15000ps_nitro.v` | Post-route gate-level netlist |
| `step1_mode1_15000ps.sdf` | Back-annotation용 delay 정보. `*.sdf`는 gitignore 대상이므로 repo에는 없을 수 있음 |
| `step1_mode1_15000ps_timing.rpt` | Timing 분석 결과 |
| `step1_mode1_15000ps_area.rpt` | Area / Utilization 결과 |

---

## 7. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS >= 0) | 통과, +846 ps 여유 |
| Utilization | 약 93.5%, 상당히 높은 편 |
| Unplaced Cells | 0 |
| Multi Driver Nets | 0 |

> WNS가 +846 ps로 timing은 안정적으로 통과했다. 다만 utilization이 약 93.5%로 높기 때문에, 동일 조건에서 면적을 더 줄이는 실험은 routing congestion이나 timing 악화를 유발할 수 있다. 현재 결과는 step1 mode1 15000ps의 post-route 기준 유효 후보로 볼 수 있다.
