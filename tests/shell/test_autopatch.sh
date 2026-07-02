#!/usr/bin/env bash
# auto-patch-claude.sh 회귀 테스트 — BUG-04(FSEvents race)·BUG-05(이중 백업)·멱등성.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "== test_autopatch.sh =="
setup_sandbox
trap teardown_sandbox EXIT
deploy_scripts

AUTO="$HOME/.claude/scripts/auto-patch-claude.sh"
LOG="$HOME/.claude/logs/spinner-patch.log"
BIN="$VERSIONS/2.1.170"

# fixture mtime을 과거로 밀어 "안정된 파일" 상태로 시작
touch -t 202601010000 "$BIN"

# ── 1회차: 패치 성공 + 백업 1개만 (BUG-05: sh/py 이중 백업 금지) ──
"$AUTO"
assert_contains "$(tail -1 "$LOG")" "patched=1" "1회차 스캔 patched=1"
assert_eq "0" "$(en_count "$BIN")" "패치 후 영문 sentinel 0"
BAK_COUNT="$(ls -1 "$VERSIONS"/2.1.170.bak.* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "1" "$BAK_COUNT" "BUG-05: 패치 1회당 백업 정확히 1개"

# ── 2회차: 멱등 skip + 백업 무증가 ──────────────────────
"$AUTO"
assert_contains "$(tail -1 "$LOG")" "skipped=1" "2회차 이미 패치됨 → skip"
BAK_COUNT2="$(ls -1 "$VERSIONS"/2.1.170.bak.* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "1" "$BAK_COUNT2" "skip 시 백업 무증가"

# ── race: 쓰기 진행 중 파일은 연기 (BUG-04) ─────────────
NEW="$VERSIONS/2.1.171"
python3 "$REPO_DIR/tests/make-fixture.py" "$NEW" >/dev/null
(
  i=0
  while [[ $i -lt 30 ]]; do printf 'x' >> "$NEW"; sleep 0.2; i=$((i + 1)); done
) &
WRITER=$!
sleep 0.3
SPINNER_PATCH_SETTLE_SECS=1 "$AUTO"
assert_contains "$(tail -3 "$LOG" | tr '\n' ' ')" "연기" "쓰기 중 파일 → 패치 연기 로그"
assert_eq "0" "$([[ "$(en_count "$NEW")" == "0" ]] && echo 1 || echo 0)" \
  "쓰기 중 파일은 미패치 상태 유지"
kill "$WRITER" 2>/dev/null; wait "$WRITER" 2>/dev/null

# ── 쓰기 완료 후 재실행: 정상 패치 ──────────────────────
sleep 1
SPINNER_PATCH_SETTLE_SECS=1 "$AUTO"
assert_eq "0" "$(en_count "$NEW")" "쓰기 완료 후 재스캔 → 패치 성공"

# ── 미매핑 신규 verb → 패치 후 WARN 경보 (FR-31) ────────
EXTRA="$VERSIONS/2.1.180"
python3 - "$EXTRA" <<PY
import importlib.util, sys
spec = importlib.util.spec_from_file_location("mf", "$REPO_DIR/tests/make-fixture.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.build_fixture(sys.argv[1], extra_verbs=["Zooming"])
PY
touch -t 202601010000 "$EXTRA"
"$AUTO"
assert_contains "$(tail -5 "$LOG" | tr '\n' ' ')" "unmapped=1" \
  "미매핑 verb 잔존 → WARN unmapped=1 로그"
assert_eq "0" "$(en_count "$EXTRA")" "알려진 verb는 정상 패치됨"

report
