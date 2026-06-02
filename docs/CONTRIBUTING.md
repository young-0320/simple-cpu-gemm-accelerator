# 협업 규칙

## 1. 폴더 구조

```
repo/
├── rtl/                         ← synthesizable RTL 설계 소스
│   ├── simple_cpu/              ← Simple CPU core, decoder, controller, register file 등
│   └── gemm_accelerator/        ← GEMM accelerator, MMIO register block, FSM, MAC datapath, LSU 등
├── sw/                          ← CPU 구동용 어셈블리, 어셈블러, 프로그램 코드
├── sim/                         ← 테스트벤치, Verilator, 파형, transactional verification 파일
├── model/                       ← Python/C++ 참조 모델 및 golden output 생성 코드
│   ├── python/                  ← Python reference model, random test vector 생성
│   └── cpp/                     ← C/C++ reference model 또는 Verilator 연동 코드
├── asic/                        ← ASIC 합성/검증 관련 파일
│   ├── oasys/                   ← Oasys 합성 스크립트, constraint, log, report
│   └── nitro/                   ← Nitro P&R 스크립트, constraint, log, report
├── fpga/                        ← FPGA/Vivado 검증 관련 파일
│   ├── scripts/                 ← Vivado project 생성, build, bitstream 생성 자동화 스크립트
│   ├── vivado/                  ← Vivado project, block design, generated output
│   └── Zybo-Z7.xdc              ← Zybo Z7 FPGA pin/clock constraint
└── docs/                        ← 프로젝트 문서
    ├── spec/                    ← CPU, GEMM accelerator, memory/interface 설계 스펙
    ├── report/                  ← 최종 보고서, 실험 결과, 성능/전력 분석 자료
    ├── project2.md              ← 프로젝트 요구사항 정리
    └── CONTRIBUTING.md          ← 협업 규칙
```

새 파일은 담당 모듈 기준으로 가장 가까운 하위 폴더에 둔다. 예를 들어 GEMM FSM RTL은 `rtl/gemm_accelerator/`, CPU instruction 관련 RTL은 `rtl/simple_cpu/`, Vivado 자동화 스크립트는 `fpga/scripts/`, 설계 설명 문서는 `docs/spec/`에 둔다.

비어 있는 폴더를 Git에 남겨야 하면 해당 폴더에 `.gitkeep`을 둔다.

## 2. 파일 네이밍 규칙

1. 모든 파일명은 소문자 + 언더스코어 방식으로 작성한다.
2. 파일 이름과 모듈 이름은 일치시킨다 (예: `full_adder.v` → `module full_adder`).
3. 하나의 파일에는 하나의 모듈만 작성한다.
4. 테스트 벤치의 파일 이름은 tb_로 시작한다 (예: `tb_full_adder.v`).

## 3. Git 사용법

### **기본 원칙**

**중요) 작업 전에 항상 최신 코드를 받는다.**
`git pull origin main`

작업 완료 후 push 한다.

```
git add .
git commit -m "커밋 메시지"
git push origin main
```

### **커밋 메시지**

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

1. 다른 사람 담당 모듈은 수정 금지
2. 작업 전에 꼭 `git pull`로 최신 코드 반영
3. `git push`하기 전 한번만 더 확인
