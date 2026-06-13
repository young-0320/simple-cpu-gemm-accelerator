# Nitro Step1/Step2 P&R 비교 분석 리포트

작성일: 2026-06-13

## 1. 목적

본 문서는 `simple-cpu-gemm-accelerator`의 Nitro P&R 결과 중 `step1`과 `step2` 구현을 비교하여, 최종 제출 구조로 어떤 구현을 선택하는 것이 타당한지 판단하기 위한 분석 리포트이다.

비교 대상은 15000 ps, 즉 15 ns clock period에서 수행된 Nitro 결과이다. `step1`은 `mode0`, `mode1`, `mode4` 결과가 존재하고, `step2`는 `mode1`, `mode4` 결과가 존재한다. 따라서 직접적인 step 간 비교는 같은 mode가 존재하는 `mode1`과 `mode4`를 중심으로 수행한다. `step1 mode0`은 step1 내부 참고 결과로만 사용한다.

## 2. 분석 대상 산출물

| 구분 | Summary 파일 | 주요 원본 리포트 |
|---|---|---|
| step1 mode0 | `asic/nitro/results/step1/step1_mode0_15000ps_summary.md` | `mode0_15000ps/*_timing.rpt`, `*_area.rpt` |
| step1 mode1 | `asic/nitro/results/step1/step1_mode1_15000ps_summary.md` | `mode1_15000ps/*_timing.rpt`, `*_area.rpt` |
| step1 mode4 | `asic/nitro/results/step1/step1_mode4_15000ps_summary.md` | `mode4_15000ps/*_timing.rpt`, `*_area.rpt` |
| step2 mode1 | `asic/nitro/results/step2/step2_mode1_15000ps_summary.md` | `mode1_15000ps/*_timing.rpt`, `*_area.rpt` |
| step2 mode4 | `asic/nitro/results/step2/step2_mode4_15000ps_summary.md` | `mode4_15000ps/*_timing.rpt`, `*_area.rpt` |

## 3. 전체 결과 요약

| 구현 | WNS | Standard Cell Area | Total Utilization | Leaf Cells | Total Nets | Orphaned Nets | 판정 |
|---|---:|---:|---:|---:|---:|---:|---|
| step1 mode0 | +6 ps | 410,661 um^2 | ~82.5% | 6,560 | 7,008 | 422 | timing 여유가 거의 한계 |
| step1 mode1 | +846 ps | 332,024 um^2 | ~93.5% | 4,438 | 4,675 | 227 | timing은 좋으나 utilization이 높음 |
| step1 mode4 | +710 ps | 431,638 um^2 | ~88.6% | 6,804 | 6,993 | 174 | 통과하나 step2 대비 규모가 큼 |
| step2 mode1 | +755 ps | 318,042 um^2 | ~84.5% | 4,263 | 4,441 | 154 | timing/area/복잡도 균형 우수 |
| step2 mode4 | +685 ps | 419,734 um^2 | ~86.4% | 6,702 | 6,748 | 91 | mode4 중 가장 균형적 |

모든 비교 대상은 15 ns 기준에서 WNS가 양수이므로 timing은 만족한다. 그러나 최종 구조 선택은 단순히 WNS만으로 판단하기 어렵다. 실제 P&R 품질은 timing 여유, cell area, cell count, net count, orphaned net, utilization 여유를 함께 보아야 한다.

## 4. Mode1 직접 비교

| 항목 | step1 mode1 | step2 mode1 | 우세 |
|---|---:|---:|---|
| WNS | +846 ps | +755 ps | step1 |
| Standard Cell Area | 332,024 um^2 | 318,042 um^2 | step2 |
| Total Utilization | ~93.5% | ~84.5% | step2 |
| Leaf Cells | 4,438 | 4,263 | step2 |
| Total Nets | 4,675 | 4,441 | step2 |
| Orphaned Nets | 227 | 154 | step2 |
| Clock Cells | 92 | 46 | step2 |

`step1 mode1`은 WNS가 +846 ps로 `step2 mode1`의 +755 ps보다 91 ps 더 크다. 따라서 순수 timing margin만 보면 step1이 조금 더 유리하다.

하지만 `step2 mode1`은 standard cell area가 더 작고, leaf cell 수와 net 수가 모두 감소했다. 특히 utilization이 약 93.5%에서 약 84.5%로 낮아져 placement/routing 여유가 더 크다. ASIC P&R에서 utilization은 높다고 항상 좋은 값이 아니다. 일정 수준 이상으로 높아지면 routing congestion, ECO, hold/timing repair, clock tree 수정 여지가 줄어들 수 있다.

따라서 `mode1`에서는 step1이 WNS만 우세하지만, step2가 더 작은 cell area와 더 낮은 구현 복잡도를 가지면서도 충분한 timing margin을 유지한다. 최종 구현 후보로는 `step2 mode1`이 더 균형적이다.

