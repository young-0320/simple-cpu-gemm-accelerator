# GEMM 검증 방식 수정 및 성능 비교 기준 정리

작성일: 2026-06-07

## 1. 작업 배경

tb에서 관찰 가능한 cycle 수를 근거로 비교할 수 있게 만드는 것이다.

현재 프로젝트의 기본 연산은 `C = A x B`이며, 기존 baseline은 single memory port 기반의 1-MAC 구조를 기준으로 한다. 이 구조는 기능 검증에는 적합하지만, 연산량이 증가할수록 MAC 연산이 직렬로 수행되기 때문에 compute cycle이 병목이 된다.

## 2. 최적화 흐름 정리

### 2.1 1-MAC baseline

1-MAC 구조는 가장 단순한 baseline이다. 모든 곱셈-누산을 하나의 MAC datapath에서 순차적으로 처리하므로 구현은 단순하지만, `M`, `N`, `K`가 커질수록 연산 cycle이 증가한다.

이 구조는 이후 최적화의 기준점으로 사용한다.

### 2.2 4-MAC 확장

1-MAC에서 확인되는 compute 병목을 줄이기 위해 4-MAC 구조로 확장했다.

4-MAC 구조는 여러 MAC 연산을 병렬로 처리할 수 있으므로, 동일한 transaction에서 compute phase의 cycle 수를 줄일 수 있다. 기존 single-port testbench에서도 1-MAC 대비 cycle 수 감소를 확인할 수 있기 때문에, compute datapath 확장의 효과를 설명하는 비교 기준으로 사용할 수 있다.

### 2.3 memory access 병목 확인

MAC 병렬도를 높이면 compute phase는 줄어들지만, A/B matrix를 외부 memory에서 읽어오는 load phase는 여전히 single-port 접근 방식에 묶인다.

즉, MAC datapath만 확장하면 전체 성능이 계속 선형적으로 좋아지는 것이 아니라, 다음 병목이 memory access로 이동한다. 이 병목은 testbench에서 phase별 cycle breakdown을 기록해야 명확히 확인할 수 있다.

### 2.4 dual memory access + AT 연산 구조

`rtl_AT`는 dual-port 형태의 병렬 memory access와 AT 연산 구조를 가진다.

이 구조는 A/B 데이터를 더 병렬적으로 읽을 수 있으므로 load phase cycle을 줄일 수 있다. 따라서 단순히 전체 cycle만 비교하는 것보다, `load`, `compute`, `store` phase를 나누어 비교해야 dual memory access의 이점이 명확히 드러난다.

## 3. testbench 수정 내용

기존 single-port testbench만으로는 dual-port memory 구조의 장점을 제대로 검증하기 어렵다. single-port testbench에 `rtl_AT`를 연결하면 외부 interface가 single-port로 제한되기 때문에, 실제 dual-port memory access의 cycle 이점이 반영되지 않는다.

이번 작업에서는 기존 검증 구조를 다음과 같이 정리했다.

- legacy testbench인 `tb_gemm_vectors.sv` 제거
- 기존 structured testbench를 single-port 기준의 `tb_gemm_vectors_single.sv`로 정리
- dual-port 검증을 위한 `tb_gemm_vectors_dual.sv` 추가
- Python verification script에서 `--tb single` / `--tb dual` 선택 지원
- single/dual testbench 모두에서 phase별 cycle breakdown을 수집하도록 정리

이를 통해 single memory access 기반의 MAC 구조와 dual memory access 기반의 AT 구조를 같은 vector set 기준으로 비교할 수 있게 됐다.

## 4. 현재 검증 결과

현재 검증 기준에서는 다음 결과를 확인했다.

- single-port baseline RTL: directed case `56/56 PASS`
- `rtl_AT` single-port compatibility mode: directed case `56/56 PASS`
- `rtl_AT` dual-port testbench: mixed case `126/126 PASS`

single-port testbench와 dual-port testbench를 `rtl_AT` mixed case 기준으로 비교했을 때, dual-port 접근 방식은 load phase에서 cycle 감소를 보였다.

| 비교 항목                | single-port AT | dual-port AT |   감소 |
| ------------------------ | -------------: | -----------: | -----: |
| 전체 total cycle         |           4960 |         4076 |    884 |
| 전체 average cycle       |          39.37 |        32.35 | 17.82% |
| 전체 max cycle           |            196 |          164 |     32 |
| valid-only average cycle |          61.13 |        49.79 | 18.54% |
| valid load average cycle |          45.79 |        34.46 | 24.75% |

compute/store phase는 동일하고, cycle 감소는 load phase에서 발생했다. 따라서 dual-port memory access의 이점은 "연산 자체가 빨라졌다"기보다는 "A/B load 병목이 줄었다"로 해석하는 것이 맞다.

## 5. 현재 작업의 결론

오늘 작업으로 기능 검증과 cycle 비교를 위한 testbench 기반은 정리됐다.

현재 단계에서의 역할 범위는 다음과 같이 마무리할 수 있다.

- 1-MAC baseline의 compute 병목 설명 가능
- 4-MAC 확장을 통한 compute 병목 완화 설명 가능
- single-port memory access가 다음 병목이라는 근거 확보
- dual-port memory access의 load cycle 감소 확인
- single/dual testbench를 분리해 비교 가능한 검증 구조 확보

즉, 오늘 작업은 RTL 통합 자체보다는 "통합 RTL을 만들기 전에 어떤 구조를 비교해야 하는지"와 "그 비교를 어떻게 검증할지"를 정리한 작업이다.

## 6. 다음 작업

다음 단계는 새로운 통합 RTL 모델을 만드는 것이다.

권장 방향은 기존 `rtl`과 `rtl_AT`를 바로 섞기보다, 별도 통합 RTL 디렉터리에서 다음 구조를 명확히 구현하는 것이다.

- 기존 `rtl`의 외부 interface contract 유지
- dual-port memory access 구조 적용
- mode 기반 연산 선택 지원
- `mode = 1`: 1-MAC
- `mode = 4`: 4-MAC
- `mode = 0`: AT 연산

이렇게 하면 발표에서 다음 최적화 흐름을 자연스럽게 설명할 수 있다.

1. 1-MAC baseline에서 compute 병목 확인
2. 4-MAC 확장으로 compute 병목 완화
3. MAC 병렬화 이후 memory access 병목 확인
4. dual-port memory access로 load 병목 완화
5. 최종적으로 MAC/AT mode를 선택할 수 있는 통합 GEMM accelerator 제안

**속도/cycle 최적화 관점에서는 dual + AT 방향이 타당하다. 하지만 PPA 전체 최적해라고 단정하려면 dual+MAC, dual+AT, single+MAC을 같은 조건으로 합성/검증해서 비교해야 한다.**
