#!/usr/bin/env bash
# install → update → uninstall E2E — FR-10/11/12/13/15/17, NFR-01/03.
# 핵심: 기존 설치 사용자가 재설치·삭제 없이 업데이트 받고, 사용자 설정은 무간섭.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "== test_install_e2e.sh =="
setup_sandbox
trap teardown_sandbox EXIT
export SPINNER_PLATFORM=darwin   # 이 스위트는 macOS(LaunchAgent) 경로 고정 검증

BIN="$VERSIONS/2.1.170"
SNIPPET_TOTAL="$(python3 -c "
import json; print(len(json.load(open('$REPO_DIR/snippets/settings-hooks.json'))['PreToolUse']))")"

# ── 사전 상태: 사용자 고유 설정 + 구버전(레거시) 설치 흔적 ─────
python3 - "$SETTINGS" <<'PY'
import json, sys
settings = {
    "model": "opus",
    "hooks": {
        "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}],
        "PreToolUse": [
            {"matcher": "Bash",
             "hooks": [{"type": "command",
                        "command": "/usr/local/bin/my-security-check.sh",
                        "statusMessage": "보안 검사"}]},
            {"matcher": "Read",   # 구버전 spinner-to-kor 형식 (마커 없음)
             "hooks": [{"type": "command", "command": "true",
                        "statusMessage": "파일 읽는 중"}]},
        ],
    },
}
json.dump(settings, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
PY

# 구버전 계정별 라벨 LaunchAgent 흔적 (실사용 레거시 설치본 재현)
LEGACY_PLIST="$HOME/Library/LaunchAgents/dev.olduser.claude-spinner-patch.plist"
printf '<plist/>' > "$LEGACY_PLIST"

# ── 설치 (기존 사용자 관점에선 곧 "업데이트") ────────────────
OUT="$("$REPO_DIR/install.sh" 2>&1)"; RC=$?
assert_eq "0" "$RC" "install.sh 정상 종료"
assert_not_contains "$OUT" "✗" "설치 직후 verify 전 항목 ✓"
assert_file_absent "$LEGACY_PLIST" "구 라벨 LaunchAgent 마이그레이션(제거) — 중복 에이전트 방지"
assert_contains "$(cat "$LAUNCHCTL_LOG")" "unload $LEGACY_PLIST" "구 라벨 unload 호출"

assert_eq "$SNIPPET_TOTAL" "$(count_ours)" "우리 hook entry 수 == snippet 수"
S_NOW="$(cat "$SETTINGS")"
assert_contains "$S_NOW" "my-security-check.sh" "FR-12: 사용자 Bash hook 원형 보존"
assert_contains "$S_NOW" "say done" "사용자 Stop hook 보존"
assert_contains "$S_NOW" '"model": "opus"' "hook 외 사용자 설정 보존"
READ_ENTRIES="$(python3 -c "
import json; pre=json.load(open('$SETTINGS'))['hooks']['PreToolUse']
print(sum(1 for e in pre if isinstance(e,dict) and e.get('matcher')=='Read'))")"
assert_eq "1" "$READ_ENTRIES" "FR-17: 레거시 entry in-place 업그레이드, 중복 0"

assert_file_exists "$HOME/Library/LaunchAgents/dev.claude-spinner-patch.plist" "plist 생성"
assert_contains "$(cat "$LAUNCHCTL_LOG")" "load -w" "LaunchAgent load 호출"
assert_eq "0" "$(en_count "$BIN")" "바이너리 즉시 패치 완료"
STAMP="$HOME/.claude/scripts/.spinner-to-kor-version"
assert_file_exists "$STAMP" "FR-15: 버전 스탬프 기록"
assert_eq "$(cat "$REPO_DIR/VERSION")" "$(cat "$STAMP")" "스탬프 == repo VERSION"

# ── 재실행(업데이트): 멱등 + 무간섭 ─────────────────────────
BEFORE="$(cat "$SETTINGS")"
echo "0.0.1" > "$STAMP"   # 구버전 설치본 흉내
OUT="$("$REPO_DIR/install.sh" --update 2>&1)"; RC=$?
assert_eq "0" "$RC" "--update 정상 종료"
assert_contains "$OUT" "0.0.1" "업데이트 리포트에 이전 버전 표기"
assert_eq "$BEFORE" "$(cat "$SETTINGS")" "FR-11/17: 업데이트 후 settings 불변(멱등)"
assert_eq "$(cat "$REPO_DIR/VERSION")" "$(cat "$STAMP")" "스탬프 갱신"

# ── 제거(--restore-bin): 우리 것만 제거 + 원본 복원 ─────────
OUT="$("$REPO_DIR/uninstall.sh" --restore-bin 2>&1)"; RC=$?
assert_eq "0" "$RC" "uninstall.sh 정상 종료"
assert_eq "0" "$(count_ours)" "우리 hook 전량 제거"
S_NOW="$(cat "$SETTINGS")"
assert_contains "$S_NOW" "my-security-check.sh" "NFR-03: 제거 후에도 사용자 hook 보존"
assert_contains "$S_NOW" "say done" "제거 후 Stop hook 보존"
assert_file_absent "$HOME/.claude/scripts/patch-spinner-verbs.py" "스크립트 제거"
assert_file_absent "$STAMP" "버전 스탬프 제거"
assert_file_absent "$HOME/Library/LaunchAgents/dev.claude-spinner-patch.plist" "plist 제거"
OLDEST_BAK="$(ls -1 "$VERSIONS"/2.1.170.bak.* | head -1)"
if cmp -s "$BIN" "$OLDEST_BAK"; then
  pass "NFR-01: --restore-bin 후 바이너리 == 깨끗한 원본"
else
  fail "NFR-01: 복원된 바이너리가 원본과 다름"
fi

# ── 깨진 settings.json: 설치 중단 + 무변경 ──────────────────
teardown_sandbox
setup_sandbox
echo '{broken json!!' > "$SETTINGS"
OUT="$("$REPO_DIR/install.sh" 2>&1)"; RC=$?
if [[ "$RC" != "0" ]]; then pass "깨진 JSON → 설치 중단(비정상 종료)"; else fail "깨진 JSON인데 설치 성공"; fi
assert_eq '{broken json!!' "$(cat "$SETTINGS")" "실패 시 settings.json 무변경"

report
