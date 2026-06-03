# Data Memory Spec

이 문서는 GEMM accelerator와 Simple CPU가 공유하는 external data memory의 주소 단위와 matrix 저장 규칙을 정의하는 layout contract이다. 

A/B/C matrix가 memory word에 놓이는 방식, packed lane mapping, padding, base address 계산의 기준은 이 문서에서 확정한다.

Accelerator 내부 FSM, local buffer, MAC datapath 동작은 `gemm_accelerator.md`에서 정의한다. 그 문서는 이 layout contract를 사용하며, memory layout 규칙을 다시 정의하지 않는다.

## Memory Contract

| 항목       | 값             | 의미                                      |
| ---------- | -------------- | ----------------------------------------- |
| `DATA_W` | 32 bit         | memory 한 word의 폭                       |
| `ADDR_W` | 12 bit         | 4K word address 공간                      |
| Addressing | word-addressed | 주소 1 증가가 32-bit word 1개 이동을 의미 |

주소는 byte address가 아니라 word address이다. 따라서 `mem[0x100]`, `mem[0x101]`, `mem[0x102]`는 서로 연속된 32-bit word를 가리킨다.

```text
mem[0x100] = word 0
mem[0x101] = word 1
mem[0x102] = word 2
```

## Unified CPU Address Map

Simple CPU는 12-bit word address를 사용하므로 CPU가 접근할 수 있는 전체 주소 공간은 `0x000`부터 `0xFFF`까지이다. 이 프로젝트에서는 instruction, matrix data, GEMM MMIO register를 같은 CPU address space 안에서 구분한다.

| Word address range | Region | 용도 |
| --- | --- | --- |
| `0x000` - `0x07F` | Instruction region | CPU instruction 저장 |
| `0x080` - `0xFEF` | Data region | A/B input matrix와 C output matrix 저장 |
| `0xFF0` - `0xFFF` | MMIO / reserved region | GEMM register 접근과 향후 확장 |

A/B/C matrix storage는 data region 안에 배치한다. `A_BASE`, `B_BASE`, `C_BASE`는 GEMM MMIO register에 저장되는 word address 값이며, 각 값은 matrix data가 시작되는 data-region address를 가리킨다.

## Matrix Storage

| Matrix | Element type | Memory format | Word당 element 수 |
| ------ | ------------ | ------------- | ----------------- |
| A      | signed int8  | packed        | 4                 |
| B      | signed int8  | packed        | 4                 |
| C      | signed int32 | unpacked      | 1                 |

A/B는 입력 matrix이므로 32-bit word 하나에 signed int8 element 4개를 묶어서 저장한다. C는 누산 결과이므로 element 하나가 32-bit word 하나를 그대로 차지한다.

## Packed A/B Word Layout

A/B packed word의 lane은 아래 bit range에 대응한다. 각 lane은 signed int8 two's-complement 값으로 해석한다.

| Lane   | Bit range       |
| ------ | --------------- |
| lane 0 | `word[7:0]`   |
| lane 1 | `word[15:8]`  |
| lane 2 | `word[23:16]` |
| lane 3 | `word[31:24]` |

packed A/B matrix가 사용하는 word 수는 valid element 개수 기준으로 계산한다.

```text
A_element_count = M * K
B_element_count = K * N

A_words = ceil(A_element_count / 4) = (A_element_count + 3) / 4
B_words = ceil(B_element_count / 4) = (B_element_count + 3) / 4
```

마지막 packed word에서 valid element가 없는 lane은 zero padding으로 채운다. Padding lane에는 다음 matrix의 element나 다른 데이터를 이어 담지 않는다.

Valid element와 padding lane은 값으로 구분하지 않는다. 행렬 안의 실제 element 값이 `0`일 수 있으므로, 유효 여부는 항상 element index와 matrix size로 판단한다.

```text
valid A index: 0 <= index < M * K
valid B index: 0 <= index < K * N
padding lane:  index >= element_count
```

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

`K=1`, `N=3`인 B matrix는 element가 3개이므로 32-bit word 1개를 사용하고, 남는 lane 3은 zero padding이다.

```text
B[0][0] -> mem[B_BASE + 0] lane 0
B[0][1] -> mem[B_BASE + 0] lane 1
B[0][2] -> mem[B_BASE + 0] lane 2
padding -> mem[B_BASE + 0] lane 3 = 0
```
