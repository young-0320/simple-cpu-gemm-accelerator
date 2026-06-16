2026-6-17 작업 목록

## 목표

과제 3번 "FPGA 검증 (속도 및 전력소모 비교)" — Zybo Z7-20.
정확성 검증은 Verilator 트랜잭션 테스트로 이미 끝났으므로, FPGA 단계에서는
**Vivado synthesis/implementation 리포트(속도=timing, 전력=power)**가
핵심 산출물이다. ILA 등으로 보드에서 연산 결과를 다시 검증하지는 않는다.
LED는 "정상 종료했다"만 보여주는 최소 확인용.

## 합성 대상

- `rtl_v2/gemm_system_top.v` (원본 4096-word) 그대로 사용한다.
- `asic/demo_mem256/`의 256-word 축소본은 **ASIC(Oasys/Nitro) 전용 워크어라운드**라
  FPGA에는 가져오지 않는다 — Oasys/Nitro는 memory macro가 없어서
  `reg [31:0] mem[0:4095]`가 131,072개 FF로 펼쳐지지만, Vivado는 이 코딩
  스타일(동기식 read, write/read 포트 분리)을 표준 dual-port BRAM inference
  템플릿으로 인식해서 `RAMB36E1` 등 진짜 BRAM 프리미티브로 자동 매핑한다.
  Block Memory Generator IP를 따로 붙일 필요 없음.
  (합성 로그의 `Inferring RAM` 메시지, `report_utilization`의
  `Block RAM Tile` 카운트로 실제로 BRAM이 됐는지 확인할 것.)

## 현재 상태 / 남은 작업

- [x] `Zybo-Z7.xdc`: `clk`(K17, 125MHz), `reset`(btn[0]=K18), `led[0:3]` 매핑.
      미사용 `ja` 핀 블록은 주석 처리(우리 design에 `ja` 포트 없음).
- [x] **`zybo_top` wrapper 작성** (`rtl_v2/zybo_top.v`). `fpga/`는 CONTRIBUTING.md
      규칙상 script/constraint/report 전용이라 RTL은 다른 design들과 같이
      `rtl_v2/`에 둠. `gemm_system_top`의 포트 중 `in_port[8:0]`은
      `gemm_call.asm`이 전혀 읽지 않으므로 9'd0으로 tie-off, `pc_debug`/
      `acc_debug`/`gemm_busy_debug`/`gemm_state_debug`는 핀에 안 내보내고
      open(`()`)으로 둠. 외부로 노출하는 포트는 `clk`, `reset`, `led[3:0]`뿐 —
      `Zybo-Z7.xdc`는 이 wrapper 기준으로 작성됨. reset은 active-high로
      바로 연결(`tb_gemm_system_v2.sv`의 reset 극성과 Zybo 버튼 모두 active-high).
- [x] **BRAM 프리로드 hex 생성 스크립트 작성.** `sw/tools/assembler.py`를
      파라미터화(입출력 경로를 인자로 받음)하고 `--format hex` 출력(raw hex,
      `$readmemh`용, 기존 `--format coe` 기본값은 하위호환 유지)을 추가함.
      여기에 `sw/tools/build_mem_image.py`를 새로 만들어 어셈블된 프로그램과
      A/B 행렬 데이터(테스트벤치가 sim에서 따로 주입하던 것)를 한 hex 이미지로
      합침 — 사용법은 아래 "BRAM 초기화 hex 만들기" 참고.
      → 남은 건 이 출력 파일을 Vivado 프로젝트에서 `GEMM_MEM_INIT` define으로
      실제 연결하는 것 (다음 항목).
- [ ] Vivado 프로젝트 생성 (`fpga/scripts/`에 생성 스크립트, `fpga/vivado/`는
      산출물이라 `.gitkeep`만 추적). 이 스크립트에서 `verilog_define
      GEMM_MEM_INIT="<merged.hex 경로>"`를 설정해 `rtl_v2/gemm_system_top.v`의
      `$readmemh(\`GEMM_MEM_INIT, mem)`에 연결해야 함.
