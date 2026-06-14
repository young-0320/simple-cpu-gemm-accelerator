# Nitro P&R Summary — step3_demo / mode0 / 30000ps

Generated: 2026-06-14

---

## 1. 설정

| 항목 | 값 |
|---|---|
| Step | step3_demo |
| Mode | mode0 |
| Top Module | `step3_system_top_mode0` |
| Clock Period | 30000 ps (30 ns) |
| Process | Generic 250nm |
| Corner | slow / TT 2.5V 25°C |
| double_backed | false |

---

## 2. Timing 결과

| 항목 | 값 |
|---|---|
| Clock Period | 30000.0 ps |
| Clock Network Latency | 2042.0 ps |
| Data Arrival Time | 26501.0 ps |
| Data Required Time | 31822.0 ps |
| **WNS (Worst Negative Slack)** | **+5331 ps ✅** |

**타이밍 만족.** Critical path는 `u_gemm/u_mac/k_reg[2]` → `u_gemm/u_mac/acc_reg[31]` 경로 (MAC accumulator 내부, gemm_local_buffer 경유).

---

## 3. Area / Utilization 결과

| 항목 | 값 |
|---|---|
| Standard Cells | 3,037,620 μm² (52.58%) |
| Buffers / Inverters | 108,958 μm² (1.88%) |
| Filler Cells | 0 |
| **Placeable Row Area** | **5,776,970 μm²** |
| **Total Utilization** | **~54.5%** |

---

## 4. Cell 통계

| Cell 종류 | Count | 비율 |
|---|---|---|
| Registers (DFF) | 9400 | 23.27% |
| Complex Cells | 22646 | 56.06% |
| Inverters | 2079 | 5.14% |
| Buffers | 2439 | 6.03% |
| Clock Cells | 321 | - |
| **Total Leaf Cells** | **40395** | 100% |
| Unplaced Cells | 0 | ✅ |

---

## 5. Net 통계

| 항목 | Count | 비율 |
|---|---|---|
| Total Nets | 40698 | 100% |
| 1 Fanout | 25420 | 62.46% |
| 2 Fanouts | 2817 | 6.92% |
| 3~30 Fanouts | 11712 | 28.77% |
| 30~127 Fanouts | 135 | 0.33% |
| Orphaned | 614 | 1.51% |
| Multi Driver | 0 | ✅ |

---

## 6. Routing 결과

| 항목 | 값 |
|---|---|
| Total Wire Length | 6.77 m |
| Non-preferred direction | 1.44% |
| Total Wires | 458,260 |
| Total Vias | 359,330 |
| Double Vias | 78.84% |
| Multi Vias | 0.00% |
| **Final Routing Violations** | **0 ✅** |
| **DRC Violations** | **0 ✅** |
| **Opens** | **0 ✅** |

---

## 7. 출력 파일

| 파일 | 설명 |
|---|---|
| `step3_demo_mode0_30000ps_nitro.v` | Post-route gate-level netlist |
| `step3_demo_mode0_30000ps.sdf` | Back-annotation용 delay 정보 |
| `step3_demo_mode0_30000ps_timing.rpt` | Timing 분석 결과 |
| `step3_demo_mode0_30000ps_area.rpt` | Area / Utilization 결과 |

---

## 8. 종합 평가

| 항목 | 상태 |
|---|---|
| Timing (WNS ≥ 0) | ✅ +5331 ps 여유 |
| Utilization | ✅ ~54.5% |
| Unplaced Cells | ✅ 0 |
| Multi Driver Nets | ✅ 0 |
| Routing Violations | ✅ 0 |

> WNS +5331 ps로 여유가 매우 큼 (30000ps 중 5331ps, 약 17.8% 여유). 더 짧은 clock period (예: 25000ps)로 재합성/재P&R 도전 가능. Utilization은 ~54.5%로 여유 있는 편이며, chip area를 줄여 util 65~70% 수준으로 최적화할 여지가 있음.

---

## 9. 진행 이력 (참고)

|index| chip area | double_backed | core_cell_util | Util | Violations |
|---|---|---|---|---|---|
| 1   | 27,000,000a | true | 80 | --     | --            | -> error
| 2   | 30,000,000a | true | 80 | 38.99% | 31 (short 12) | -> 합성은 완료됐지만 violations 존재/chip area의 문제가 아님을 확인
| 3 (최종) | 26,000,000a | false | 70 | 52.58% | **0** ✅ | -> metal1,3 배선 간격도 11500으로 줄임
-> 이후 util 올리기 위한 시도
| 4   | 25,000,000a | true | 80 | --     |       --      | -> error
| 5   | 25,000,000a | true | 70 | --     |       --      | -> error

`double_backed false` 전환, metal 1,3 배선 간격 13500 > 11500 수정 후 Placeable Row Area가 약 2배 증가하면서 배선 공간이 확보되어 violation이 모두 해소됨.
