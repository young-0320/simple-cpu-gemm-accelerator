# Data Memory Spec

이 문서는 GEMM accelerator와 Simple CPU가 공유하는 external data memory의 주소 단위와 matrix 저장 규칙을 정의한다.

## Memory Contract

| 항목 | 값 | 의미 |
| --- | --- | --- |
| `DATA_W` | 32 bit | memory 한 word의 폭 |
| `ADDR_W` | 12 bit | 4K word address 공간 |
| Addressing | word-addressed | 주소 1 증가가 32-bit word 1개 이동을 의미 |

주소는 byte address가 아니라 word address이다. 따라서 `mem[0x100]`, `mem[0x101]`, `mem[0x102]`는 서로 연속된 32-bit word를 가리킨다.

```text
mem[0x100] = word 0
mem[0x101] = word 1
mem[0x102] = word 2
```

## Matrix Storage

| Matrix | Element type | Memory format | Word당 element 수 |
| --- | --- | --- | --- |
| A | signed int8 | packed | 4 |
| B | signed int8 | packed | 4 |
| C | signed int32 | unpacked | 1 |

A/B는 입력 matrix이므로 32-bit word 하나에 signed int8 element 4개를 묶어서 저장한다. C는 누산 결과이므로 element 하나가 32-bit word 하나를 그대로 차지한다.

## Row-Major Layout

A, B, C는 모두 row-major order로 저장한다. 2차원 index `(row, col)`은 아래처럼 1차원 element index로 변환된다.

```text
index = row * num_cols + col
```

packed A/B의 word address와 lane은 element index에서 계산한다.

```text
word_offset = index / 4
lane        = index % 4
word_addr   = BASE + word_offset
```

C는 packed format이 아니므로 element index가 곧 word offset이다.

```text
C_word_addr = C_BASE + (row * N + col)
```

## Example

`M=2`, `K=4`인 A matrix는 element가 8개이므로 32-bit word 2개를 사용한다.

```text
A[0][0..3] -> mem[A_BASE + 0] lanes 0..3
A[1][0..3] -> mem[A_BASE + 1] lanes 0..3
```

`M=2`, `N=2`인 C matrix는 element가 4개이므로 32-bit word 4개를 사용한다.

```text
C[0][0] -> mem[C_BASE + 0]
C[0][1] -> mem[C_BASE + 1]
C[1][0] -> mem[C_BASE + 2]
C[1][1] -> mem[C_BASE + 3]
```
