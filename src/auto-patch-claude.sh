#!/usr/bin/env bash
# LaunchAgent용 자동 패치 헬퍼.
#
# ~/.local/share/claude/versions/ 디렉터리를 스캔해, 영문 spinner verb가
# 잔존하는 모든 바이너리에 대해 patch-spinner-verbs.py를 실행한다.
# 이미 패치된 파일은 즉시 skip (idempotent).
#
# 안전 장치:
#   - 쓰기 진행 중 파일(자동 업데이트 다운로드 중)은 mtime 안정화 검사로
#     연기한다 — 다음 FSEvents 트리거가 다시 잡는다. (BUG-04)
#   - 백업·서명 실패 복구는 patch-spinner-verbs.py 한 곳이 책임진다. (BUG-05)
#   - 미패치 판정은 py --check(다중 sentinel)에 위임한다. (FR-07)
#
# 환경변수:
#   SPINNER_PATCH_SETTLE_SECS  mtime 안정화 대기 초 (기본 2)
#
# 트리거: ~/Library/LaunchAgents/dev.claude-spinner-patch.plist
#         (WatchPaths로 versions/ 디렉터리 변경 시 자동 실행)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/patch-spinner-verbs.py"
DETECT_SCRIPT="$SCRIPT_DIR/detect-verbs.py"
VERSIONS_DIR="$HOME/.local/share/claude/versions"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/spinner-patch.log"
SETTLE_SECS="${SPINNER_PATCH_SETTLE_SECS:-2}"

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

if [[ ! -d "$VERSIONS_DIR" ]]; then
  log "versions 디렉터리 없음: $VERSIONS_DIR — skip"
  exit 0
fi

if [[ ! -f "$PY_SCRIPT" ]]; then
  log "patch 스크립트 없음: $PY_SCRIPT"
  exit 2
fi

log "스캔 시작: $VERSIONS_DIR"

patched=0
skipped=0
deferred=0
errors=0

for bin in "$VERSIONS_DIR"/*; do
  # 바이너리 파일만 (백업·임시·디렉터리 제외)
  [[ -f "$bin" ]] || continue
  case "$bin" in
    *.bak.*) continue ;;
    *.tmp)   continue ;;
  esac

  # 쓰기 안정화 — 최근 10초 내 변경된 파일만 대기·재확인 (BUG-04)
  # mtime은 python으로 조회 (macOS `stat -f` / GNU `stat -c` 분기 회피, 플랫폼 중립)
  now="$(date +%s)"
  mtime="$(python3 -c "import os,sys;print(int(os.path.getmtime(sys.argv[1])))" "$bin" 2>/dev/null || echo 0)"
  if (( now - mtime < 10 )); then
    sleep "$SETTLE_SECS"
    mtime2="$(python3 -c "import os,sys;print(int(os.path.getmtime(sys.argv[1])))" "$bin" 2>/dev/null || echo -1)"
    if [[ "$mtime" != "$mtime2" ]]; then
      log "쓰기 진행 중 — 연기: $(basename "$bin") (다음 트리거에서 재시도)"
      deferred=$((deferred + 1))
      continue
    fi
  fi

  # 미패치 검사 — 다중 sentinel (py --check 는 성공 시에만 숫자 출력)
  en_count="$(python3 "$PY_SCRIPT" --check "$bin" 2>>"$LOG_FILE")" || en_count=""
  if [[ "$en_count" == "0" ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  if [[ -z "$en_count" ]]; then
    log "검사 실패 — 연기: $(basename "$bin")"
    errors=$((errors + 1))
    continue
  fi

  log "패치 시도: $(basename "$bin") (영문 sentinel ${en_count}건)"

  # 백업 생성·서명 실패 시 원본 복구는 py가 수행한다
  if python3 "$PY_SCRIPT" "$bin" >> "$LOG_FILE" 2>&1; then
    patched=$((patched + 1))
    log "패치 성공: $(basename "$bin")"
    # 새 바이너리에 미매핑 신규 verb가 있으면 조기 경보 (FR-31)
    if [[ -f "$DETECT_SCRIPT" ]]; then
      unmapped="$(python3 "$DETECT_SCRIPT" --count "$bin" 2>>"$LOG_FILE")" || unmapped=""
      if [[ -n "$unmapped" && "$unmapped" != "0" ]]; then
        log "WARN unmapped=$unmapped — 새 verb 감지: 'python3 $DETECT_SCRIPT $bin' 으로 확인 후 매핑 갱신"
      fi
    fi
  else
    errors=$((errors + 1))
    log "패치 실패: $(basename "$bin") — py가 원본 복구 수행함, 로그 확인"
  fi
done

log "완료: patched=$patched skipped=$skipped deferred=$deferred errors=$errors"
exit 0
