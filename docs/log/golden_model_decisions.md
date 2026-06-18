# 골든 모델 및 Vector 생성 결정사항

## 역할 분리

- `model/python/golden_gemm.py`는 core oracle이다.
- `golden_gemm.py`는 CLI, random 생성, 파일 IO를 갖지 않는다.
- `model/python/gen_gemm_vectors.py`는 vector generator이다.
- generator는 golden model을 호출해 expected status, expected C, expected memory image를 만든다.

## 산출물 위치

생성 모드에 따라 기본 출력 디렉토리를 나눈다.

```text
sim/vectors/random_case    # random only
sim/vectors/directed_case  # directed only
sim/vectors/mixed_case     # directed + random
```

`--out-dir`를 직접 주면 지정한 경로를 사용한다.

## 생성 파일

각 출력 디렉토리 안에 아래 파일을 만든다.

```text
manifest.json
cases.tsv
*_init.mem
*_expected.mem
```

`manifest.json`은 사람이 보는 상세 metadata 파일이다. 파일 상단에는 `schema`, `mode`, `seed`를 둔다.

`cases.tsv`는 SystemVerilog testbench가 읽는 compact case table이다. Seed 정보는 넣지 않고 `manifest.json`에서 확인한다.

`.mem` 파일은 case당 full 4096-word memory image이다. 각 line은 32-bit word 하나이며 8자리 hex이다.

## Memory 초기화

초기 memory 전체는 seed 기반 pseudo-random pattern으로 채운다.

A/B matrix 영역은 generated matrix 값을 signed int8 row-based packed format으로 덮어쓴다. 각 row의 마지막 packed word에서 남는 padding lane은 `0`으로 채운다.

C 영역은 init image에서는 random pattern을 유지하고, expected image에서는 GEMM 결과로 overwrite한다.

## 옵션 조합

```text
--directed-file O, --seed O -> directed + random
--directed-file O, --seed X -> directed only
--directed-file X, --seed O -> random only
--directed-file X, --seed X -> error
```

Random case 개수를 지정하려면 `--seed`가 필요하다.

## Generated 파일 정리

Generator는 실행 전에 출력 디렉토리의 기존 generated 파일만 삭제한다.

```text
manifest.json
cases.tsv
*_init.mem
*_expected.mem
```

다른 메모 파일이나 사용자 파일은 건드리지 않는다.