- [ ] Synthesis + Implementation 실행, timing closure 확인
      (`report_timing_summary` — Fmax/WNS. sysclk 125MHz 고정이라 못 맞으면
      Clocking Wizard로 분주 클럭 추가 검토).
- [ ] `report_power` 추출. 가능하면 vectorless 추정 대신 기존 Verilator
      VCD(`sim/results/power/step3_mode{1,4}_directed4x4x4/...vcd`)를 SAIF로
      변환해서 switching activity 기반으로 — Oasys 쪽과 같은 방식이라 비교 가능.
- [ ] `report_utilization`도 참고 자료로 남김 (BRAM 추론 확인 + 면적 참고).
- [ ] `MAC_MODE=1`, `MAC_MODE=4` 둘 다 반복해서 속도/전력 비교 (2번 항목의
      Oasys/Nitro PPA 비교와 같은 축).

## BRAM 초기화 hex 만들기

`gemm_call.asm`만 어셈블하면 명령어만 들어가고 A/B 행렬 데이터는 비어있다.
보드용 단일 init hex를 만들려면 2단계를 거친다.

1. (참고용, 보통 직접 쓸 필요 없음) `sw/tools/assembler.py` 단독 실행:

   ```bash
   python3 sw/tools/assembler.py sw/programs/gemm_call.asm gemm_call.hex --format hex
   ```

   `--format coe`(기본값)는 기존 `doorlock.asm` → Block Memory Generator COE
   워크플로우용이고, `--format hex`는 `$readmemh`가 읽는 raw hex(줄당 8자리,
   구분자 없음)다.

2. `sw/tools/build_mem_image.py`로 프로그램 hex와 A/B 데이터를 한 이미지로 합침:

   ```bash
   python3 sw/tools/build_mem_image.py sw/programs/gemm_call.asm gemm_call_full.hex \
     --a-base 0x100 --b-base 0x110 --m 2 --n 2 --k 2 \
     --a "1,2,3,4" --b "1,0,0,1"
   ```

   내부적으로 `assembler.py`의 `assemble_file`/`write_hex`를 그대로 import해서
   쓰므로 `assembler.py`를 직접 다시 실행할 필요는 없다 — `.asm` 파일 하나만
   넣으면 명령어 어셈블 + A/B packing(`docs/spec/data_memory.md` 규칙: row-major,
   4 lane/word, lane0=word[7:0]..lane3=word[31:24], row 끝나면 zero padding)을
   한 번에 처리해서 `gemm_call_full.hex` 하나를 만든다.

   - `--a`/`--b`는 row-major 순서의 signed int8 값을 콤마로 나열 (각각 M*K개,
     K*N개여야 함 — 개수 안 맞으면 에러).
   - `--a-base`/`--b-base`는 `gemm_call.asm`에 STORE되는 A_BASE/B_BASE와
     반드시 일치시켜야 함 (현재 `gemm_call.asm`은 0x100/0x110 하드코딩).
   - 출력 `gemm_call_full.hex`가 Vivado 프로젝트에서 `GEMM_MEM_INIT`이
     가리켜야 할 최종 파일.

## 참고: out_port(LED) 동작

`gemm_call.asm`은 GEMM 완료를 폴링하다 상태값이 정확히 `2`(`busy=0, done=1,
error=0, invalid_size=0`)일 때만 빠져나와 `led[3]`을 켠다(`OUT 0x0` ← `0x8`).
`error`/`invalid_size`가 뜨는 경우는 상태값이 `2`가 될 수 없어서 POLL 루프에서
멈춘다 — 즉 지금은 "정상=LED on, 비정상=무한 대기(LED off)"이며, 비정상 상태를
별도 LED 패턴으로 명시적으로 구분하진 않는다. 이번 데모는 M=N=K=2로 고정돼
있어 invalid_size가 뜰 일이 없으므로 우선순위는 낮음 (필요해지면 asm에서
error/invalid_size 비트를 따로 분기하도록 수정).
