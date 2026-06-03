# GEMM Accelerator + CPU Integration (Baseline, 1-MAC serial)

simple-cpu-smart-doorlock 프로젝트의 CPU에 GEMM 코프로세서를 붙인 baseline.
`C = A x B` (A: MxK, B: KxN, C: MxN), 모든 차원 1~4 지원.
CPU 코어는 **수정하지 않고**, glue 레이어로 통합.

## 디렉토리 구조

```
gemm/
├── rtl/
│   ├── gemm_define.vh            상수 (MMIO offset, FSM state, dim range)
│   ├── gemm_mmio_reg.v           [Day1] MMIO 레지스터 블록
│   ├── gemm_controller_fsm.v     [Day2] 컨트롤러 FSM
│   ├── gemm_local_buffer.v       [Day2-3] a/b_buf(int8), c_buf(int32)
│   ├── gemm_lsu.v                [Day3]  Load/Store Unit
│   ├── gemm_mac_datapath.v       [Day4]  1-MAC serial
│   ├── gemm_accelerator_top.v    [Day4]  GEMM 5블록 통합
│   │
│   ├── gemm_cpu_glue.v           CPU<->GEMM 통합 레이어 (주소디코드/MMIO/arbitration)
│   ├── gemm_system_top.v         CPU + glue + GEMM + BRAM 시스템 top
│   │
│   ├── top_cpu.v, decoder.v, ... CPU 코어 (원본 그대로, 미수정)
│   │
│   └── tb_*.v                    검증용 wrapper
│
├── tb/                           C++ 테스트벤치
├── asm/
│   ├── gemm_call.asm             GEMM 호출 어셈블리 드라이버 (예: 2x2x2)
│   └── assembler.py             원본 어셈블러
└── sim/
    └── run_all_tests.sh          전체 테스트 한 번에 실행
```

## 검증 결과 (전부 통과)

| 스위트 | 대상 | 핵심 검증 |
|--------|------|-----------|
| mmio   | MMIO 레지스터 | base/dim write, start pulse, sticky status |
| fsm    | 컨트롤러 FSM | 전체 시퀀스, invalid_size, clear 복귀 |
| buf    | 로컬 버퍼 | int8/int32 r/w, c_clear, 동시 read |
| macbuf | MAC+버퍼 | **랜덤 320케이스** golden 일치 |
| lsu    | LSU LOAD | **랜덤 256케이스** unpack 정확 |
| top    | GEMM 단독 | **랜덤 192 트랜잭션** end-to-end |
| system | CPU+GEMM | **CPU 구동 랜덤 30케이스** golden 일치 |

system 스위트 = CPU가 실제 어셈블리를 실행해 GEMM register 설정 -> start ->
status polling -> 메모리의 C 결과 확인까지 전 과정.

## 재현 방법

```bash
cd sim
./run_all_tests.sh    # 각 스위트 끝에 "ALL PASS" 확인
```

## CPU 통합 핵심 설계

### 메모리 맵
```
0x000..       : 프로그램 코드 + A/B/C matrix 데이터
0xFF0..0xFF7  : GEMM MMIO 레지스터
```

### glue 역할 (gemm_cpu_glue.v)
- 주소 디코드: cpu_addr이 0xFF0~0xFF7이면 MMIO 접근
- STORE 0xF0x -> GEMM register write (BRAM 안 씀)
- LOAD 0xFF7 -> GEMM status 반환 (BRAM 1-cycle latency에 맞춰 정렬)
- **arbitration (stall-free)**: GEMM busy 동안 CPU를 freeze (clk_enable=0).
  LSU가 BRAM을 독점하므로 stall 로직이 전혀 없음. busy 끝나면 CPU 재개.

### 왜 stall이 없나
GEMM busy 동안 CPU는 어차피 데이터 메모리 접근이 금지(busy-time rule)되어
polling만 한다. 그래서 CPU를 통째로 멈춰도 잃는 게 없고, LSU는 한 cycle도
밀리지 않는다. 멈추는 것은 놀고 있던 CPU이지 일하는 LSU가 아니다.

