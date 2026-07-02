#!/usr/bin/env bash
# Linux/WSL 전체 설치 E2E — FR-41/42. SPINNER_PLATFORM=linux 로 실기 없이 검증.
# 재서명(codesign) no-op, systemd 등록 경로.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "== test_linux_e2e.sh =="
setup_sandbox
trap teardown_sandbox EXIT
export SPINNER_PLATFORM=linux

BIN="$VERSIONS/2.1.170"
UNIT_DIR="$HOME/.config/systemd/user"

# ── 설치 ────────────────────────────────────────────────
OUT="$("$REPO_DIR/install.sh" 2>&1)"; RC=$?
assert_eq "0" "$RC" "linux install.sh 정상 종료"
assert_not_contains "$OUT" "macOS 전용" "linux에서 Darwin 게이트 미차단"

assert_file_exists "$HOME/.claude/scripts/patch-spinner-verbs.py" "스크립트 배치"
assert_eq "20" "$(count_ours)" "hook 머지 완료"
assert_file_exists "$UNIT_DIR/spinner-patch.path" "systemd .path unit 생성"
assert_contains "$(cat "$SYSTEMCTL_LOG")" "enable" "systemctl enable 호출"
assert_eq "0" "$(en_count "$BIN")" "바이너리 즉시 패치 (재서명 no-op)"
assert_file_exists "$HOME/.claude/scripts/.spinner-to-kor-version" "버전 스탬프 기록"

# ── verify: linux 경로 ──────────────────────────────────
OUT="$("$REPO_DIR/verify.sh" 2>&1)"
assert_contains "$OUT" "패치됨" "verify [2] 패치됨"
assert_not_contains "$OUT" "LaunchAgent" "verify가 linux에선 systemd 라벨 사용"
assert_contains "$OUT" "최신" "verify [6] 버전 최신"

# ── 멱등 업데이트 ───────────────────────────────────────
SETTINGS_BEFORE="$(cat "$SETTINGS")"
"$REPO_DIR/install.sh" --update >/dev/null 2>&1
assert_eq "$SETTINGS_BEFORE" "$(cat "$SETTINGS")" "linux 업데이트 멱등"

# ── 제거 ────────────────────────────────────────────────
OUT="$("$REPO_DIR/uninstall.sh" 2>&1)"; RC=$?
assert_eq "0" "$RC" "linux uninstall 정상 종료"
assert_file_absent "$UNIT_DIR/spinner-patch.path" "systemd unit 제거"
assert_contains "$(cat "$SYSTEMCTL_LOG")" "disable" "systemctl disable 호출"
assert_eq "0" "$(count_ours)" "hook 전량 제거"

report
