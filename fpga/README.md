# FPGA 검증 가이드 (Zybo Z7-20)

과제 3번 "FPGA 검증(속도 및 전력소모 비교)"을 위한 Vivado synthesis/implementation
워크플로우다. 정확성 검증은 Verilator 트랜잭션 테스트로 이미 끝났으므로, 이
단계의 핵심 산출물은 **timing(속도)과 power 리포트**이다. 보드의 LED는 "정상
종료했다"만 보여주는 최소 확인용이고, ILA 등으로 연산 결과를 다시 검증하지는
않는다.

## 1. 합성 대상

`rtl_v2/gemm_system_top.v`(원본 4096-word)를 그대로 합성한다.
`asic/demo_mem256/`의 256-word 축소본은 ASIC(Oasys/Nitro) 전용 workaround이므로
FPGA에는 가져오지 않는다 — Oasys/Nitro는 memory macro가 없어 `reg [31:0]
mem[0:4095]`가 131,072개 FF로 펼쳐지지만, Vivado는 이 코딩 스타일(동기식 read,
write/read 포트 분리)을 표준 dual-port BRAM inference 템플릿으로 인식해서
`RAMB36E1` 등 진짜 BRAM 프리미티브로 자동 매핑하기 때문이다. Block Memory
Generator IP를 따로 붙일 필요 없다. (합성 로그의 `Inferring RAM` 메시지,
`report_utilization`의 `Block RAM Tile` 카운트로 실제 BRAM 매핑 여부를 확인한다.)

## 2. 구성 요소

- `Zybo-Z7.xdc`: `clk`(K17, 125MHz), `reset`(btn[0]=K18), `led[0:3]` 핀 매핑.
  미사용 `ja` 핀 블록은 주석 처리(이 design에 `ja` 포트 없음).
- `rtl_v2/zybo_top.v`: top wrapper. `CONTRIBUTING.md` 규칙상 `fpga/`는
  script/constraint/report 전용이라 RTL은 다른 design과 같이 `rtl_v2/`에 둔다.
  `gemm_system_top`의 `in_port[8:0]`은 `gemm_call.asm`이 읽지 않으므로 9'd0으로
  tie-off, `pc_debug`/`acc_debug`/`gemm_busy_debug`/`gemm_state_debug`는 핀에
  내보내지 않고 open(`()`)으로 둔다. 외부로 노출하는 포트는 `clk`, `reset`,
  `led[3:0]`뿐이고 `Zybo-Z7.xdc`는 이 wrapper 기준으로 작성됐다. reset은
  active-high로 직접 연결한다(`tb_gemm_system_v2.sv`의 reset 극성과 Zybo 버튼
  `btn[0]` 모두 active-high이므로 별도 반전 불필요).
- `fpga/scripts/build_and_report.tcl`: Vivado 2024.2 기준 project-mode
  빌드/스윕 스크립트. `MAC_MODE`와 clk period(ns)를 `-tclargs`로 받아
  `fpga/vivado/gemm_fpga_mode<N>/`에 빌드를 생성/재사용하고, 매 실행마다
  `Zybo-Z7.xdc`를 복사해 `create_clock -period`만 바꾼 스윕용 XDC로 교체한 뒤
  `synth_1`/`impl_1`(route_design까지)을 재실행한다. (이 머신에는 Zybo Z7
  board file이 `board.repopaths`에 등록돼 있지 않아, 재현성을 위해 raw part
  `xc7z020clg400-1` + `Zybo-Z7.xdc`로 진행한다.)
