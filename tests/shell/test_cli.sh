#!/usr/bin/env bash
# 단일 CLI 진입점 spinner-to-kor — FR-16.
# 계약: 6개 서브커맨드가 기존 스크립트로 정확히 위임되고, 기존 진입점은 그대로 동작.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "== test_cli.sh =="
setup_sandbox
trap teardown_sandbox EXIT

CLI="$REPO_DIR/spinner-to-kor"
PROJ="$SANDBOX/cliproj"
mkdir -p "$PROJ"

# ── 인자 없음 / 알 수 없는 서브커맨드 → usage + exit 2 ──────
OUT="$("$CLI" 2>&1)"; RC=$?
if [[ "$RC" == "2" ]]; then pass "인자 없음 → exit 2"; else fail "인자 없음 → exit $RC"; fi
assert_contains "$OUT" "사용" "인자 없음 → usage 출력"

OUT="$("$CLI" bogus 2>&1)"; RC=$?
if [[ "$RC" == "2" ]]; then pass "알 수 없는 서브커맨드 → exit 2"; else fail "bogus → exit $RC"; fi

OUT="$("$CLI" help 2>&1)"; RC=$?
assert_eq "0" "$RC" "help → exit 0"

# ── status: 미설치 상태 ─────────────────────────────────
OUT="$("$CLI" status 2>&1)"; RC=$?
assert_eq "0" "$RC" "status 정상 종료 (조회 전용)"
assert_contains "$OUT" "미설치" "미설치 상태 표시"

# ── install 위임 (--project 옵션 투과) ──────────────────
"$CLI" install --project "$PROJ" >/dev/null 2>&1
PROJ_OURS="$(python3 - "$PROJ/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
pre = s.get("hooks", {}).get("PreToolUse", [])
print(sum(1 for e in pre if isinstance(e, dict)
          and any("spinner-to-kor" in str(h.get("command", ""))
                  for h in e.get("hooks", []) if isinstance(h, dict))))
PY
)"
if [[ "$PROJ_OURS" -ge 20 ]]; then pass "install --project 위임 + 옵션 투과"; else fail "install 위임 실패 (ours=$PROJ_OURS)"; fi

# ── update 위임 (전역) ──────────────────────────────────
OUT="$("$CLI" update 2>&1)"; RC=$?
assert_eq "0" "$RC" "update 정상 종료"
assert_file_exists "$HOME/.claude/scripts/.spinner-to-kor-version" "update → 전역 설치 경로 실행(스탬프)"

# ── verify / status: 설치 후 ────────────────────────────
OUT="$("$CLI" verify 2>&1)"
assert_contains "$OUT" "[1] 활성 바이너리" "verify 위임"
OUT="$("$CLI" status 2>&1)"
assert_contains "$OUT" "$(cat "$REPO_DIR/VERSION")" "status에 설치 버전 표시"
assert_contains "$OUT" "패치됨" "status에 바이너리 패치 상태 표시"

# ── patch 위임 (명시 경로) ──────────────────────────────
NEW="$VERSIONS/2.1.172"
python3 "$REPO_DIR/tests/make-fixture.py" "$NEW" >/dev/null
touch -t 202601010000 "$NEW"
"$CLI" patch "$NEW" >/dev/null 2>&1
assert_eq "0" "$(en_count "$NEW")" "patch 위임 — 명시 바이너리 패치"

# ── uninstall 위임 ──────────────────────────────────────
"$CLI" uninstall --project "$PROJ" >/dev/null 2>&1
PROJ_OURS="$(python3 - "$PROJ/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
pre = s.get("hooks", {}).get("PreToolUse", [])
print(sum(1 for e in pre if isinstance(e, dict)
          and any("spinner-to-kor" in str(h.get("command", ""))
                  for h in e.get("hooks", []) if isinstance(h, dict))))
PY
)"
assert_eq "0" "$PROJ_OURS" "uninstall --project 위임 + 옵션 투과"

report
