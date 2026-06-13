# step3 Full-System P&R Demo (BRAM 256 words)

## 왜 만들었나

`step3` full-system(`gemm_system_top`)은 내부에 behavioral BRAM
(`reg [31:0] mem[0:4095]`, 4096 words)을 가진다. ASIC memory macro 없이
합성하면 이 메모리가 register array로 펼쳐져 **약 131,072개의 flip-flop**이
되고, 전체 cell이 약 480,000개까지 폭증한다. 그 결과 Nitro P&R에서 routing
congestion(Edge/Node Overflow 50~76%)이 발생해 배치배선이 몇 시간이 지나도
끝나지 않는다.

이 demo는 BRAM을 **256 words로 축소**해서, full-system 구조(CPU + glue + GEMM
+ memory)는 그대로 유지하면서 P&R이 정상적으로 끝나도록 한 것이다.

- 4096 x 32 = 131,072 FF  →  256 x 32 = 8,192 FF (메모리 FF 16배 감소)
- 전체 cell 약 480,000  →  약 20,000 추정
- 4x4 GEMM workload는 수십 word면 충분하므로 256 words로도 정상 동작

원본(4096) 설계는 그대로 유지된다. 이 demo는 P&R 시연 전용이다.

## 무엇이 바뀌었나 (원본 대비)

1. `asic/demo_mem256/gemm_system_top.v`
   - `reg [31:0] mem [0:255];`  (원본: `[0:4095]`)
   - 메모리 인덱싱을 `bram_addr_a[7:0]` 등 하위 8비트로 (합성 안전)
   - 그 외 로직/포트는 원본과 동일

2. `asic/demo_mem256/gemm_call.asm`
   - A_BASE=0x20, B_BASE=0x50, C_BASE=0x80  (원본: 0x100/0x110/0x120)
   - 256 word 범위(0x00~0xFF) 안에 들어가고, 프로그램 코드 영역과 겹치지 않음
   - (0xFF0~0xFF7은 MMIO 레지스터라 메모리와 무관, 그대로 둠)

원본 `rtl_v2/gemm_system_top.v`, 원본 `step3.f`, `step3_mode0_config.tcl`은
건드리지 않는다.

## 사용법 (Oasys 합성)

1. `REPO_ROOT` 확인
   `step3_mode0_demo_config.tcl`의 `set REPO_ROOT {...}`를 **본인 repo 경로**로
   맞춘다. (지금 값은 예시이므로 반드시 자기 경로로 수정)

2. 파일 배치
   - `asic/demo_mem256/gemm_system_top.v`   (256 RTL)
   - `asic/demo_mem256/gemm_call.asm`        (데모 base)
   - `asic/oasys/step3_demo.f`               (system_top만 256 경로로 교체된 source list)
   - `asic/oasys/step3_mode0_demo_config.tcl`(step3_demo.f를 읽는 config)

3. (필요시) 프로그램 메모리 초기화 파일 재생성
   base address가 바뀌었으므로, `gemm_call.asm`을 어셈블러로 다시 돌려
   메모리 init(hex/coe) 파일을 새로 만든다. (프로그램을 메모리에 preload하는
   흐름을 쓰는 경우)

4. Oasys에서 `step3_mode0_demo_config.tcl`을 골라 합성
   - mode1, mode4도 데모로 돌리려면 이 config을 복사해 TOP_MODULE만
     `step3_system_top_mode1` / `_mode4`로 바꾼 demo config을 추가로 만든다.

5. 합성 후 netlist를 Nitro로 P&R
   - 이제 cell 수가 대폭 줄어 congestion 없이 정상적으로 완료된다.

## 보고서에 적을 것

- "full-system(step3)은 behavioral BRAM이 register array로 합성되어 area/power가
  왜곡되므로, P&R 시연을 위해 BRAM을 256 words로 축소한 demo로 진행했다."
- 이렇게 명시하면 축소가 정당한 데모 조건임이 분명해진다.
  (이미 oasys/README.md 2.3절에서 behavioral BRAM 왜곡 문제를 언급하고 있다.)
