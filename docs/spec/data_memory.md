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

| Word address range    | Region                 | 용도                                    |
| --------------------- | ---------------------- | --------------------------------------- |
| `0x000` - `0x07F` | Instruction region     | CPU instruction 저장                    |
| `0x080` - `0xFEF` | Data region            | A/B input matrix와 C output matrix 저장 |
| `0xFF0` - `0xFFF` | MMIO / reserved region | GEMM register 접근과 향후 확장          |

A/B/C matrix storage는 data region 안에 배치한다. `A_BASE`, `B_BASE`, `C_BASE`는 GEMM MMIO register에 저장되는 word address 값이며, 각 값은 matrix data가 시작되는 data-region address를 가리킨다.

## Matrix Storage

| Matrix | Element type | Memory format | Word당 element 수 |
| ------ | ------------ | ------------- | ----------------- |
| A      | signed int8  | packed        | 4                 |
| B      | signed int8  | packed        | 4                 |
| C      | signed int32 | unpacked      | 1                 |

A/B는 입력 matrix이므로 row 단위로 32-bit word 하나에 signed int8 element를 최대 4개까지 묶어서 저장한다. C는 누산 결과이므로 element 하나가 32-bit word 하나를 그대로 차지한다.

## Packed A/B Word Layout

A/B packed word의 lane은 아래 bit range에 대응한다. 각 lane은 signed int8 two's-complement 값으로 해석한다.

| Lane   | Bit range       |
| ------ | --------------- |
| lane 0 | `word[7:0]`   |
| lane 1 | `word[15:8]`  |
| lane 2 | `word[23:16]` |
| lane 3 | `word[31:24]` |

packed A/B matrix는 row 단위로 word에 배치한다. 한 row 안에서는 column 순서대로 lane 0부터 채우고, row가 끝나면 남은 lane을 zero padding으로 채운 뒤 다음 row는 다음 word에서 시작한다. 다른 row의 element를 같은 packed word에 이어 담지 않는다.

packed A/B matrix가 사용하는 word 수는 row별 packed word 수 기준으로 계산한다.

```text
A_row_words = ceil(K / 4) = (K + 3) / 4
B_row_words = ceil(N / 4) = (N + 3) / 4

A_words = M * A_row_words
B_words = K * B_row_words
```

Baseline dimension은 `1..4`이므로 A row 하나와 B row 하나는 각각 packed word 하나에 들어간다. 그래도 주소 계산은 위 row-word 공식을 따른다.

각 row의 마지막 packed word에서 valid element가 없는 lane은 zero padding으로 채운다. Padding lane에는 다음 row의 element나 다른 데이터를 이어 담지 않는다.

Valid element와 padding lane은 값으로 구분하지 않는다. 행렬 안의 실제 element 값이 `0`일 수 있으므로, 유효 여부는 항상 row, column, matrix size로 판단한다.

```text
valid A: 0 <= row < M, 0 <= col < K
valid B: 0 <= row < K, 0 <= col < N
padding lane: col >= row_col_count
```

## Row-Major Layout

A, B, C는 모두 row-major order로 저장한다. A/B는 row-based packed format이므로 packed word address와 lane을 row와 column에서 직접 계산한다.

```text
row_words = ceil(num_cols / 4) = (num_cols + 3) / 4
word_addr = BASE + row * row_words + col / 4
lane      = col % 4
```

C는 packed format이 아니므로 row-major element index가 곧 word offset이다.

```text
C_word_addr = C_BASE + (row * N + col)
```

## Example

`M=2`, `K=3`인 A matrix는 row가 2개이고 row당 32-bit word 1개를 사용한다.

```text
A[0][0] -> mem[A_BASE + 0] lane 0
A[0][1] -> mem[A_BASE + 0] lane 1
A[0][2] -> mem[A_BASE + 0] lane 2
padding -> mem[A_BASE + 0] lane 3 = 0
A[1][0] -> mem[A_BASE + 1] lane 0
A[1][1] -> mem[A_BASE + 1] lane 1
A[1][2] -> mem[A_BASE + 1] lane 2
padding -> mem[A_BASE + 1] lane 3 = 0
```

`M=2`, `N=2`인 C matrix는 element가 4개이므로 32-bit word 4개를 사용한다.

```text
C[0][0] -> mem[C_BASE + 0]
C[0][1] -> mem[C_BASE + 1]
C[1][0] -> mem[C_BASE + 2]
C[1][1] -> mem[C_BASE + 3]
```

`K=2`, `N=3`인 B matrix는 row가 2개이고 row당 32-bit word 1개를 사용한다.

```text
B[0][0] -> mem[B_BASE + 0] lane 0
B[0][1] -> mem[B_BASE + 0] lane 1
B[0][2] -> mem[B_BASE + 0] lane 2
padding -> mem[B_BASE + 0] lane 3 = 0
B[1][0] -> mem[B_BASE + 1] lane 0
B[1][1] -> mem[B_BASE + 1] lane 1
B[1][2] -> mem[B_BASE + 1] lane 2
padding -> mem[B_BASE + 1] lane 3 = 0
```
