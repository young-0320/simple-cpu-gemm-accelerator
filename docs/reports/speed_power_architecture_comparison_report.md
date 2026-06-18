# 속도/전력 기준 아키텍처 비교 리포트 (Dual vs Single memory, 1-MAC vs 4-MAC)

작성일: 2026-06-18

## 1. 목적

`project2.md` 과제 2번 요구사항은 "Oasys와 Nitro로 합성 결과 분석 (**속도 및 전력 소모**)"이다.
본 문서는 이 기준(속도, 전력)으로 GEMM accelerator의 메모리 구조(dual-port vs
single-port)와 MAC datapath(1-MAC vs 4-MAC)를 비교해, 어떤 조합이 가장
최적화됐는지 판단한다.

`docs/reports/nitro_step1_step2_comparison_report.md`가 이미 step1(dual)/step2
(single) 비교를 다뤘지만, 그 문서는 **Nitro P&R의 물리적 구현 품질**
(area, leaf cell 수, net 수, orphaned net, utilization)을 기준으로 비교해
"step2(single)를 최종 채택"이라고 결론 내렸다. 그 분석과 본 문서는 서로 다른
기준을 사용하므로 결론이 다를 수 있다 — 자세한 내용은 5절에서 다룬다.

## 2. 분석 대상 및 비교 기준점

| 구조 | 소스 | MAC 모드 |
|---|---|---|
| dual-memory, accelerator-only | `asic/oasys/results/step1/` (`rtl_v2`) | mode0(AT), mode1(1-MAC), mode4(4-MAC) |
| single-memory, accelerator-only | `asic/oasys/results/step2/` (`rtl`) | mode1(1-MAC), mode4(4-MAC) — AT 없음 |

비교 기준점은 **15000 ps (66.7 MHz)**로 고정한다. 이 지점은 dual/single,
mode0/1/4 전부에서 Oasys sweep과 Nitro post-route 양쪽이 timing pass를
확인한 유일한 공통 지점이다(`asic/nitro/results/step1`, `step2`의
`*_15000ps_summary.md` 참고).

cycle 수는 동일 워크로드(M=N=K=4)를 돌린 Verilator 결과에서 가져온다.

| 구조 | 소스 | load | compute | store | busy(=load+compute+store) |
|---|---|---:|---:|---:|---:|
| single + 1-MAC | `sim/results/power/step2_mode1_directed006/report.md` | 51 | 68 | 19 | 138 |
| single + 4-MAC | `sim/results/power/step2_mode4_directed006/report.md` | 51 | 36 | 19 | 106 |
| dual + 1-MAC | `sim/results/power/step3_mode1_directed4x4x4/report.md`* | 27 | 68 | 19 | 114 |
| dual + 4-MAC | `sim/results/power/step3_mode4_directed4x4x4/report.md`* | 27 | 36 | 19 | 82 |

\* step1(dual-memory, accelerator-only)은 별도 cycle 계측 결과가 없어, 동일한
`rtl_v2` GEMM accelerator를 그대로 포함하는 step3(full-system) 실행의 GEMM
busy 구간 값을 대신 사용했다. compute/store 값이 single-memory 쪽과 정확히
같게 나오는 것으로(68/19) MAC datapath 자체는 동일하게 동작함을 확인했고,
load만 51→27로 줄어든 것은 dual-port가 A/B를 동시에 읽을 수 있어서다.

AT(mode0)의 cycle 수는 2026-06-07 시점 결과(`sim/results/directed_case/
20260607_222703_rtl_at_directed_case_m0/report.md`)에만 있다. 이 결과는
`rtl_AT` target 기준인데, `rtl_AT`는 datapath뿐 아니라 LSU/controller_fsm도
`rtl`/`rtl_v2`와 다르게 구현되어 있다(출력 원소마다 A/B를 메모리에서
재로드하는 구조). load=128 사이클처럼 큰 값은 측정 오류가 아니라 이 별도
LSU 구조의 결과이지만, AT 연산(adder tree) 자체의 효율과는 무관한 값이
섞여 있어 다른 target과 같은 조건으로 비교할 수 없다. 따라서 정량
비교에서 제외했다(6절 참고). 최종 target인 `rtl_v2`에도 동일한 AT
datapath(`gemm_mac_datapath_at.v`)가 구현되어 있으나, 이 조합은 Verilator
regression 대상에 포함되지 않아 cycle이 측정된 적은 없다.

## 3. 결과

### 3.1 Oasys PPA @15000ps

| 구조 | WNS | margin | area(sq um) | power(mW) |
|---|---:|---:|---:|---:|
| dual + AT (mode0) | 1503.6 ps | 10.0% | 406,367 | 63.79 |
| dual + 1-MAC | 3933.1 ps | 26.2% | 327,971 | 52.77 |
| dual + 4-MAC | 3761.6 ps | 25.1% | 426,972 | 67.47 |
| single + 1-MAC | 3880.6 ps | 25.9% | 315,406 | 50.15 |
| single + 4-MAC | 3780.8 ps | 25.2% | 414,415 | 64.45 |

