#!/usr/bin/env bash
# 전체 테스트 실행기 — Python 단위 + 셸 회귀/E2E.
# 사용: tests/run.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }

bold "== 매핑 불변식 검증 =="
python3 - <<PY || FAILED=1
import importlib.util
spec = importlib.util.spec_from_file_location("pv", "$REPO_DIR/src/patch-spinner-verbs.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.validate_map()
print(f"OK — {len(m.VERB_MAP)}개 매핑 byte 길이 일치")
PY

bold "== Python 단위 테스트 =="
python3 "$REPO_DIR/tests/test_patch.py" || FAILED=1
python3 "$REPO_DIR/tests/test_merge_hooks.py" || FAILED=1
python3 "$REPO_DIR/tests/test_detect.py" || FAILED=1

bold "== 셸 테스트 =="
for t in "$REPO_DIR"/tests/shell/test_*.sh; do
  bash "$t" || FAILED=1
done

bold "== 전체 결과 =="
if [[ "$FAILED" == "0" ]]; then
  printf '\033[32m전체 테스트 통과\033[0m\n'
else
  printf '\033[31m실패한 테스트 있음\033[0m\n' >&2
fi
exit "$FAILED"