- `verilog_define GEMM_MEM_INIT="<repo>/fpga/vivado/gemm_call_full.hex"`로
  `rtl_v2/gemm_system_top.v`의 `` $readmemh(`GEMM_MEM_INIT, mem) ``에 연결된다
  (hex는 아래 "3. BRAM 초기화 hex 만들기"로 미리 생성).

## 3. BRAM 초기화 hex 만들기

`gemm_call.asm`만 어셈블하면 명령어만 들어가고 A/B 행렬 데이터는 비어있다.
보드용 단일 init hex는 2단계로 만든다.

1. (참고용, 보통 직접 쓸 필요 없음) `sw/tools/assembler.py` 단독 실행:

   ```bash
   python3 sw/tools/assembler.py sw/programs/gemm_call.asm gemm_call.hex --format hex
   ```

   `--format coe`(기본값)는 기존 `doorlock.asm` → Block Memory Generator COE
   워크플로우용이고, `--format hex`는 `$readmemh`가 읽는 raw hex(줄당 8자리,
   구분자 없음)다.

2. `sw/tools/build_mem_image.py`로 프로그램 hex와 A/B 데이터를 한 이미지로 합친다:

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

   - `--a`/`--b`는 row-major 순서의 signed int8 값을 콤마로 나열한다(각각
     M*K개, K*N개여야 함 — 개수 안 맞으면 에러).
   - `--a-base`/`--b-base`는 `gemm_call.asm`에 STORE되는 A_BASE/B_BASE와
     반드시 일치시켜야 한다(현재 `gemm_call.asm`은 0x100/0x110 하드코딩).
   - 출력 `gemm_call_full.hex`가 Vivado 프로젝트에서 `GEMM_MEM_INIT`이
     가리켜야 할 최종 파일이다.

## 4. 결과 요약

- **Timing**: 두 MAC_MODE 모두 ASIC sweep과 같은 그리드(100/50/33.3/20/10MHz)로
  스윕했다. `MAC_MODE=1`은 12ns(83.3MHz)까지 pass, 11ns(90.9MHz)에서
  WNS=-0.379ns로 fail; `MAC_MODE=4`는 12ns(83.3MHz, margin 0.05%)까지 pass,
  11ns에서 WNS=-0.567ns로 fail. margin 10~20%대에 들어오는 가장 빠른 지점은
  두 mode 모두 **15ns(66.7MHz)**로 수렴한다(가정이 아니라 독립 측정 결과 —
  ASIC step3_demo의 "critical path가 CPU accumulator에 있다"는 결론과
  일치). 자세한 표는 `fpga/reports/mode{1,4}/sweep_summary_mode{1,4}.md` 참고.
  - **caveat**: 이 Fmax는 "route_design까지 timing을 닫을 수 있는 가장 빠른
    주기"라는 합성 측정값이다. Zybo 보드의 실제 오실레이터(`clk`, K17)는
    125MHz(8ns) 고정이라, 66.7MHz를 MMCM/Clocking Wizard 없이 보드에 그대로
    줄 수는 없다(이번 작업 범위 밖이라 추가하지 않았다).
- **Power**: `report_power`는 vectorless(activity-less) 추정만 사용했다 — 이
  머신 Vivado에는 VCD→SAIF 변환 도구가 없어 switching-activity 기반 측정
  (Oasys/Nitro 방식)을 쓰지 못한다. ASIC power 절대값과 직접 비교하지 말고,
  같은 sweep 방법론(주파수 대비 power 추이)만 비교 축으로 쓴다. 15ns(66.7MHz)
  기준 total power: mode1 130mW, mode4 128mW.
- **Utilization**: 모든 sweep 지점에서 Block RAM Tile = 4(RAMB36E1) — 메모리가
  FF로 펼쳐지지 않고 정상적으로 BRAM에 매핑됨을 확정. LUT/FF는 mode4가 mode1보다
  약 34%/11% 더 많이 쓴다(4-MAC 병렬 datapath). 두 mode 모두 DSP48 사용 0개
  (곱셈기가 LUT 로직으로 추론됨).

## 5. 참고: out_port(LED) 동작

`gemm_call.asm`은 GEMM 완료를 폴링하다 상태값이 정확히 `2`(`busy=0, done=1,
error=0, invalid_size=0`)일 때만 빠져나와 `led[3]`을 켠다(`OUT 0x0` ← `0x8`).
`error`/`invalid_size`가 뜨는 경우는 상태값이 `2`가 될 수 없어서 POLL 루프에서
멈춘다 — 즉 "정상=LED on, 비정상=무한 대기(LED off)"이며, 비정상 상태를 별도
LED 패턴으로 명시적으로 구분하지는 않는다. 이번 데모는 M=N=K=2로 고정돼 있어
invalid_size가 뜰 일이 없으므로 우선순위는 낮다(필요해지면 asm에서
error/invalid_size 비트를 따로 분기하도록 수정).