### 3.2 속도 / 에너지 (AT 제외, cycle 데이터 확보된 4개 조합)

| 구조 | busy cycles | latency @66.7MHz | power | 에너지/연산(power×latency) |
|---|---:|---:|---:|---:|
| dual + 1-MAC | 114 | 1.71 µs | 52.77 mW | 90.2 nJ |
| **dual + 4-MAC** | 82 | **1.23 µs** | 67.47 mW | **83.0 nJ** |
| single + 1-MAC | 138 | 2.07 µs | 50.15 mW | 103.8 nJ |
| single + 4-MAC | 106 | 1.59 µs | 64.45 mW | 102.5 nJ |

## 4. 해석

- **속도(latency)**: dual + 4-MAC이 1.23 µs로 4개 조합 중 가장 빠르다.
  dual-port 메모리가 load 사이클을 51→27로 줄이고, 4-MAC이 compute를
  68→36으로 줄여 두 효과가 함께 누적된다.
- **순간 전력**: dual + 4-MAC이 67.47 mW로 가장 높다. 4-MAC의 N방향 병렬
  datapath가 면적/전력을 늘리기 때문이다.
- **에너지(전력×시간)**: 그런데도 dual + 4-MAC이 83.0 nJ로 가장 낮다. 순간
  전력은 더 쓰지만 그만큼 빨리 끝나서, 연산 1회당 총 소모 에너지는 오히려
  가장 적다. "속도와 전력 둘 다 만족하는 조합이 무엇인가"라는 질문에는
  에너지(전력×시간)가 가장 직접적인 답이 되고, 그 기준으로 dual + 4-MAC이
  1위다.
- single-memory는 두 MAC 모드 모두 dual보다 에너지효율이 낮다(102.5~
  103.8 nJ). single-port의 직렬 A/B 로드가 순수한 손해로 남는다.
- AT(mode0)은 area/power가 1-MAC과 4-MAC 사이에 위치하지만, timing margin이
  10.0%로 셋 중 가장 타이트하다. cycle 데이터는 LSU 구조가 다른 `rtl_AT`
  기준만 있어 다른 target과 같은 조건으로 비교할 수 없으므로 에너지
  순위에는 포함하지 않았다(2절 참고). K방향 병렬 구조라 K가 큰 shape에서
  유리할 것으로 예상되나, 이번 비교 워크로드(M=N=K=4)에서는 정량적 우위를
  확인하지 못했다.

## 5. 기존 Nitro 비교 리포트와의 결론 차이

`docs/reports/nitro_step1_step2_comparison_report.md`는 Nitro P&R 결과의
area, leaf cell 수, net 수, orphaned net, utilization을 기준으로 비교해
"step2(single-memory)를 최종 구현 architecture로 채택"이라고 결론 냈다. 그
문서의 분석 자체는 유효하다 — single-memory가 물리적 구현 지표
(area/cell/net/utilization)에서 일관되게 더 작고 정돈된 결과를 낸다.

본 문서는 다른 기준, 즉 `project2.md`가 명시한 **속도와 전력**을 직접
비교했고, 그 기준으로는 dual-memory + 4-MAC이 더 우수하다. 두 결론이
다른 이유는 비교 기준이 다르기 때문이며, 어느 한쪽이 틀린 것은 아니다.

- "물리적 구현이 더 작고 단순한 구조가 필요하다" → 기존 리포트의 결론
  (single-memory)을 따른다.
- "속도와 전력 소모로 평가한다"(project2 과제 요구사항 원문) → 본 문서의
  결론(dual-memory + 4-MAC)을 따른다.

참고로 실제 통합 시스템(`rtl_v2/gemm_system_top.v`)은 이미 dual-memory
구조이고 `MAC_MODE` 기본값도 4로 설정돼 있어, 현재 코드베이스의 기본
선택은 본 문서의 결론과 일치한다.

## 6. 한계 및 추가 확인 필요 사항

- AT(mode0)의 cycle 수는 `rtl_AT`(LSU/controller_fsm이 다른 target과 다른
  prototype) 기준만 있어 에너지 비교에서 제외했다. 최종 target인 `rtl_v2`,
  `MAC_MODE=0` 조합은 Verilator regression에 포함된 적이 없어 cycle이
  측정된 적이 없다. 필요하면 `rtl_v2 MAC_MODE=0`을 regression에 추가해
  새로 측정해야 한다.
- 전력 수치는 Oasys 기본 toggle-rate 가정 기준이다(VCD 기반 실측 power는
  이번 비교에 포함하지 않음).
- latency 비교에 사용한 66.7MHz는 4개 조합이 공통으로 pass하는 지점일 뿐,
  각 구조가 도달 가능한 최고 주파수는 아니다(특히 single + 1-MAC은
  117.6MHz까지 가능). "각자의 최고 주파수에서 비교"하면 순위가 달라질 수
  있다는 점은 이미 채팅에서 다룬 사례(step2 mode1 vs mode4, 8500ps/10000ps
  기준)로 확인했다.
