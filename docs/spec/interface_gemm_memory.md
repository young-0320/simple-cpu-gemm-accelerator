# GEMM to Memory Data Interface

GEMM accelerator는 external data memory에서 A/B matrix를 읽고, 계산이 끝난 C matrix를 다시 external data memory에 쓴다. 이 인터페이스의 핵심은 32-bit word memory 위에서 int8 input과 int32 output을 일관되게 다루는 것이다.

## Memory Assumption

| 항목 | 값 |
| --- | --- |
| Data width | 32 bit |
| Address type | word address |
| A/B element | signed int8, packed |
| C element | signed int32, unpacked |

CPU가 GEMM을 시작하면 memory data path의 주인은 GEMM accelerator이다. CPU는 busy 동안 normal memory access를 하지 않고 MMIO status polling만 수행한다.

## Read Path: A/B Load

A와 B는 32-bit word 하나에 int8 element 4개가 들어간 packed format이다. Load-Store Unit은 memory에서 word를 읽고, lane별 signed int8로 unpack한 뒤 local buffer에 저장한다.

```text
external memory word
        |
        v
packed int8 lanes [3:0]
        |
        v
sign-extended int8 element
        |
        v
a_buf / b_buf
```

row-major element index는 다음과 같다.

```text
A_index = i * K + k
B_index = k * N + j
```

packed word address와 lane은 element index에서 계산한다.

```text
word_addr = BASE + index / 4
lane      = index % 4
```

## Write Path: C Store

C는 int32 accumulation 결과이므로 packing하지 않는다. C element 하나가 memory word 하나를 차지한다.

```text
c_buf
  |
  v
external memory word write
```

C의 writeback address는 row-major 기준으로 계산한다.

```text
C_index     = i * N + j
C_word_addr = C_BASE + C_index
```

## LSU Responsibilities

| 단계 | 책임 |
| --- | --- |
| LOAD A | `A_BASE`부터 필요한 packed word를 읽고 `a_buf`를 채운다. |
| LOAD B | `B_BASE`부터 필요한 packed word를 읽고 `b_buf`를 채운다. |
| STORE C | `c_buf`의 int32 결과를 `C_BASE`부터 row-major 순서로 쓴다. |

Baseline에서는 memory error response를 별도로 정의하지 않는다. Error flag는 dimension validation 같은 accelerator 내부 조건을 보고하는 데 사용한다.
