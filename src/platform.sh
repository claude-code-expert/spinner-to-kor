#!/usr/bin/env bash
# 플랫폼 추상화 — 자동 재패치 등록/해제/상태를 OS별로 캡슐화 (FR-41/42).
#
# install.sh·uninstall.sh·verify.sh 가 소싱한다. 감시 메커니즘만 OS별로 다르고
# (macOS: LaunchAgent+FSEvents / Linux·WSL: systemd path unit) 패치 본체는 공통.
#
# 테스트는 SPINNER_PLATFORM env 로 플랫폼을 강제해 실기 없이 양 경로를 검증한다.

# darwin | linux
spinner_detect_platform() {
  if [[ -n "${SPINNER_PLATFORM:-}" ]]; then
    echo "$SPINNER_PLATFORM"
    return
  fi
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    *)      echo linux ;;
  esac
}

# 자동 재패치 등록. 인자: <scripts_dir> <templates_dir>
# 반환: 0 성공. 로드 실패는 경고만 하고 0 (설치 자체는 계속).
spinner_register_autopatch() {
  local scripts_dir="$1" templates_dir="$2"
  case "$(spinner_detect_platform)" in
    darwin) _spinner_register_darwin "$scripts_dir" "$templates_dir" ;;
    linux)  _spinner_register_linux  "$scripts_dir" "$templates_dir" ;;
  esac
}

spinner_unregister_autopatch() {
  case "$(spinner_detect_platform)" in
    darwin) _spinner_unregister_darwin ;;
    linux)  _spinner_unregister_linux ;;
  esac
}

# 로드 상태: 1=활성, 0=비활성
spinner_autopatch_loaded() {
  case "$(spinner_detect_platform)" in
    darwin)
      launchctl list 2>/dev/null | grep -q 'claude-spinner-patch' && echo 1 || echo 0 ;;
    linux)
      systemctl --user is-active spinner-patch.path >/dev/null 2>&1 && echo 1 || echo 0 ;;
  esac
}

# ── darwin ──────────────────────────────────────────────
_spinner_darwin_plist() { echo "$HOME/Library/LaunchAgents/dev.claude-spinner-patch.plist"; }

_spinner_register_darwin() {
  local scripts_dir="$1" templates_dir="$2"
  local plist; plist="$(_spinner_darwin_plist)"
  mkdir -p "$(dirname "$plist")"

  # 구버전 계정별 라벨(dev.<username>.claude-spinner-patch) 마이그레이션 (FR-17)
  local legacy
  for legacy in "$HOME/Library/LaunchAgents"/dev.*.claude-spinner-patch.plist; do
    [[ -f "$legacy" ]] || continue
    [[ "$legacy" == "$plist" ]] && continue
    launchctl unload "$legacy" 2>/dev/null || true
    rm -f "$legacy"
    printf "구버전 LaunchAgent 마이그레이션(제거): %s\n" "$(basename "$legacy")" >&2
  done

  local hb="${HOMEBREW_PREFIX:-/usr/local}"
  sed -e "s|{{HOME}}|$HOME|g" -e "s|{{HOMEBREW_PREFIX}}|$hb|g" \
      "$templates_dir/LaunchAgent.plist.template" > "$plist"

  launchctl unload "$plist" 2>/dev/null || true
  launchctl load -w "$plist"
  for _ in 1 2 3; do
    [[ "$(spinner_autopatch_loaded)" == "1" ]] && return 0
    sleep 1
  done
  printf "LaunchAgent 로드 실패. 'launchctl load -w \"%s\"' 수동 실행 필요\n" "$plist" >&2
  return 0
}

_spinner_unregister_darwin() {
  # 신 라벨(dev.claude-spinner-patch)·구 계정별 라벨(dev.<user>.claude-spinner-patch) 모두
  local p
  for p in "$HOME/Library/LaunchAgents"/dev.claude-spinner-patch.plist \
           "$HOME/Library/LaunchAgents"/dev.*.claude-spinner-patch.plist; do
    [[ -f "$p" ]] || continue
    launchctl unload "$p" 2>/dev/null || true
    rm -f "$p"
  done
}

# ── linux / WSL ─────────────────────────────────────────
_spinner_linux_unit_dir() { echo "$HOME/.config/systemd/user"; }

_spinner_register_linux() {
  local scripts_dir="$1" templates_dir="$2"
  local unit_dir; unit_dir="$(_spinner_linux_unit_dir)"
  mkdir -p "$unit_dir"

  sed -e "s|{{HOME}}|$HOME|g" -e "s|{{SCRIPTS_DIR}}|$scripts_dir|g" \
      "$templates_dir/systemd-path.template" > "$unit_dir/spinner-patch.path"
  sed -e "s|{{HOME}}|$HOME|g" -e "s|{{SCRIPTS_DIR}}|$scripts_dir|g" \
      "$templates_dir/systemd-service.template" > "$unit_dir/spinner-patch.service"

  # systemctl 부재(예: systemd 없는 WSL1) 시 unit 파일만 두고 안내
  if ! command -v systemctl >/dev/null 2>&1; then
    printf "systemctl 없음 — systemd unit 파일만 배치했습니다. WSL이면 /etc/wsl.conf 에\n" >&2
    printf "  [boot]\\n  systemd=true  후 'wsl --shutdown' 재시작하거나, 수동으로\n" >&2
    printf "  '~/.claude/scripts/auto-patch-claude.sh' 를 주기 실행하세요.\n" >&2
    return 0
  fi
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now spinner-patch.path 2>/dev/null || \
    printf "systemctl enable 실패 — 'systemctl --user enable --now spinner-patch.path' 수동 실행 필요\n" >&2
  return 0
}

_spinner_unregister_linux() {
  local unit_dir; unit_dir="$(_spinner_linux_unit_dir)"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now spinner-patch.path 2>/dev/null || true
  fi
  rm -f "$unit_dir/spinner-patch.path" "$unit_dir/spinner-patch.service"
}
