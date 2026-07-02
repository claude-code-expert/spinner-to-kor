#!/usr/bin/env bash
# Claude Code 한국어 스피너 — 원클릭 설치·업데이트.
#
# 사용:
#   ./install.sh                  # 전역 설치 (기설치 상태면 자동으로 무간섭 업데이트)
#   ./install.sh --update         # 명시적 업데이트 (동작 동일, 버전 리포트 출력)
#   ./install.sh --no-patch       # 바이너리 패치 건너뜀 (hooks·LaunchAgent만)
#   ./install.sh --project [DIR]  # 프로젝트 스코프 — DIR/.claude/settings.json 에
#                                 #   Layer A(hook)만 머지 (기본 DIR=$PWD).
#                                 #   Layer B/C는 머신 전역 자원이라 건드리지 않음
#
# 동작 (전 단계 멱등 — 기존 설치·사용자 설정 무간섭):
#   1) ~/.claude/scripts/ 에 패치·머지 스크립트 4개 복사
#   2) ~/.claude/settings.json 에 한국어 hook 무간섭 머지 (src/merge-hooks.py —
#      사용자 hook 보존, 구버전 설치본 in-place 업그레이드)
#   3) LaunchAgent plist 템플릿을 사용자 환경으로 치환 → ~/Library/LaunchAgents/ 등록
#   4) 현재 활성 바이너리 즉시 패치 (영문 verb → 한국어)
#   5) 버전 스탬프 기록 + verify.sh 실행
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/src"
TEMPLATES_DIR="$REPO_DIR/templates"
SNIPPETS_DIR="$REPO_DIR/snippets"

SCRIPTS_DEST="$HOME/.claude/scripts"
LOGS_DEST="$HOME/.claude/logs"
SETTINGS="$HOME/.claude/settings.json"
PLIST_DEST="$HOME/Library/LaunchAgents/dev.claude-spinner-patch.plist"
STAMP="$SCRIPTS_DEST/.spinner-to-kor-version"
REPO_VERSION="$(cat "$REPO_DIR/VERSION")"

PATCH_BINARY=1
PROJECT_MODE=0
PROJECT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-patch) PATCH_BINARY=0 ;;
    --update)   : ;;  # 설치와 동일 경로 — 아래 버전 리포트로만 구분
    --project)
      PROJECT_MODE=1
      if [[ $# -ge 2 && "$2" != --* ]]; then
        PROJECT_DIR="$2"
        shift
      fi
      ;;
    *)
      printf "\033[31m알 수 없는 옵션: %s\033[0m\n" "$1" >&2
      exit 2
      ;;
  esac
  shift
done

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*" >&2; }
yel()   { printf "\033[33m%s\033[0m\n" "$*"; }

# ───────────────────────────────────────────────────────────
# 프로젝트 스코프 — Layer A(hook)만, 전역 자산 무접촉 (FR-14)
# ───────────────────────────────────────────────────────────
if [[ "$PROJECT_MODE" == "1" ]]; then
  PROJECT_DIR="${PROJECT_DIR:-$PWD}"
  bold "== 프로젝트 스코프 설치 — Layer A(hook)만 =="

  if ! command -v python3 >/dev/null 2>&1; then
    red "python3 가 필요합니다."
    exit 2
  fi
  if [[ ! -d "$PROJECT_DIR" ]]; then
    red "프로젝트 디렉터리 없음: $PROJECT_DIR"
    exit 2
  fi

  PROJ_SETTINGS="$PROJECT_DIR/.claude/settings.json"
  if [[ -f "$PROJ_SETTINGS" ]]; then
    TS="$(date +%Y%m%d-%H%M%S)"
    cp -p "$PROJ_SETTINGS" "${PROJ_SETTINGS}.bak.${TS}"
    yel "백업: ${PROJ_SETTINGS}.bak.${TS}"
  fi

  if ! python3 "$SRC_DIR/merge-hooks.py" install \
        --settings "$PROJ_SETTINGS" --snippet "$SNIPPETS_DIR/settings-hooks.json"; then
    red "프로젝트 settings.json 머지 실패 — 파일은 변경되지 않았습니다."
    exit 2
  fi
  green "✓ 프로젝트 hook 설치 완료: $PROJ_SETTINGS"

  if [[ -f "$STAMP" ]]; then
    green "✓ 전역 레이어(B: 바이너리 verb, C: 자동 재패치)는 이미 설치되어 있습니다."
  else
    yel "전역 레이어(B/C) 미설치 — 스피너 verb 한국어화는 './install.sh' 전역 설치가 필요합니다."
    yel "  (프로젝트 설치는 도구별 한국어 라벨(Layer A)만 제공합니다)"
  fi

  echo
  bold "프로젝트 설치 완료. 이 프로젝트에서 새 claude 세션을 열어 확인하세요."
  exit 0
fi

# ───────────────────────────────────────────────────────────
# 사전 점검
# ───────────────────────────────────────────────────────────
bold "== 사전 점검 =="

if [[ "$(uname -s)" != "Darwin" ]]; then
  red "macOS 전용입니다. (LaunchAgent + Mach-O 코드서명 의존)"
  exit 2
fi

if ! command -v claude >/dev/null 2>&1; then
  red "claude 명령어를 PATH에서 찾을 수 없습니다. Claude Code를 먼저 설치하세요."
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  red "python3 가 필요합니다. 'xcode-select --install' 또는 Homebrew로 설치하세요."
  exit 2
fi

# Homebrew prefix 자동 감지 (LaunchAgent plist 안 PATH 환경변수용)
if [[ -x /opt/homebrew/bin/brew ]]; then
  HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -x /usr/local/bin/brew ]]; then
  HOMEBREW_PREFIX="/usr/local"
