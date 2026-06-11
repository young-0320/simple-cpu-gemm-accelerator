# Oasys Results Policy

이 디렉토리는 Oasys 합성 결과를 보관한다. 

## 보관 기준

각 step/mode의 frequency sweep 결과는 다음 두 종류로 나눈다.

1. `mode*_sweep_summary.md`

   - 해당 mode에서 실행한 모든 clock period의 핵심 PPA 숫자를 기록한다.
   - 최소 항목은 `period`, `freq`, `WNS`, `margin`, `area`, `total_power`,
     `pass/fail`이다.
   - timing 한계, 권장 동작점, area/power 증가 해석도 이 파일에 정리한다.
2. 대표 raw result 폴더

   - 모든 sweep point의 raw report를 남기지 않는다.
   - mode 하나당 보통 2개 내지는 3개 정도만 남긴다.
   - 하나는 최종 권장 동작점, 다른 하나는 timing 경계점 또는 첫 fail 지점이다.

이 방식에서는 sweep 전체의 PPA 수치는 summary에 작성하고, raw report는 결론을 검증하기 위한 대표 증거로만 보관한다.

## Raw Report가 필요한 경우

`mode*_sweep_summary.md`는 보고서용 PPA 비교에는 충분하지만, raw report 전체를 완전히 대체하지는 않는다. 다음 정보는 대표 raw result 폴더에 남긴다.

- `timing.rpt`: critical path의 startpoint/endpoint와 셀 단위 timing path
- `area.rpt`: cell count와 instance별 area breakdown
- `power.rpt`: internal/switching/leakage power breakdown
- `synth.v`: 합성된 gate-level netlist

따라서 최종 권장점과 timing 경계점의 raw report만 보관해도, 결론 검증에는
충분하다.

## 권장 디렉토리 구조

```text
results/
└── step2/
    ├── mode1_sweep_summary.md
    ├── mode1_15000ps/
    │   ├── step2_mode1_timing.rpt
    │   ├── step2_mode1_area.rpt
    │   ├── step2_mode1_power.rpt
    │   └── step2_mode1_synth.v
    └── mode1_7000ps/
        ├── step2_mode1_timing.rpt
        ├── step2_mode1_area.rpt
        ├── step2_mode1_power.rpt
        └── step2_mode1_synth.v
```

폴더명은 `<mode>_<period>ps` 형식을 사용한다. 예를 들어 `mode4_15000ps`는
`MAC_MODE=4`, clock period 15000 ps 조건의 결과이다.

파일명은 현재 결과와의 추적성을 위해 `step*_mode*_*` 형식을 유지한다. 

## 대표 Point 선택 기준

mode별로 raw report 폴더를 줄일 때는 다음 순서로 남긴다.

1. 권장 동작점

   - P&R margin을 고려해 최종 후보로 선택한 period이다.
   - 보통 Oasys margin이 20-30% 수준인 가장 빠른 안정 동작점이다.
2. timing 경계점

   - 첫 fail 지점이 있으면 첫 fail 지점을 남긴다.
   - 첫 fail raw report가 없거나 재실행이 어렵다면, 가장 빠듯한 pass 지점을 남긴다.

예를 들어 summary에서 15000 ps를 권장하고 7000 ps가 첫 fail이면,
`mode*_15000ps/`와 `mode*_7000ps/`를 남긴다. 7000 ps raw report가 없으면
`mode*_8500ps/`처럼 margin이 작은 pass 지점을 대신 남긴다.

## 정리 원칙

- 모든 sweep 숫자는 삭제하지 말고 `mode*_sweep_summary.md`에 남긴다.
- 중간 sweep point의 raw report는 summary에 반영된 뒤 삭제해도 된다.
- 보고서에 직접 인용한 값은 summary와 raw report 중 하나에서 추적 가능해야 한다.
- 폴더명과 파일명은 mode가 서로 충돌하지 않게 맞춘다.
