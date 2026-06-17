2026-6-17 작업 목록

## 다음 할 일

- [X] Verilator로 6개 VCD 로컬 생성 (아래 명령, `sim/results/`는 `.gitignore`라 GitHub에 없음 → 매번 로컬/서버에서 직접 생성해야 함)
- [ ] Oasys: step2_mode1/mode4, step3_mode1/mode4(원본 4096), step3_mode1/mode4_demo(256) config.tcl **6개**에 vcd_file/vcd_scope 채움 (완료, demo 2개도 `TOP.<tb>.dut` 형식으로 통일). 학교 서버에서 6개 config로 Oasys 재실행하고 report_power 결과 받아오기 (VCD 기반 dynamic power로 갱신). 진행 순서: step2_mode1 → step2_mode4 → step3_mode1_demo → step3_mode4_demo → step3_mode1 → step3_mode4 (원본 step3는 합성이 길어 마지막으로 미룸)
- [ ] Nitro: report_power 명령이 TCL에 없음. Nitro에서 power 리포트 뽑는 방법 확인 후 추가 (학교 사용 버전이 VCD 기반 power 리포트를 지원하는지 먼저 확인)

## Verilator VCD 생성 (power 분석용)

repository root에서 순서대로 실행. 자세한 옵션 설명은 `sim/README.md` 참고.

```bash
# 1. step2_mode1 -> sim/results/power/step2_mode1_directed006/tb_gemm_vectors_single.vcd
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb single \
  --mac-mode 1 \
  --trace-vcd \
  --case-name directed_006

# 2. step2_mode4 -> sim/results/power/step2_mode4_directed006/tb_gemm_vectors_single.vcd
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb single \
  --mac-mode 4 \
  --trace-vcd \
  --case-name directed_006

# 3. step3_mode1 -> sim/results/power/step3_mode1_directed4x4x4/tb_gemm_system_v2.vcd
python3 sim/scripts/run_gemm_system_verification.py \
  --mac-mode 1 \
  --trace-vcd \
  --case-name directed_4x4x4_signed

# 4. step3_mode4 -> sim/results/power/step3_mode4_directed4x4x4/tb_gemm_system_v2.vcd
python3 sim/scripts/run_gemm_system_verification.py \
  --mac-mode 4 \
  --trace-vcd \
  --case-name directed_4x4x4_signed
```

6개 명령 실행 후 생성된 VCD 경로가 Oasys config.tcl의 `vcd_file`과 일치하는지 확인한다. step2는 `asic/oasys/step2_mode{1,4}_config.tcl` 2개, step3는 같은 VCD(`step3_mode{1,4}_directed4x4x4/tb_gemm_system_v2.vcd`)를 원본 `step3_mode{1,4}_config.tcl`과 256-word 데모 `step3_mode{1,4}_demo_config.tcl` 양쪽에서 재사용하므로 4개, 총 **6개 config**에 반영한다.
