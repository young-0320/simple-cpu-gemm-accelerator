# Simple CPU Spec

Simple CPU는 GEMM을 직접 계산하지 않는다. 이 프로젝트에서 CPU의 역할은 matrix 연산을 accelerator에게 맡기고, MMIO register를 통해 transaction을 시작하고 종료 상태를 확인하는 것이다.

## Responsibility

| CPU가 맡는 일 | 설명 |
| --- | --- |
| Operand 위치 지정 | A/B/C matrix의 base address를 GEMM register에 쓴다. |
| Problem size 지정 | `M`, `N`, `K`를 GEMM register에 쓴다. |
| Transaction 시작 | `GEMM_CTRL.start`를 write해서 accelerator를 깨운다. |
| Completion 확인 | `GEMM_STATUS.done`을 polling한다. |
| Result 확인 | 필요하면 C matrix가 저장된 memory를 읽는다. |

CPU는 MAC 연산, A/B unpack, C writeback을 수행하지 않는다. 해당 동작은 모두 GEMM accelerator 내부 책임이다.

## Control Flow

```text
1. GEMM_A_BASE write
2. GEMM_B_BASE write
3. GEMM_C_BASE write
4. GEMM_M / GEMM_N / GEMM_K write
5. GEMM_CTRL.start write
6. GEMM_STATUS.done polling
7. GEMM_STATUS.error 확인
8. 정상 완료이면 C 결과 확인
9. GEMM_CTRL.clear_done write
```

`done`은 성공을 뜻하지 않고 transaction이 끝났음을 뜻한다. CPU는 항상 `done=1`을 본 뒤 `error`를 함께 확인해야 한다.

## Busy-Time Rule

GEMM accelerator가 busy인 동안 CPU는 normal data memory에 접근하지 않는다. 이 기간에 CPU가 하는 memory 관련 동작은 `GEMM_STATUS` MMIO polling뿐이다.

이 제약은 baseline 구조에서 memory arbitration을 단순하게 만들기 위한 규칙이다. 즉, GEMM이 A/B load와 C store를 수행하는 동안 external memory port의 주인은 accelerator이다.
