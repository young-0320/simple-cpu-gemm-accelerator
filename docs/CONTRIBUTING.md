# 협업 규칙

## 1. 폴더 구조

```
repo/
├── rtl/                         ← 합성 가능한 Verilog/SystemVerilog RTL, top-level/shared RTL
│   ├── simple_cpu/              ← CPU core, decoder, controller, register file
│   └── gemm_accelerator/        ← GEMM MMIO, FSM, LSU, buffer, MAC datapath
├── sw/                          ← CPU에서 실행할 프로그램과 보조 도구
│   ├── programs/                ← assembly/source program, test workload
│   └── tools/                   ← assembler, loader, hex/coe 변환 스크립트
├── sim/                         ← RTL 검증 환경
│   ├── tb/                      ← unit/top-level testbench
│   ├── tests/                   ← test case, random seed, expected output, vector manifest
│   └── waves/                   ← waveform 산출물, Git에는 .gitkeep만 남김
├── model/                       ← golden/reference model과 test vector 생성 코드
├── asic/                        ← ASIC flow 입력 파일과 결과 정리
│   ├── oasys/                   ← Oasys synthesis script, constraint, report 정리
│   └── nitro/                   ← Nitro P&R script, constraint, report 정리
├── fpga/                        ← FPGA/Vivado bring-up 파일
│   ├── Zybo-Z7.xdc              ← Zybo Z7 FPGA pin/clock constraint
│   ├── scripts/                 ← Vivado project/build/bitstream 자동화 스크립트
│   └── vivado/                  ← generated Vivado project, Git에는 .gitkeep만 남김
└── docs/                        ← 사람이 읽는 문서
    ├── spec/                    ← 설계 스펙과 인터페이스 계약
    ├── report/                  ← 최종 보고서, 실험 결과, 성능/전력 분석
    ├── project2.md              ← 과제 요구사항 정리
    └── CONTRIBUTING.md          ← 협업 규칙
```

### 배치 기준

1. RTL은 소유 모듈 기준으로 둔다. CPU 전용이면 `rtl/simple_cpu/`, GEMM 전용이면 `rtl/gemm_accelerator/`, top-level이나 둘이 같이 쓰는 파일은 `rtl/` 바로 아래에 둔다.
2. `sw/`는 실제 CPU가 실행하는 program과 이를 만들기 위한 tool만 둔다. 검증용 Python golden model은 `sw/`가 아니라 `model/`에 둔다.
3. `sim/`에는 testbench와 test case를 둔다. Verilator가 만든 `obj_dir`, waveform, log 같은 산출물은 Git에 올리지 않는다.
4. `fpga/`와 `asic/`에는 source 역할을 하는 script, constraint, report 요약만 남긴다. Vivado project output, bitstream, tool log는 생성 산출물로 보고 Git 추적을 피한다.
5. `docs/spec/`는 설계가 바뀔 때 같이 업데이트한다. 결과 캡처, 표, 최종 보고서 초안은 `docs/report/`에 둔다.

## 2. 파일 네이밍 규칙

1. 모든 파일명은 소문자 + 언더스코어 방식으로 작성한다.
2. 파일 이름과 모듈 이름은 일치시킨다 (예: `full_adder.v` → `module full_adder`).
3. 하나의 파일에는 하나의 모듈만 작성한다.
4. 테스트 벤치의 파일 이름은 tb_로 시작한다 (예: `tb_full_adder.v`).

## 3. Git 사용법

### **기본 원칙**

**중요 : 작업 전에 항상 최신 코드를 받는다.**

먼저 현재 작업 중인 변경사항이 있는지 확인한다.

```
git status
```

작업 중인 변경사항이 없다면 최신 코드를 받는다.

`git pull origin main`

작업 완료 후에는 바로 `git add .`를 하기 전에 변경 파일과 변경량을 확인한다.

```
git status
git diff --stat
```

커밋에 넣을 파일만 골라서 stage 한다.

```
git add <파일 경로>
```

예시:

```
git add rtl/simple_cpu/alu.v
git add sim/tb/tb_alu.v
git add docs/spec/simple_cpu.md
```

모든 변경사항을 의도적으로 커밋할 때만 `git add .`를 사용한다.

변경사항을 확인한 뒤 commit과 push를 한다.

```
git commit -m "커밋 메시지"
git push origin main
```

### **커밋 메시지**

선택 사항입니다.

```
feat:     새 기능 추가
fix:      버그 수정
test:     Testbench 추가 또는 수정
docs:     문서 수정
refactor: 기능 변경 없이 코드 정리
```

예시

```
feat: ALU 비교 연산(EQ, GT) 추가
fix: FSM DECODE 상태에서 제어 신호 오류 수정
test: tb_alu 단위 시뮬레이션 추가
docs: spec 업데이트
```

## 4. 주의사항

1. 작업 전에 꼭 `git pull`로 최신 코드 반영
2. `git push`하기 전 한번만 더 확인
