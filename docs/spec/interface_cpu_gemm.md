# CPU to GEMM Control Interface

CPU와 GEMM accelerator는 MMIO register block으로 대화한다. CPU는 register write로 작업 조건을 넘기고, status read로 accelerator의 진행 상태를 확인한다.

> 이 문서는 CPU가 GEMM accelerator를 제어하기 위한 32-bit MMIO register map과 logical control/status 계약을 정의한다.

## Address Map

Simple CPU는 12-bit word address와 32-bit load/store data path를 사용한다. 현재 RTL은 `0xFF0`부터 `0xFF7`까지를 active GEMM MMIO register block으로 decode한다.

```text
GEMM_MMIO_BASE = 12'hFF0
```

| Word address | Register | CPU access |
| --- | --- | --- |
| `0xFF0` | `GEMM_A_BASE` | Write |
| `0xFF1` | `GEMM_B_BASE` | Write |
| `0xFF2` | `GEMM_C_BASE` | Write |
| `0xFF3` | `GEMM_M` | Write |
| `0xFF4` | `GEMM_N` | Write |
| `0xFF5` | `GEMM_K` | Write |
| `0xFF6` | `GEMM_CTRL` | Write |
| `0xFF7` | `GEMM_STATUS` | Read |

`0xFF8`부터 `0xFFF`까지는 향후 MMIO 확장을 위한 reserved address range이다. 현재 RTL은 이 범위를 MMIO로 decode하지 않으므로 software와 tests는 이 주소들을 접근하지 않는다.

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

`GEMM_CTRL` write는 stored state가 아니라 pulse command로 해석한다. CPU가 해당 bit에 `1`을 write하면 MMIO register block은 GEMM 쪽으로 one-cycle pulse를 만든다.

| Bit | Field | Direction | 동작 |
| --- | --- | --- | --- |
| `[0]` | `CTRL.start` | CPU to GEMM | 현재 설정된 base address와 dimension으로 transaction을 시작한다. |
| `[1]` | `CTRL.clear_done` | CPU to GEMM | sticky `done`, `error`, error detail flag를 clear하고 IDLE로 복귀시킨다. |
| `[31:2]` | Reserved | CPU to GEMM | Write ignored |

`start`는 IDLE 상태에서만 의미가 있다. Integrated RTL에서는 `STATUS.busy=1`인 동안 CPU가 freeze되므로 software가 새로운 `start`를 발행하지 않는다. Direct testbench도 busy 중 start를 생성하지 않는다.

## Status Bits

`GEMM_STATUS` read는 아래 bit field를 가진 32-bit status word를 반환한다.

| Bit | Field | Direction | 의미 |
| --- | --- | --- | --- |
| `[0]` | `STATUS.busy` | GEMM to CPU | accelerator가 LOAD, COMPUTE, STORE 중이다. |
| `[1]` | `STATUS.done` | GEMM to CPU | transaction이 종료되었다. 성공 여부는 `error`와 함께 판단한다. |
| `[2]` | `STATUS.error` | GEMM to CPU | transaction을 정상 수행할 수 없었다. |
| `[3]` | `STATUS.invalid_size` | GEMM to CPU | `M`, `N`, `K`가 지원 범위 `1..4`를 벗어났다. |
| `[31:4]` | Reserved | GEMM to CPU | Read 0 |

`done`과 error-related flag는 sticky 상태이다. CPU가 `CTRL.clear_done`을 write하기 전까지 유지된다.

## Transaction Protocol

```text
CPU                         GEMM
 | write A/B/C base           |
 | write M/N/K                |
 | write CTRL.start --------> | validate dimensions
 | freeze while busy          | LOAD -> COMPUTE -> STORE
 | resume when busy=0         | done=1, busy=0
 | read STATUS.done/error <---|
 | write CTRL.clear_done ---> | clear sticky flags, return IDLE
```

지원하는 dimension은 baseline에서 `1 <= M,N,K <= 4`이다. 범위를 벗어나면 GEMM은 memory access를 시작하지 않고 `done=1`, `error=1`, `invalid_size=1`을 보고한다.

## Transactional Verification Contract

Verilator testbench도 위 protocol을 그대로 사용하는 transaction driver 형태로 작성한다. 검증 코드는 accelerator 내부 state를 직접 force하거나 local buffer를 직접 비교하지 않는다. 대신 transaction 입력을 만들고, MMIO register write/read와 external memory read/write만으로 결과를 확인한다.

각 test transaction은 아래 정보를 가진다.

| 항목 | 의미 |
| --- | --- |
| Input setup | `A_BASE`, `B_BASE`, `C_BASE`, `M`, `N`, `K`, A/B matrix contents |
| Stimulus | `CTRL.start` write, busy 동안 CPU freeze, 완료 후 `GEMM_STATUS` read |
| Expected status | 정상 transaction은 `error=0`, invalid transaction은 `error=1`, `invalid_size=1` |
| Expected memory | 정상 transaction에서 `C_BASE` 이후 `M*N` word가 golden model 결과와 일치해야 한다. |

Random test는 이 transaction 구조 안에서 `M`, `N`, `K`, A/B 값, base address를 constrained-random으로 생성한다. A/B packing과 zero padding은 `data_memory.md`의 layout contract를 따른다.
