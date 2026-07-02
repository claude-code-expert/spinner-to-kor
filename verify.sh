#!/usr/bin/env bash
# Claude Code 한국어 스피너 — 설치 상태 점검.
#
# 6개 항목을 확인하고 각각에 ✓ / ✗ 마크와 함께 출력한다.
#   1. 활성 바이너리 경로
#   2. 활성 바이너리의 영문 verb 잔존 수 (0이면 패치됨)
#   3. 자동 재패치 (LaunchAgent / systemd) 상태
#   4. settings.json 에 한국어 hook 존재
#   5. 최근 패치 로그
#   6. 설치본 버전 == repo 버전
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 미패치 판정 단일 소스 — repo 사본 우선, 없으면 설치본 폴백 (FR-07)
PY_PATCHER="$REPO_DIR/src/patch-spinner-verbs.py"
[[ -f "$PY_PATCHER" ]] || PY_PATCHER="$HOME/.claude/scripts/patch-spinner-verbs.py"
# 플랫폼 추상화 — repo 사본 우선, 없으면 설치본 폴백
PLATFORM_SH="$REPO_DIR/src/platform.sh"
[[ -f "$PLATFORM_SH" ]] || PLATFORM_SH="$HOME/.claude/scripts/platform.sh"
# shellcheck source=src/platform.sh
source "$PLATFORM_SH"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
ok()    { printf "  \033[32m✓\033[0m %s\n" "$*"; }
ng()    { printf "  \033[31m✗\033[0m %s\n" "$*"; }
info()  { printf "    %s\n" "$*"; }

bold "Claude Code 한국어 스피너 — 설치 상태"
echo

# 1. 활성 바이너리
bold "[1] 활성 바이너리"
BIN="$(readlink -f "$(command -v claude)" 2>/dev/null || true)"
if [[ -n "$BIN" && -f "$BIN" ]]; then
  ok "$BIN"
else
  ng "claude 명령을 PATH에서 찾을 수 없음"
fi

# 2. 영문 verb 잔존 — py --check 위임 (다중 sentinel, BUG-01/FR-07)
bold "[2] 영문 verb 잔존 (목표: 0)"
if [[ -n "$BIN" && -f "$BIN" ]]; then
  EN_COUNT="$(python3 "$PY_PATCHER" --check "$BIN" 2>/dev/null)" || EN_COUNT=""
  if [[ "$EN_COUNT" == "0" ]]; then
    ok "패치됨 (영문 sentinel 0건)"
  elif [[ -z "$EN_COUNT" ]]; then
    ng "판정 실패 — patch-spinner-verbs.py 를 찾지 못했거나 실행 오류"
    info "재설치: ./install.sh"
  else
    ng "미패치 — 영문 sentinel $EN_COUNT 건 잔존"
    info "수동 패치: ~/.claude/scripts/patch-spinner-verbs.sh"
  fi
fi

# 3. 자동 재패치 (macOS: LaunchAgent / Linux·WSL: systemd path unit)
PLATFORM="$(spinner_detect_platform)"
bold "[3] 자동 재패치 ($PLATFORM)"
if [[ "$(spinner_autopatch_loaded)" == "1" ]]; then
  ok "활성화됨"
else
  ng "비활성"
  if [[ "$PLATFORM" == "darwin" ]]; then
    info "재로드: launchctl load -w ~/Library/LaunchAgents/dev.claude-spinner-patch.plist"
  else
    info "재활성: systemctl --user enable --now spinner-patch.path"
  fi
fi

# 4. settings.json hooks
bold "[4] settings.json 한국어 hook"
SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
  HOOK_COUNT="$(python3 -c "
import json,sys
s=json.load(open('$SETTINGS'))
pre=s.get('hooks',{}).get('PreToolUse',[])
KO=('파일 읽는 중','쉘 명령 실행 중','코드 검색 중','MCP 도구 호출 중')
n=sum(1 for h in pre if isinstance(h,dict) for sub in h.get('hooks',[]) if isinstance(sub,dict) and sub.get('statusMessage') in KO)
print(n)
" 2>/dev/null || echo 0)"
  if [[ "$HOOK_COUNT" -ge 4 ]]; then
    ok "한국어 statusMessage hook 검출"
  else
    ng "한국어 hook 미설치"
    info "재설치: ./install.sh"
  fi
else
  ng "$SETTINGS 없음"
fi

# 5. 패치 로그
bold "[5] 최근 패치 로그 (마지막 5줄)"
LOG="$HOME/.claude/logs/spinner-patch.log"
if [[ -f "$LOG" ]]; then
  tail -5 "$LOG" | sed 's/^/    /'
else
  info "(로그 없음 — LaunchAgent가 한 번도 트리거되지 않음)"
fi

# 6. 설치본 버전
bold "[6] 설치본 버전"
STAMP="$HOME/.claude/scripts/.spinner-to-kor-version"
REPO_VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo "")"
INSTALLED_VERSION="$(cat "$STAMP" 2>/dev/null || echo "")"
if [[ -z "$REPO_VERSION" ]]; then
  info "(repo VERSION 파일 없음 — repo 밖에서 실행됨, 비교 생략)"
elif [[ -z "$INSTALLED_VERSION" ]]; then
  ng "버전 스탬프 없음 — 미설치 또는 구버전 설치본"
  info "업데이트: ./install.sh --update (기존 설치·사용자 설정 무간섭)"
elif [[ "$INSTALLED_VERSION" == "$REPO_VERSION" ]]; then
  ok "최신 ($INSTALLED_VERSION)"
else
  ng "구버전 설치본 ($INSTALLED_VERSION ≠ repo $REPO_VERSION)"
  info "업데이트: ./install.sh --update"
fi
