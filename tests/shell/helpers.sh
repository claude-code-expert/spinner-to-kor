#!/usr/bin/env bash
# 셸 테스트 공용 헬퍼 — 샌드박스(가짜 HOME/PATH) + assert.
#
# 안전 원칙: 테스트는 실제 시스템을 절대 건드리지 않는다.
#   - HOME을 tmpdir로 위장 → settings.json·scripts·LaunchAgents 전부 샌드박스 안
#   - launchctl·codesign을 가짜 실행파일로 대체 (PATH 선행)
#   - claude 바이너리는 tests/make-fixture.py 가짜 파일
set -uo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HELPER_DIR/../.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1" >&2; }

assert_eq() {  # want got msg
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want=[$1] got=[$2])"; fi
}
assert_contains() {  # haystack needle msg
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (missing: $2)"; fi
}
assert_not_contains() {  # haystack needle msg
  if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3 (unexpected: $2)"; fi
}
assert_file_exists() { if [[ -e "$1" ]]; then pass "$2"; else fail "$2 (없음: $1)"; fi }
assert_file_absent() { if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2 (잔존: $1)"; fi }

setup_sandbox() {
  SANDBOX="$(mktemp -d /tmp/spinner-shtest-XXXXXX)"
  export HOME="$SANDBOX/home"
  FAKEBIN="$SANDBOX/fakebin"
  VERSIONS="$HOME/.local/share/claude/versions"
  SETTINGS="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.local/bin" "$VERSIONS" "$HOME/.claude" \
           "$HOME/Library/LaunchAgents" "$FAKEBIN"
  export PATH="$FAKEBIN:$HOME/.local/bin:$PATH"
  export LAUNCHCTL_LOG="$SANDBOX/launchctl.log"

  cat > "$FAKEBIN/launchctl" <<'EOF'
#!/usr/bin/env bash
echo "launchctl $*" >> "${LAUNCHCTL_LOG:-/dev/null}"
if [[ "${1:-}" == "list" ]]; then printf -- '-\t0\tdev.claude-spinner-patch\n'; fi
exit 0
EOF
  printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/codesign"
  chmod +x "$FAKEBIN/launchctl" "$FAKEBIN/codesign"

  python3 "$REPO_DIR/tests/make-fixture.py" "$VERSIONS/2.1.170" >/dev/null
  ln -s "$VERSIONS/2.1.170" "$HOME/.local/bin/claude"
}

teardown_sandbox() { rm -rf "${SANDBOX:?}"; }

# 설치 스크립트만 샌드박스 scripts 디렉터리로 복사 (install.sh 1단계 모사)
deploy_scripts() {
  mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/logs"
  local f
  for f in patch-spinner-verbs.py patch-spinner-verbs.sh auto-patch-claude.sh merge-hooks.py detect-verbs.py; do
    [[ -f "$REPO_DIR/src/$f" ]] && cp -p "$REPO_DIR/src/$f" "$HOME/.claude/scripts/$f"
  done
  chmod +x "$HOME/.claude/scripts/"* 2>/dev/null || true
}

# settings.json 안 우리(spinner-to-kor 마커) entry 수
count_ours() {
  python3 - "$SETTINGS" <<'PY'
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception:
    print(-1); raise SystemExit
pre = s.get("hooks", {}).get("PreToolUse", [])
print(sum(1 for e in pre if isinstance(e, dict)
          and any("spinner-to-kor" in str(h.get("command", ""))
                  for h in e.get("hooks", []) if isinstance(h, dict))))
PY
}

# 바이너리 내 영문 sentinel 수 (py --check 위임)
en_count() {
  python3 "$REPO_DIR/src/patch-spinner-verbs.py" --check "$1"
}

report() {
  echo
  echo "결과: PASS=$PASS FAIL=$FAIL"
  [[ "$FAIL" == "0" ]]
}
