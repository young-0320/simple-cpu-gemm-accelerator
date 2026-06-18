# ASIC Power 측정 워크플로우 (VCD 기반)

Oasys/Nitro의 기본 power 추정은 toggle-rate 가정 기준이다. 실제 워크로드 기준
dynamic power를 보려면 Verilator로 VCD를 직접 생성해 Oasys config의
`vcd_file`/`vcd_scope`에 연결해야 한다. 이 문서는 그 절차를 설명한다.

## 1. 대상 config (6개)

| 구성                   | config.tcl                                  | VCD 소스                  |
| ---------------------- | -------------------------------------------- | -------------------------- |
| step2_mode1            | `asic/oasys/step2_mode1_vcd_config.tcl`     | `tb_gemm_vectors_single` |
| step2_mode4            | `asic/oasys/step2_mode4_vcd_config.tcl`     | `tb_gemm_vectors_single` |
| step3_mode1 (원본 4096) | `asic/oasys/step3_mode1_vcd_config.tcl`     | `tb_gemm_system_v2`      |
| step3_mode4 (원본 4096) | `asic/oasys/step3_mode4_vcd_config.tcl`     | `tb_gemm_system_v2`      |
| step3_mode1_demo (256) | `asic/oasys/step3_mode1_demo_vcd_config.tcl` | `tb_gemm_system_v2`(원본과 동일 VCD 재사용) |
| step3_mode4_demo (256) | `asic/oasys/step3_mode4_demo_vcd_config.tcl` | `tb_gemm_system_v2`(원본과 동일 VCD 재사용) |

step3의 원본(4096)과 demo(256) config은 같은 VCD
(`step3_mode{1,4}_directed4x4x4/tb_gemm_system_v2.vcd`)를 재사용한다 — RTL의
동작(toggle pattern)은 메모리 폭과 무관하기 때문이다.

## 2. VCD 생성 (Verilator)

repository root에서 실행한다. `sim/results/`는 `.gitignore` 대상이라 GitHub에는
없으므로, 필요할 때마다 로컬/서버에서 직접 생성해야 한다. 자세한 옵션은
`sim/README.md`를 참고한다.

```bash
# step2_mode1 -> sim/results/power/step2_mode1_directed006/tb_gemm_vectors_single.vcd
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb single \
  --mac-mode 1 \
  --trace-vcd \
  --case-name directed_006

# step2_mode4 -> sim/results/power/step2_mode4_directed006/tb_gemm_vectors_single.vcd
python3 sim/scripts/run_gemm_verification.py \
  --rtl-dir rtl/gemm_accelerator \
  --vector-dir sim/vectors/directed_case \
  --tb single \
  --mac-mode 4 \
  --trace-vcd \
  --case-name directed_006

# step3_mode1 -> sim/results/power/step3_mode1_directed4x4x4/tb_gemm_system_v2.vcd
python3 sim/scripts/run_gemm_system_verification.py \
  --mac-mode 1 \
  --trace-vcd \
  --case-name directed_4x4x4_signed

# step3_mode4 -> sim/results/power/step3_mode4_directed4x4x4/tb_gemm_system_v2.vcd
python3 sim/scripts/run_gemm_system_verification.py \
  --mac-mode 4 \
  --trace-vcd \
  --case-name directed_4x4x4_signed
```

위 4개 명령으로 6개 config가 참조하는 VCD를 전부 만들 수 있다 — step3 두 개는
원본(4096)/demo(256) config 양쪽에서 재사용된다.

## 3. Oasys 실행

생성된 VCD 경로가 각 config.tcl의 `vcd_file`과 일치하는지 확인한 뒤, 학교
서버에서 6개 config로 Oasys를 재실행하고 `report_power` 결과를 받는다.
권장 진행 순서: step2_mode1 → step2_mode4 → step3_mode1_demo →
step3_mode4_demo → step3_mode1 → step3_mode4 (원본 step3는 합성이 길어
마지막으로 미룬다).

## 4. Nitro

Nitro tcl에는 `report_power` 명령이 없다. VCD 기반 power 리포트를 Nitro에서
뽑으려면 사용 중인 버전이 이를 지원하는지 먼저 확인해야 한다(미확인 상태).
