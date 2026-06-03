# GEMM Golden Model

`model/python/golden_gemm.py`는 core oracle이다. CLI, random 생성, 파일 IO를 갖지 않는다. memory image와 transaction metadata를 입력으로 받아 expected GEMM transaction 결과만 계산한다.

`model/python/gen_gemm_vectors.py`는 SystemVerilog/Verilator transaction testbench가 사용할 vector 파일을 생성한다.

## 생성 모드

| 모드 | 필수 옵션 | 선택 옵션 | 기본 출력 위치 |
| --- | --- | --- | --- |
| Random only | `--seed` | `--valid-cases`, `--invalid-cases`, `--out-dir` | `sim/vectors/random_case` |
| Directed only | `--directed-file` | `--out-dir` | `sim/vectors/directed_case` |
| Mixed | `--directed-file`, `--seed` | `--valid-cases`, `--invalid-cases`, `--out-dir` | `sim/vectors/mixed_case` |

`--out-dir`를 직접 주면 위 기본 출력 위치 대신 지정한 경로를 사용한다.

Random case 개수를 지정하려면 `--seed`가 필요하다. `--seed`만 주고 case 개수를 생략하면 기본값으로 valid case 50개, invalid case 20개를 생성한다.

## 표준 실행 예시

Random only:

```bash
python3 model/python/gen_gemm_vectors.py --seed 20260603
```

Random case 개수 지정:

```bash
python3 model/python/gen_gemm_vectors.py \
  --seed 20260603 \
  --valid-cases 50 \
  --invalid-cases 20
```

Directed only:

```bash
python3 model/python/gen_gemm_vectors.py \
  --directed-file model/gemm_directed_cases.json
```

Mixed:

```bash
python3 model/python/gen_gemm_vectors.py \
  --directed-file model/gemm_directed_cases.json \
  --seed 20260603 \
  --valid-cases 50 \
  --invalid-cases 20
```

## Directed File 예시

```json
[
  {
    "name": "one_by_one_negative",
    "m": 1,
    "n": 1,
    "k": 1,
    "a": [[-3]],
    "b": [[7]],
    "a_base": "00000080",
    "b_base": "00000084",
    "c_base": "00000088"
  }
]
```

## 산출물

각 출력 디렉토리 안에는 같은 이름의 metadata/table 파일이 생성된다.

```text
manifest.json
cases.tsv
directed_000_init.mem
directed_000_expected.mem
random_000_init.mem
random_000_expected.mem
```

`manifest.json`은 사람이 확인하거나 디버깅할 때 쓰는 상세 metadata 파일이다. 파일 상단에 `mode`와 `seed`가 먼저 기록된다.

`cases.tsv`는 SystemVerilog testbench가 읽을 compact case table이다. `exp_status`는 expected 32-bit `GEMM_STATUS` word이다. Seed 정보는 `manifest.json`에서 확인한다.

`.mem` 파일은 case당 full 4096-word memory image이다. 한 줄이 32-bit word 하나이며, 8자리 hex로 저장된다. A/B는 row-based packed layout으로 배치하고, SystemVerilog testbench는 `$readmemh`로 읽으면 된다.

Generator는 실행 전에 출력 디렉토리의 기존 generated 파일(`manifest.json`, `cases.tsv`, `*_init.mem`, `*_expected.mem`)을 지우고 새로 생성한다. 다른 메모나 파일은 건드리지 않는다.

## 테스트

```bash
python3 -m unittest discover -s sim/tests/python -p 'test_*.py'
```
