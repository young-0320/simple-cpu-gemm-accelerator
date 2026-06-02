# 협업 규칙

## 1. 폴더 구조

```
repo/
├── rtl/    ← CPU, 가속기, 버스, 메모리 등 RTL 설계 소스
├── sw/     ← CPU 구동용 어셈블리, 어셈블러, 프로그램 코드
├── sim/    ← 테스트벤치, Verilator, 파형 등 시뮬레이션 파일
├── model/  ← Python/C++ 참조/골든 모델
├── asic/   ← ASIC 합성/검증 관련 제약, 스크립트, 리포트
├── fpga/   ← FPGA/Vivado 제약, 스크립트, IP, bitstream
└── docs/   ← 문서 및 스펙
```

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