## 5. Mode4 직접 비교

| 항목 | step1 mode4 | step2 mode4 | 우세 |
|---|---:|---:|---|
| WNS | +710 ps | +685 ps | step1, 근소 |
| Standard Cell Area | 431,638 um^2 | 419,734 um^2 | step2 |
| Total Utilization | ~88.6% | ~86.4% | step2 |
| Leaf Cells | 6,804 | 6,702 | step2 |
| Total Nets | 6,993 | 6,748 | step2 |
| Orphaned Nets | 174 | 91 | step2 |
| Clock Cells | 87 | 115 | step1 |

`mode4`에서도 step1의 WNS가 +710 ps로 step2의 +685 ps보다 25 ps 크다. 그러나 이 차이는 15 ns 목표 기준에서 크지 않으며, 두 구현 모두 충분히 timing을 만족한다.

반면 step2는 standard cell area, leaf cell 수, total net 수, orphaned net 수에서 모두 개선된다. 특히 orphaned net이 174개에서 91개로 줄어든 점은 netlist와 physical implementation 관점에서 더 정돈된 구조임을 보여준다.

`step2 mode4`는 clock cell 수가 step1보다 많지만, 전체 cell 수와 area는 오히려 줄어들었다. 따라서 clock tree 관련 overhead가 일부 증가했더라도 전체 구현 품질을 해칠 정도는 아니며, 종합적으로는 step2가 더 안정적인 mode4 결과로 판단된다.

## 6. Step1 Mode0 참고 해석

`step1 mode0`은 step2에 대응되는 직접 비교 대상은 아니지만, step1 계열의 특성을 보여주는 참고 결과로 볼 수 있다.

`step1 mode0`은 WNS가 +6 ps로 매우 작다. timing violation은 아니지만, 15 ns 조건에서 사실상 한계에 가까운 결과이다. 또한 total nets가 7,008개, orphaned nets가 422개로 비교 대상 중 가장 크다. 이는 step1 계열 일부 구조가 timing 및 net complexity 측면에서 여유가 크지 않다는 점을 보여준다.

따라서 `step1 mode0`은 최종 제출 후보라기보다 baseline 또는 참고용 구현으로 보는 것이 적절하다.

## 7. 종합 판단

Step1과 Step2는 모두 15 ns timing target을 만족한다. 그러나 최종 제출 구조 관점에서는 Step2가 대부분의 물리 구현 지표에서 더 우수하다.

Step1의 장점은 일부 mode에서 WNS가 더 크다는 점이다. 하지만 Step2는 WNS가 조금 줄어든 대신, cell area, leaf cell count, net count, orphaned net, utilization 여유에서 전반적으로 더 좋은 결과를 보인다. 즉 Step2는 timing을 충분히 만족하면서도 더 작은 논리 규모와 더 낮은 배선 복잡도를 달성한 구조이다.

특히 `step2 mode1`은 WNS +755 ps로 timing margin이 충분하고, `step1 mode1` 대비 standard cell area와 cell/net count를 줄였다. `step2 mode4` 역시 WNS +685 ps를 확보하면서 `step1 mode4`보다 area와 net complexity를 낮췄다.

따라서 본 프로젝트의 최종 Nitro P&R 구조는 Step2를 기준으로 선택하는 것이 타당하다.

## 8. 추가 최적화 필요성

현재 Step2 결과는 이미 제출 가능한 수준으로 안정적이다. WNS가 충분히 양수이고, unplaced cell과 multi-driver net이 0이며, utilization도 과도하게 높지 않다.

추가 최적화는 가능하다. 예를 들어 clock period를 14000 ps 근처로 줄여보거나, floorplan/core area를 더 조여 utilization을 높이는 실험을 할 수 있다. 그러나 이러한 작업은 현재 결과를 제출하기 위해 반드시 필요한 작업은 아니다.

오히려 제출 직전 단계에서 RTL을 크게 수정하면 검증 리스크가 증가할 수 있다. 현재 결과는 Step2 architecture가 이미 좋은 구조이며, 추가 최적화는 future work로 남기는 것이 합리적이다.

## 9. 최종 결론

Step2 architecture는 Step1 대비 대부분의 Nitro P&R 지표에서 더 우수하다. Step1은 일부 mode에서 WNS가 조금 더 크지만, Step2는 충분한 timing margin을 유지하면서 더 작은 area, 더 적은 cell/net 수, 더 낮은 orphaned net, 더 안정적인 utilization을 보인다.

따라서 본 프로젝트에서는 Step2를 최종 구현 architecture로 채택한다. 현재 Step2 결과는 15 ns timing target을 안정적으로 만족하므로, 추가 RTL 수정 없이도 최종 제출 결과로 사용하기에 충분하다. 추가 최적화는 필수 작업이 아니라 향후 개선 과제로 정리하는 것이 적절하다.
