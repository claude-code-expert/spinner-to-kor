#!/usr/bin/env bash
# 플랫폼 추상화 — FR-41/42. src/platform.sh 의 감지·등록·해제·상태 함수.
# SPINNER_PLATFORM env 로 크로스플랫폼 경로를 실기 없이 검증한다.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "== test_platform.sh =="
setup_sandbox
trap teardown_sandbox EXIT
deploy_scripts

source "$REPO_DIR/src/platform.sh"
TEMPLATES="$REPO_DIR/templates"
SCRIPTS="$HOME/.claude/scripts"

# ── 감지 ────────────────────────────────────────────────
assert_eq "darwin" "$(SPINNER_PLATFORM=darwin spinner_detect_platform)" "darwin 강제 감지"
assert_eq "linux"  "$(SPINNER_PLATFORM=linux  spinner_detect_platform)" "linux 강제 감지"
DETECTED="$(spinner_detect_platform)"
if [[ "$DETECTED" == "darwin" || "$DETECTED" == "linux" ]]; then
  pass "실 플랫폼 감지 ($DETECTED)"
else
  fail "알 수 없는 플랫폼: $DETECTED"
fi

# ── darwin: plist + launchctl ───────────────────────────
export SPINNER_PLATFORM=darwin
spinner_register_autopatch "$SCRIPTS" "$TEMPLATES" >/dev/null 2>&1
PLIST="$HOME/Library/LaunchAgents/dev.claude-spinner-patch.plist"
assert_file_exists "$PLIST" "darwin: plist 생성"
assert_contains "$(cat "$LAUNCHCTL_LOG")" "load -w" "darwin: launchctl load 호출"
assert_eq "1" "$(spinner_autopatch_loaded)" "darwin: 로드 상태 1"
spinner_unregister_autopatch >/dev/null 2>&1
assert_file_absent "$PLIST" "darwin: unregister 후 plist 제거"

# ── linux: systemd path/service unit + systemctl ────────
export SPINNER_PLATFORM=linux
: > "$SYSTEMCTL_LOG"
spinner_register_autopatch "$SCRIPTS" "$TEMPLATES" >/dev/null 2>&1
UNIT_DIR="$HOME/.config/systemd/user"
assert_file_exists "$UNIT_DIR/spinner-patch.path" "linux: .path unit 생성"
assert_file_exists "$UNIT_DIR/spinner-patch.service" "linux: .service unit 생성"
assert_contains "$(cat "$UNIT_DIR/spinner-patch.path")" "$VERSIONS" "linux: PathModified 경로 치환"
assert_contains "$(cat "$UNIT_DIR/spinner-patch.service")" "$SCRIPTS/auto-patch-claude.sh" "linux: ExecStart 경로 치환"
assert_contains "$(cat "$SYSTEMCTL_LOG")" "enable" "linux: systemctl enable 호출"
assert_not_contains "$(cat "$SYSTEMCTL_LOG")" "launchctl" "linux: launchctl 미사용"
spinner_unregister_autopatch >/dev/null 2>&1
assert_file_absent "$UNIT_DIR/spinner-patch.path" "linux: unregister 후 .path 제거"
assert_contains "$(cat "$SYSTEMCTL_LOG")" "disable" "linux: systemctl disable 호출"

# ── 멱등성: 재등록해도 unit 중복/오류 없음 ──────────────
spinner_register_autopatch "$SCRIPTS" "$TEMPLATES" >/dev/null 2>&1
spinner_register_autopatch "$SCRIPTS" "$TEMPLATES" >/dev/null 2>&1
assert_file_exists "$UNIT_DIR/spinner-patch.path" "linux: 재등록 멱등"

report