### CPU는 미수정
top_cpu.v 등 CPU 코어 파일은 원본 그대로. glue가 CPU의 bram_* 신호를
가로채 라우팅하므로, CPU는 자기가 BRAM을 읽는지 GEMM status를 읽는지 모른다.

## GEMM 호출 어셈블리 패턴

```asm
    LOADI 0x100      ; A_BASE
    STORE 0xFF0
    LOADI 0x110      ; B_BASE
    STORE 0xFF1
    LOADI 0x120      ; C_BASE
    STORE 0xFF2
    LOADI 0x2        ; M, N, K
    STORE 0xFF3
    ...
    LOADI 0x1        ; start
    STORE 0xFF6
POLL:
    LOAD  0xFF7      ; status
    CMPI  0x2        ; done?
    JZ    FINISH
    JMP   POLL
FINISH:
    LOADI 0x2        ; clear_done
    STORE 0xFF6
```

## 다음 단계

1. **합성 (Oasys/Nitro)**: gemm_system_top 합성, 속도·전력 측정.
   - 합성 대상: gemm_*.v (tb_*.v 제외) + CPU 코어 + gemm_system_top
   - BRAM 모델은 보드의 Block Memory Generator IP로 교체
2. **FPGA 검증**: top_doorlock에 GEMM 통합 (또는 별도 top)
3. **4-MAC extension**: gemm_mac_datapath만 교체, 1-MAC과 PPA 비교
   - FSM/LSU/buffer/glue/system top 모두 재사용 가능

## 합성 참고

- 합성 가능 RTL: gemm_define.vh, gemm_mmio_reg, gemm_controller_fsm,
  gemm_local_buffer, gemm_lsu, gemm_mac_datapath, gemm_accelerator_top,
  gemm_cpu_glue, gemm_system_top + CPU 코어
- 제외: tb_*.v (검증용 wrapper), gemm_system_top의 behavioral BRAM은
  실제 BRAM IP로 교체
- $signed 사용 (합성 지원), local_buffer는 레지스터 어레이

## 4-MAC Extension (완료)

`gemm_accelerator_top`의 파라미터 `MAC_MODE`로 선택:
- `MAC_MODE=1` : 1-MAC serial (baseline)
- `MAC_MODE=4` : 4-MAC row-parallel (한 row의 N column 동시 계산)

```
acc0 += A[i][k]*B[k][0]
acc1 += A[i][k]*B[k][1]   (고정 i,k에서 4 column 병렬)
acc2 += A[i][k]*B[k][2]
acc3 += A[i][k]*B[k][3]
```

### 바뀐 파일 (3개)
- gemm_mac_datapath4.v  : 4-MAC datapath 신규
- gemm_local_buffer.v   : B row read 포트 추가 (b_row_k/n -> b_row0..3)
- gemm_accelerator_top.v: MAC_MODE generate로 1/4-MAC 선택

### 유지된 파일
- gemm_mmio_reg, gemm_controller_fsm, gemm_lsu, gemm_cpu_glue, gemm_system_top
  (mac_en/mac_done 핸드셰이크가 추상적이라 그대로 재사용)

### 검증
- 4-MAC end-to-end: 랜덤 192 트랜잭션 golden 일치
- 4-MAC MAC+buffer: 랜덤 320케이스 golden 일치
- 1-MAC 전체 회귀: 통과 (파라미터화해도 baseline 동일)

### COMPUTE 단계 사이클 비교 (1-MAC vs 4-MAC)
| size  | 1-MAC | 4-MAC | 비고 |
|-------|-------|-------|------|
| 4x4x4 |  68   |  36   | 47% 감소 |
| 3x3x3 |  31   |  22   | |
| 1x4x4 |  20   |  12   | |
| 4x4x1 |  20   |  24   | N=1, 4-MAC 오버헤드 |
| 4x1x4 |  20   |  24   | N=1, 동일 |
| 2x2x2 |  12   |  12   | |

