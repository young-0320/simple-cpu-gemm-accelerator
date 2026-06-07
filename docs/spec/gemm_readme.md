# GEMM Accelerator — CPU 통합 + 다중 연산 모드

simple-cpu-smart-doorlock의 CPU에 GEMM(행렬곱) 코프로세서를 통합한 설계.
하나의 공통 구조 위에서 **세 가지 연산 방식(1-MAC / 4-MAC / Adder-Tree)을
파라미터로 선택**할 수 있어, 같은 검증 환경에서 PPA를 비교할 수 있다.

```
C = A x B     (1 <= M, N, K <= 4,  int8 입력 / int32 출력)
```

CPU는 한 줄도 수정하지 않는다.

---

## 1. 설계 개요

```
gemm_system_top
├── top_cpu              CPU (원본 그대로, 미수정)
├── gemm_cpu_glue        CPU<->GEMM 라우팅 + busy 중재
├── gemm_accelerator_top GEMM 코프로세서 (MAC_MODE 파라미터)
│   ├── gemm_mmio_reg        MMIO 레지스터 + 차원 검증
│   ├── gemm_controller_fsm  IDLE/LOAD/COMPUTE/STORE/DONE
│   ├── gemm_local_buffer    a/b_buf(int8), c_buf(int32)
│   ├── gemm_lsu             Load/Store Unit (듀얼포트)
│   └── [MAC_MODE별 datapath] 1-MAC / 4-MAC / AT
└── BRAM (듀얼포트, 보드에서는 BMG IP로 교체)
```

### 핵심 설계 결정
1. **CPU 미수정 통합** — glue가 CPU의 단일 메모리 포트를 가로채 MMIO와 BRAM으로
   라우팅. CPU는 자신이 BRAM을 읽는지 GEMM status를 읽는지 모른다.
2. **Stall-free 중재** — GEMM busy 동안 CPU를 freeze(clk_enable=0)하고 LSU가
   메모리를 독점. busy가 풀리면 CPU 재개. stall 로직이 전혀 없다.
3. **듀얼포트 메모리** — Port A(A읽기+C쓰기) / Port B(B읽기)로 A·B 병렬 로드.
4. **연산 mode 파라미터화** — MAC_MODE로 datapath만 교체, 나머지 구조는 공유.

---

## 2. 인터페이스

### MMIO (word address 0xFF0 ~ 0xFF7)
| 주소 | 레지스터 | 설명 |
|------|----------|------|
| 0xFF0 | A_BASE | A 행렬 시작 주소 |
| 0xFF1 | B_BASE | B 행렬 시작 주소 |
| 0xFF2 | C_BASE | C 결과 시작 주소 |
| 0xFF3~5 | M, N, K | 행렬 차원 |
| 0xFF6 | CTRL | bit0=start, bit1=clear_done |
| 0xFF7 | STATUS | bit0=busy, 1=done, 2=error, 3=invalid_size |

호출 절차: CPU가 STORE로 base/dim 설정 → CTRL.start → STATUS.done polling → 완료.

### 메모리 레이아웃 (row-aligned)
```
A row i -> mem[A_BASE + i] = pack(A[i][0..K-1])    (행마다 word 하나)
B row k -> mem[B_BASE + k] = pack(B[k][0..N-1])
C[i][j] -> mem[C_BASE + i*N + j]   (int32, unpacked)
pack lane: [7:0]=0, [15:8]=1, [23:16]=2, [31:24]=3,  남는 lane은 padding
```

### 차원 검증
M/N/K는 32비트 전체로 [1,4] 범위를 검사(저장은 3비트). 9, 17, 65536 등
어떤 큰 값도 invalid_size로 처리된다. (3비트 truncation aliasing 버그 수정 완료)

---

## 3. 연산 모드 (MAC_MODE)

| MAC_MODE | 이름 | 병렬화 축 | 구조 | 유리한 경우 |
|----------|------|-----------|------|-------------|
| 0 | Adder-Tree | K방향 | 곱셈 4개 + adder tree (내적 4항 동시) | K가 클 때 |
| 1 | 1-MAC serial | 없음 | 곱셈기 1개, 순차 누산 | baseline |
| 4 | 4-MAC | N방향 | 독립 누산기 4개 (한 행의 4 column 동시) | N이 클 때 |

세 모드는 **동일한 buffer/LSU/FSM/glue를 공유**하고 datapath만 다르다.
AT는 row-aligned 메모리에서 K방향 4개를 buffer 인덱스로 추출해 사용한다.

---

## 4. 성능 (사이클 측정)