else
  HOMEBREW_PREFIX="/usr/local"
  yel "Homebrew를 찾지 못해 prefix를 /usr/local 으로 가정합니다."
fi

green "✓ macOS, claude, python3, Homebrew prefix=$HOMEBREW_PREFIX"

# 기존 설치 감지 → 무간섭 업데이트 모드 안내
PREV_VERSION="$(cat "$STAMP" 2>/dev/null || echo "")"
if [[ -n "$PREV_VERSION" ]]; then
  bold "== 기존 설치 감지 ($PREV_VERSION) → 무간섭 업데이트: $PREV_VERSION → $REPO_VERSION =="
elif [[ -d "$SCRIPTS_DEST" && -f "$SCRIPTS_DEST/patch-spinner-verbs.py" ]]; then
  bold "== 구버전 설치 감지 (버전 스탬프 없음) → 무간섭 업데이트: (구버전) → $REPO_VERSION =="
fi

# ───────────────────────────────────────────────────────────
# 1. 스크립트 배치
# ───────────────────────────────────────────────────────────
bold "== 1) ~/.claude/scripts/ 에 패치 스크립트 배치 =="
mkdir -p "$SCRIPTS_DEST" "$LOGS_DEST"
for f in patch-spinner-verbs.py patch-spinner-verbs.sh auto-patch-claude.sh merge-hooks.py; do
  cp -p "$SRC_DIR/$f" "$SCRIPTS_DEST/$f"
  chmod +x "$SCRIPTS_DEST/$f"
done
green "✓ 4개 스크립트 복사 완료"

# ───────────────────────────────────────────────────────────
# 2. settings.json hooks 머지
# ───────────────────────────────────────────────────────────
bold "== 2) ~/.claude/settings.json 에 한국어 hook 머지 =="
TS="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$SETTINGS" ]]; then
  cp -p "$SETTINGS" "${SETTINGS}.bak.${TS}"
  yel "백업: ${SETTINGS}.bak.${TS}"
fi

