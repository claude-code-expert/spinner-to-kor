#!/usr/bin/env bash
# 프로젝트 스코프 설치/제거 — FR-14.
# 핵심: Layer A만, 전역 ↔ 프로젝트 상호 무간섭, merge-hooks 계약 그대로 적용.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "== test_project_scope.sh =="
setup_sandbox
trap teardown_sandbox EXIT

PROJ="$SANDBOX/myproject"
PROJ_SETTINGS="$PROJ/.claude/settings.json"
mkdir -p "$PROJ"
SNIPPET_TOTAL="$(python3 -c "
import json; print(len(json.load(open('$REPO_DIR/snippets/settings-hooks.json'))['PreToolUse']))")"

count_ours_in() {
  python3 - "$1" <<'PY'
import json, sys, os
if not os.path.exists(sys.argv[1]):
    print(0); raise SystemExit
s = json.load(open(sys.argv[1]))
pre = s.get("hooks", {}).get("PreToolUse", [])
print(sum(1 for e in pre if isinstance(e, dict)
          and any("spinner-to-kor" in str(h.get("command", ""))
                  for h in e.get("hooks", []) if isinstance(h, dict))))
PY
}

# 프로젝트에 사용자 고유 hook 선재
python3 - "$PROJ_SETTINGS" <<'PY'
import json, os, sys
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
json.dump({"hooks": {"PreToolUse": [
    {"matcher": "Bash",
     "hooks": [{"type": "command", "command": "./scripts/project-guard.sh"}]}]}},
    open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
PY

# ── 프로젝트 설치: Layer A만, 전역 무간섭 ───────────────────
OUT="$("$REPO_DIR/install.sh" --project "$PROJ" 2>&1)"; RC=$?
assert_eq "0" "$RC" "install.sh --project 정상 종료"
assert_eq "$SNIPPET_TOTAL" "$(count_ours_in "$PROJ_SETTINGS")" "프로젝트 settings에 우리 hook 전량"
assert_contains "$(cat "$PROJ_SETTINGS")" "project-guard.sh" "프로젝트 사용자 hook 보존"
assert_file_absent "$SETTINGS" "전역 settings.json 무변경(미생성)"
assert_file_absent "$HOME/.claude/scripts/patch-spinner-verbs.py" "전역 스크립트 미배치 (Layer B 제외)"
assert_file_absent "$HOME/Library/LaunchAgents/dev.claude-spinner-patch.plist" "LaunchAgent 미등록 (Layer C 제외)"
assert_contains "$OUT" "전역" "전역 레이어(B/C) 안내 출력"
BAK_COUNT="$(ls -1 "$PROJ_SETTINGS".bak.* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "1" "$BAK_COUNT" "기존 프로젝트 settings 백업 생성"

# ── 멱등성 ──────────────────────────────────────────────
BEFORE="$(cat "$PROJ_SETTINGS")"
"$REPO_DIR/install.sh" --project "$PROJ" >/dev/null 2>&1
assert_eq "$BEFORE" "$(cat "$PROJ_SETTINGS")" "재실행 멱등 (settings 불변)"

# ── DIR 생략 = $PWD ─────────────────────────────────────
PROJ2="$SANDBOX/proj2"
mkdir -p "$PROJ2"
( cd "$PROJ2" && "$REPO_DIR/install.sh" --project >/dev/null 2>&1 )
assert_eq "$SNIPPET_TOTAL" "$(count_ours_in "$PROJ2/.claude/settings.json")" "--project 인자 생략 시 \$PWD 대상"

# ── 전역 설치와 상호 무간섭 ─────────────────────────────
"$REPO_DIR/install.sh" >/dev/null 2>&1   # 전역 설치
GLOBAL_BEFORE="$(cat "$SETTINGS")"
"$REPO_DIR/install.sh" --project "$PROJ" >/dev/null 2>&1
assert_eq "$GLOBAL_BEFORE" "$(cat "$SETTINGS")" "프로젝트 재설치가 전역 settings 무변경"
PROJ_BEFORE="$(cat "$PROJ_SETTINGS")"
"$REPO_DIR/install.sh" --update >/dev/null 2>&1   # 전역 업데이트
assert_eq "$PROJ_BEFORE" "$(cat "$PROJ_SETTINGS")" "전역 업데이트가 프로젝트 settings 무변경"

# ── 프로젝트 제거: 우리 것만, 전역 무간섭 ────────────────
OUT="$("$REPO_DIR/uninstall.sh" --project "$PROJ" 2>&1)"; RC=$?
assert_eq "0" "$RC" "uninstall.sh --project 정상 종료"
assert_eq "0" "$(count_ours_in "$PROJ_SETTINGS")" "프로젝트 우리 hook 전량 제거"
assert_contains "$(cat "$PROJ_SETTINGS")" "project-guard.sh" "제거 후 프로젝트 사용자 hook 보존"
assert_eq "$GLOBAL_BEFORE" "$(cat "$SETTINGS")" "프로젝트 제거가 전역 settings 무변경"
assert_file_exists "$HOME/Library/LaunchAgents/dev.claude-spinner-patch.plist" "프로젝트 제거가 LaunchAgent 유지"

# ── 엣지: 없는 디렉터리 / 깨진 프로젝트 JSON ─────────────
OUT="$("$REPO_DIR/install.sh" --project "$SANDBOX/no-such-dir" 2>&1)"; RC=$?
if [[ "$RC" != "0" ]]; then pass "없는 디렉터리 → 비정상 종료"; else fail "없는 디렉터리인데 성공"; fi

PROJ3="$SANDBOX/proj3"
mkdir -p "$PROJ3/.claude"
echo '{broken' > "$PROJ3/.claude/settings.json"
OUT="$("$REPO_DIR/install.sh" --project "$PROJ3" 2>&1)"; RC=$?
if [[ "$RC" != "0" ]]; then pass "깨진 프로젝트 JSON → 중단"; else fail "깨진 JSON인데 성공"; fi
assert_eq '{broken' "$(cat "$PROJ3/.claude/settings.json")" "실패 시 프로젝트 settings 무변경"

report