### LOAD 단계 — 듀얼포트 효과 (모드 공통)
A·B 병렬 로드로 단일포트 대비 약 45% 감소.
| size | 단일포트 | 듀얼포트 |
|------|----------|----------|
| 4x4x4 | 51 | 27 |
| 3x3x3 | 33 | 18 |
| 2x2x2 | 19 | 11 |

### COMPUTE 단계 — 모드별 비교
| size | 1-MAC | 4-MAC | AT |
|------|-------|-------|-----|
| 4x4x4 | 68 | **36** | 52 |
| 3x3x3 | 31 | **22** | 31 |
| 1x4x4 | 20 | **12** | 16 |
| 4x4x1 | 20 | 20 | 52 |
| 4x1x4 (N=1) | 20 | 24 | **16** |
| 2x2x2 | 12 | 12 | 16 |

해석:
- **4-MAC**은 N방향 병렬이라 N이 클 때 최고 (4x4x4에서 1-MAC 대비 47% 단축).
  단 N=1이면 병렬화 이득이 없고 writeback 오버헤드만 남아 손해.
- **AT**는 K방향 병렬이라 N=1 같은 4-MAC 약점 구간(4x1x4)에서 더 빠르다.
  즉 4-MAC과 AT는 상호보완적: 가로로 긴 행렬(N↑)은 4-MAC, 세로로 긴(K↑)은 AT.
- LOAD/STORE 사이클은 세 모드 동일 (공통 LSU 재사용).

---

## 5. 검증

Verilator 회귀 16개 스위트 전부 통과. 모두 golden model(삼중 루프)과 대조.

| 스위트 | 내용 |
|--------|------|
| mmio / fsm / buf / lsu | 블록 단위 |
| macbuf / mac4buf | 1-MAC / 4-MAC datapath, 각 랜덤 320 |
| dimedge | 범위 밖 차원(9,17,65536,0 등) 전부 invalid |
|  top1 / top4 / top0 | GEMM end-to-end (1/4/AT), 각 랜덤 192 |
|  edge1 / edge4 / edge0 | 경계값(최소·비대칭·극단 int8·K경계), 세 모드 각각 |
|  sys1 / sys4 / sys0 | CPU가 어셈블리로 GEMM 호출 (1/4/AT), 각 30 |

```bash
cd sim
./run_all_tests.sh          # 각 스위트 끝 "ALL PASS" 확인
```

### 모드별 개별 빌드
```bash
# GEMM 단독 end-to-end (MAC_MODE = 0(AT) / 1 / 4)
verilator [flags] -GMAC_MODE=0 --cc ../rtl/tb_gemm_top_wrap.v -I../rtl \
    --exe ../tb/tb_gemm_top_wrap.cpp --Mdir obj --top-module tb_gemm_top_wrap
```

### 파형 (x2go + GTKWave)
```bash
cd sim && ./make_wave.sh 0       # MAC_MODE 지정 (0=AT, 1, 4)
gtkwave wave_system.vcd          # x2go 데스크톱에서
```

---

## 6. 폴더 구조 (CONTRIBUTING 준수)

```
rtl/gemm_accelerator/   GEMM RTL (mmio, fsm, buffer, lsu, datapath x3, top, define)
rtl/                    gemm_cpu_glue, gemm_system_top
rtl/simple_cpu/         CPU 코어 (원본)
sim/tb/                 testbench (Verilog wrapper + C++)
sim/                    run_all_tests.sh, make_wave.sh
sw/programs/            gemm_call.asm, assembler.py
docs/                   문서
```

---

## 7. 다음 단계

1. **합성 (Oasys/Nitro)** — MAC_MODE=0/1/4 각각 합성해 면적·전력 측정.
   속도(측정 완료) + 면적 + 전력 = 완전한 PPA 비교.
   - 합성 대상: rtl/gemm_accelerator/*.v + gemm_cpu_glue + gemm_system_top + CPU
   - 듀얼포트 behavioral BRAM은 보드의 Block Memory Generator IP로 교체
2. **FPGA 검증 (Zybo-Z7)**
3. (확장) 8-MAC / systolic array — 합성·비교 후 결정

## 설계 노트
- MAC_MODE 기본값은 gemm_system_top/gemm_accelerator_top에서 설정. 합성 시
  -GMAC_MODE로 오버라이드.
- 듀얼포트 BRAM은 true dual-port(Port A R/W, Port B R). 보드 IP 설정 시 동일 구성.
- 모든 곱셈 결과는 32-bit signed로 확장 후 누산 (width 경고 없음).