LOAD/STORE 사이클은 두 모드 동일 (같은 LSU 재사용).
4-MAC은 N(column) 방향 병렬화 -> N이 클수록 유리, N=1이면 이득 없음.
PPA 분석: 속도 이득은 행렬 형태 의존적, 면적은 MAC 4배 + adder.

### 4-MAC 측정 재현
```bash
cd sim
for M in 1 4; do
  verilator [flags] -GMAC_MODE=$M --cc ../rtl/tb_gemm_top_wrap.v -I../rtl \
    --exe ../tb/tb_phase_count.cpp --Mdir obj_ph$M --top-module tb_gemm_top_wrap
  make -C obj_ph$M -f Vtb_gemm_top_wrap.mk && ./obj_ph$M/Vtb_gemm_top_wrap
done
```

## Memory Layout (중요: row-aligned packed format)

A/B는 row-aligned packed format을 사용한다. 각 row는 32-bit word 하나에
저장되며, 사용하지 않는 lane은 padding으로 둔다.

```
A[i] row address = A_BASE + i   (lane 0..K-1 = A[i][0..K-1], 나머지 padding)
B[k] row address = B_BASE + k   (lane 0..N-1 = B[k][0..N-1], 나머지 padding)
C[i][j]          = C_BASE + i*N + j   (int32, unpacked, 1 word/element)
```

예: A = [[1,2,3],[4,5,6]] (M=2,K=3)
```
mem[A_BASE+0] = pack(1,2,3,_)   ; row 0
mem[A_BASE+1] = pack(4,5,6,_)   ; row 1
```

이 방식은 4-MAC에 유리하다: B의 row k 하나를 한 word로 읽으면 B[k][0..3]이
한 번에 나와 4개 MAC에 동시 공급할 수 있다. (기존 연속 packing이 아님에 주의)

pack lane 순서: lane0=[7:0], lane1=[15:8], lane2=[23:16], lane3=[31:24]

### golden model / testbench packing (조원 참고)
RTL과 반드시 일치해야 하는 packing 규칙:
```c
// A: row i -> word
for(i=0;i<M;i++){ lane[0..K-1] = A[i][0..K-1]; mem[A_BASE+i] = pack(lane); }
// B: row k -> word
for(k=0;k<K;k++){ lane[0..N-1] = B[k][0..N-1]; mem[B_BASE+k] = pack(lane); }
// C: element -> word
C[i][j] read from mem[C_BASE + i*N + j]  (signed int32)
```

## 파형 보기 (x2go + GTKWave)

CPU+GEMM 통합 전체 트랜잭션을 파형으로 확인할 수 있다.

```bash
cd sim
./make_wave.sh 4      # 4-MAC 파형 (또는 ./make_wave.sh 1 로 1-MAC)
```

생성된 wave_system.vcd 를 x2go 데스크톱 터미널에서 GTKWave로 연다.

```bash
gtkwave wave_system.vcd
```

(GTKWave 미설치 시: apt-get install gtkwave, 또는 관리자에게 요청)

### 추천 관찰 신호 (GTKWave 계층에서 드래그)
| 모듈 | 신호 | 의미 |
|------|------|------|
| u_cpu  | pc_debug, acc_debug, state | CPU 명령어 실행 흐름 |
| u_glue | cpu_run, mmio_sel, mmio_off | busy 중 CPU freeze, MMIO 라우팅 |
| u_gemm | gemm_busy, gemm_state_debug | GEMM FSM 단계(IDLE/LOAD/COMPUTE/STORE/DONE) |
| u_gemm.u_lsu | mem_addr, mem_we | LSU 메모리 트래픽 |
| top | out_port | 0x8 = CPU 완료 신호 |

### 파형에서 보이는 흐름
1. CPU가 LOADI/STORE로 MMIO(0xFF0~)에 base/dim 기록 (mmio_sel 토글)
2. CTRL.start 후 gemm_busy=1 -> cpu_run=0 (CPU freeze)
3. gemm_state_debug가 LOAD(1)->COMPUTE(2)->STORE(3)->DONE(4) 전이
4. busy=0 -> cpu_run=1 (CPU 재개) -> STATUS polling -> out_port=0x8