# 무간섭 머지 — 사용자 hook 보존·레거시 업그레이드·실패 시 무변경 (BUG-02/06)
if ! python3 "$SRC_DIR/merge-hooks.py" install \
      --settings "$SETTINGS" --snippet "$SNIPPETS_DIR/settings-hooks.json"; then
  red "settings.json 머지 실패 — 파일은 변경되지 않았습니다. JSON 문법을 확인하세요:"
  red "  python3 -m json.tool \"$SETTINGS\""
  exit 2
fi
green "✓ hooks.PreToolUse 무간섭 머지 완료"

# ───────────────────────────────────────────────────────────
# 3. LaunchAgent 등록
# ───────────────────────────────────────────────────────────
bold "== 3) LaunchAgent 등록 (FSEvents 기반 자동 재패치) =="
mkdir -p "$(dirname "$PLIST_DEST")"

# 구버전 계정별 라벨(dev.<username>.claude-spinner-patch) 마이그레이션 —
# 새 라벨과 중복 로드되어 같은 디렉터리를 두 에이전트가 감시하는 것 방지 (FR-17)
for legacy in "$HOME/Library/LaunchAgents"/dev.*.claude-spinner-patch.plist; do
  [[ -f "$legacy" ]] || continue
  [[ "$legacy" == "$PLIST_DEST" ]] && continue
  launchctl unload "$legacy" 2>/dev/null || true
  rm -f "$legacy"
  yel "구버전 LaunchAgent 마이그레이션(제거): $(basename "$legacy")"
done
sed -e "s|{{HOME}}|$HOME|g" \
    -e "s|{{HOMEBREW_PREFIX}}|$HOMEBREW_PREFIX|g" \
    "$TEMPLATES_DIR/LaunchAgent.plist.template" > "$PLIST_DEST"
green "✓ plist 생성: $PLIST_DEST"

# 이미 로드돼 있으면 unload 후 재로드 (멱등)
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load -w "$PLIST_DEST"
# load 직후 list 반영이 지연될 수 있어 잠시 재시도 (거짓 실패 방지)
LOADED=0
for _ in 1 2 3; do
  if launchctl list | grep -q dev.claude-spinner-patch; then
    LOADED=1
    break
  fi
  sleep 1
done
if [[ "$LOADED" == "1" ]]; then
  green "✓ LaunchAgent 로드 완료"
else
  red "LaunchAgent 로드 실패. 'launchctl load -w \"$PLIST_DEST\"' 수동 실행 필요"
fi

# ───────────────────────────────────────────────────────────
# 4. 현재 활성 바이너리 즉시 패치
# ───────────────────────────────────────────────────────────
if [[ "$PATCH_BINARY" == "1" ]]; then
  bold "== 4) 현재 활성 바이너리 즉시 패치 =="
  if "$SCRIPTS_DEST/auto-patch-claude.sh"; then
    green "✓ auto-patch-claude.sh 실행 완료 (로그: $LOGS_DEST/spinner-patch.log)"
  else
    yel "auto-patch-claude.sh가 일부 바이너리를 처리하지 못했을 수 있습니다."
    yel "  수동 패치: $SCRIPTS_DEST/patch-spinner-verbs.sh"
  fi
else
  yel "== 4) --no-patch 지정 → 바이너리 패치 건너뜀 =="
fi

# ───────────────────────────────────────────────────────────
# 5. 버전 스탬프 + 검증
# ───────────────────────────────────────────────────────────
echo "$REPO_VERSION" > "$STAMP"
if [[ -n "$PREV_VERSION" ]]; then
  green "✓ 업데이트 완료: $PREV_VERSION → $REPO_VERSION"
else
  green "✓ 버전 스탬프 기록: $REPO_VERSION"
fi

echo
bold "== 5) 검증 =="
if [[ -x "$REPO_DIR/verify.sh" ]]; then
  "$REPO_DIR/verify.sh"
fi

echo
bold "설치 완료. 새 터미널에서 'claude' 를 실행해 스피너가 한국어인지 확인하세요."
echo "  (현재 실행 중인 claude 프로세스는 메모리에 옛 바이너리를 들고 있어 자동 반영되지 않습니다)"
