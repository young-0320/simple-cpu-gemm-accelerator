# CPU to GEMM Control Interface

CPU와 GEMM accelerator는 MMIO register block으로 대화한다. CPU는 register write로 작업 조건을 넘기고, status read로 accelerator의 진행 상태를 확인한다.

> 이 문서는 logical register 계약을 정의한다. 실제 address offset은 RTL register map을 확정할 때 고정한다.

## Register View

| Register | CPU access | 의미 |
| --- | --- | --- |
| `GEMM_A_BASE` | Write | A matrix가 시작되는 memory word address |
| `GEMM_B_BASE` | Write | B matrix가 시작되는 memory word address |
| `GEMM_C_BASE` | Write | C matrix를 저장할 memory word address |
| `GEMM_M` | Write | C의 row 수, A의 row 수 |
| `GEMM_N` | Write | C의 column 수, B의 column 수 |
| `GEMM_K` | Write | A의 column 수, B의 row 수 |
| `GEMM_CTRL` | Write | transaction 시작과 sticky status clear |
| `GEMM_STATUS` | Read | busy, done, error 상태 확인 |

## Control Bits

| Field | Direction | 동작 |
| --- | --- | --- |
| `CTRL.start` | CPU to GEMM | 현재 설정된 base address와 dimension으로 transaction을 시작한다. |
| `CTRL.clear_done` | CPU to GEMM | `done`, `error`, error detail flag를 clear하고 IDLE로 복귀시킨다. |

`start`는 IDLE 상태에서만 의미가 있다. CPU는 `STATUS.busy=1`인 동안 새로운 `start`를 보내지 않는다.

## Status Bits

| Field | Direction | 의미 |
| --- | --- | --- |
| `STATUS.busy` | GEMM to CPU | accelerator가 LOAD, COMPUTE, STORE 중이다. |
| `STATUS.done` | GEMM to CPU | transaction이 종료되었다. 성공 여부는 `error`와 함께 판단한다. |
| `STATUS.error` | GEMM to CPU | transaction이 정상 완료되지 않았다. |
| `STATUS.invalid_size` | GEMM to CPU | `M`, `N`, `K`가 지원 범위를 벗어났다. |

`done`과 error-related flag는 sticky 상태이다. CPU가 `CTRL.clear_done`을 write하기 전까지 유지된다.

## Transaction Protocol

```text
CPU                         GEMM
 | write A/B/C base           |
 | write M/N/K                |
 | write CTRL.start --------> | validate dimensions
 |                            | LOAD -> COMPUTE -> STORE
 | poll STATUS.done <-------- | done=1, busy=0
 | read STATUS.error          |
 | write CTRL.clear_done ---> | clear sticky flags, return IDLE
```

지원하는 dimension은 baseline에서 `1 <= M,N,K <= 4`이다. 범위를 벗어나면 GEMM은 memory access를 시작하지 않고 `done=1`, `error=1`, `invalid_size=1`을 보고한다.

## Transactional Verification Contract

Verilator testbench도 위 protocol을 그대로 사용하는 transaction driver 형태로 작성한다. 검증 코드는 accelerator 내부 state를 직접 force하거나 local buffer를 직접 비교하지 않는다. 대신 transaction 입력을 만들고, MMIO register write/read와 external memory read/write만으로 결과를 확인한다.

각 test transaction은 아래 정보를 가진다.

| 항목 | 의미 |
| --- | --- |
| Input setup | `A_BASE`, `B_BASE`, `C_BASE`, `M`, `N`, `K`, A/B matrix contents |
| Stimulus | `CTRL.start` write와 `STATUS.done` polling |
| Expected status | 정상 transaction은 `error=0`, invalid transaction은 `error=1`, `invalid_size=1` |
| Expected memory | 정상 transaction에서 `C_BASE` 이후 `M*N` word가 golden model 결과와 일치해야 한다. |

Random test는 이 transaction 구조 안에서 `M`, `N`, `K`, A/B 값, base address를 constrained-random으로 생성한다. A/B packing과 zero padding은 `data_memory.md`의 layout contract를 따른다.
