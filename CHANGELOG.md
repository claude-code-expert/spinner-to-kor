# Changelog

## 0.0.1 — 2026-07-02 (첫 공개 릴리스)

첫 배포. 아래 기능 전체를 포함한다:

- **3-레이어 한국어 스피너**: PreToolUse hook 20개(도구별 한국어 라벨) + 바이너리 verb 178개 한국어 치환(byte 불변식 + ad-hoc 재서명) + 자동 재패치.
- **무간섭 설치/업데이트/제거**: 사용자 `settings.json` hook 보존, 구버전 in-place 업그레이드, 실패 시 무변경. 바이너리 백업·복원.
- **프로젝트 스코프**(`--project`) + **단일 CLI**(`spinner-to-kor <install|uninstall|update|verify|patch|status>`).
- **매핑 확장**: 신규 verb 자동 감지·경보, 커스텀 오버레이(`~/.claude/spinner-map.json`), semantic/witty 스타일.
- **플랫폼**: macOS(LaunchAgent) · Linux/WSL(systemd path unit) · GitHub Actions CI(ubuntu+macos).
- **원격 한 줄 설치**: `curl … bootstrap.sh | bash`, 자립 update/uninstall(스냅샷 + PATH 진입점).
- 테스트 하네스 8스위트(fixture 기반, 실기 격리), shellcheck 클린.

세부 구현 이력은 아래 "개발 마일스톤" 및 git 이력 참고.

---

## 개발 마일스톤 (내부 이력 — 정식 릴리스 아님)

> 아래 버전 번호(1.0.0~2.1.0)는 개발 중 마일스톤 표기였으며 배포되지 않았다. 첫 정식 배포는 위 0.0.1.

## 2.1.0 (M5) — 원격 배포

- **한 줄 설치** (`bootstrap.sh`): `curl -fsSL .../bootstrap.sh | bash` — GitHub 최신 release tarball 을 받아 설치. Node/npm 의존 없음(순수 bash+python3). `SPINNER_REPO`·`SPINNER_SOURCE_TARBALL` env 로 포크·오프라인 지원.
- **자립 update/uninstall**: install 시 배포 스냅샷을 `~/.claude/spinner-to-kor/` 에 보관하고 `~/.local/bin/spinner-to-kor` PATH 진입점을 심는다. `spinner-to-kor update` = 부트스트랩 재실행(최신 release, 무간섭), `uninstall` = 스냅샷·진입점까지 정리. curl 설치 후 소스 디렉터리 없이도 전 명령 동작.
- CLI 진입점이 심볼릭 링크를 해석해 실제 스크립트 위치를 REPO_DIR로 잡는다 (`~/.local/bin` 심볼릭 대응).
- 테스트: `test_bootstrap.sh` 18건 — 로컬 tarball 주입으로 네트워크 없이 설치→update→uninstall 전체 흐름 검증.

## 2.0.0 — 2026-07-02 (M4 플랫폼 확장)

- **Linux/WSL 지원** (FR-41/42): `src/platform.sh` 신설 — 자동 재패치 등록/해제/상태를 OS별로 캡슐화. macOS는 LaunchAgent(기존), Linux·WSL은 systemd path unit(`~/.config/systemd/user/spinner-patch.path`). 재서명(codesign)은 non-darwin에서 no-op (ELF는 서명 불요). install/uninstall/verify가 공통 라이브러리 소싱.
- systemctl 부재(systemd 없는 WSL1 등) 시 unit 파일만 배치하고 `wsl.conf` 안내 — 실패해도 수동 패치 경로 유지.
- auto-patch mtime 조회를 `stat -f`(BSD)/`stat -c`(GNU) 분기 대신 python으로 통일 (플랫폼 중립).
- **CI** (NFR-08): GitHub Actions ubuntu+macos 매트릭스 — shellcheck + fixture 테스트. launchctl·systemctl·codesign mock으로 실기 없이 양 플랫폼 경로 검증.
- 테스트 하네스: 크로스플랫폼 검증용 `SPINNER_PLATFORM` env 도입, `test_platform.sh`(16)·`test_linux_e2e.sh`(16) 추가. 총 160+ assertion.

BREAKING CHANGE: install.sh의 "macOS 전용" 사전 게이트 제거 — 이제 Linux/WSL에서도 설치 진행. macOS 사용자 동작은 불변.

## 1.2.0 — 2026-07-02 (M3 매핑 확장)

- **신규 verb 자동 감지** (FR-31): `src/detect-verbs.py` — 두 embed 패턴(JSON+NUL 경계) 교집합 gerund만 후보로 삼아 오탐 차단. 자동 재패치 성공 시 함께 실행되어 미매핑 발견 시 로그에 `WARN unmapped=N`.
- **커스텀 매핑 오버레이** (FR-32): `~/.claude/spinner-map.json` — `pools`(풀 교체)·`overrides`(개별 verb 고정, 자동 space 패딩). byte 불변식 위반·오타·깨진 JSON은 패치 거부 + 바이너리 무변경. `SPINNER_MAP_FILE` 로 경로 재지정.
- **스타일 프리셋** (FR-33): `--style semantic|witty` (env `SPINNER_STYLE`) — 2026-06-18 위트 1:1 매핑 178개를 `WITTY_RAW` 로 데이터화, 패딩 자동 계산, 전수 byte 검증.
- patch-spinner-verbs.py CLI를 argparse로 정리 (`--check` 계약 불변).

## 1.1.0 — 2026-07-02 (M2 설치 UX)

- **프로젝트 스코프 설치** (FR-14): `install.sh --project [DIR]` / `uninstall.sh --project [DIR]` — 해당 프로젝트 `.claude/settings.json`에 Layer A(hook)만 무간섭 머지/제거. DIR 생략 시 현재 디렉터리. 전역 ↔ 프로젝트 상호 무간섭 (E2E 20건).
- **단일 CLI 진입점** (FR-16): `./spinner-to-kor <install|uninstall|update|verify|patch|status|help>` — 기존 스크립트로 위임하는 얇은 디스패처, 기존 진입점 하위 호환 유지. `status`는 버전·패치 상태·LaunchAgent 한눈 요약.
- install/uninstall 알 수 없는 옵션은 이제 즉시 거부 (오타 침묵 무시 방지).

## 1.0.0 — 2026-07-02 (M1 안정화)

### 핵심: 무간섭 in-place 업데이트 (FR-17)

- 기설치 사용자는 재설치·삭제 없이 `./install.sh --update` 한 번으로 새 버전 반영.
- `src/merge-hooks.py` 신설 — settings.json 머지/제거 단일 소스:
  - 우리 hook 식별 마커 도입: `command: "true # spinner-to-kor"` (스키마 비표준 키 없이).
  - 동일 matcher의 **사용자 hook을 절대 교체하지 않음** — 별도 entry로 공존 (BUG-02).
  - 마커 없는 구버전 설치본은 레거시 라벨로 인식해 in-place 업그레이드 — 중복 0.
  - 깨진 JSON·비정상 구조 시 무변경 중단, 쓰기는 tmp + atomic replace.
  - uninstall도 동일 로직 사용 — 라벨 목록 수동 동기화 제거 (BUG-06).
- `VERSION` 파일 + 설치 스탬프(`~/.claude/scripts/.spinner-to-kor-version`) + `verify.sh` [6] 버전 항목.

### 버그 수정

- **BUG-01**: `verify.sh`가 패치 완료 바이너리를 "미패치 0\n0건"으로 오판 (`set -o pipefail` + `grep -c || echo 0` 이중 출력). 판정을 `patch-spinner-verbs.py --check`로 위임.
- **BUG-03**: 바이너리 자동 탐지가 백업(`*.bak.<ts>`)·`.tmp`·숨김 파일을 활성 바이너리로 오탐할 수 있던 필터 강화.
- **BUG-04**: 자동 업데이트가 파일을 쓰는 도중 FSEvents 트리거 시 skip되던 문제 — mtime 안정화 대기 내장 (`deferred` 로그, `SPINNER_PATCH_SETTLE_SECS`).
- **BUG-05**: 패치 1회당 백업 최대 2개(~205MB×2) 무제한 누적 — 백업 생성을 py 한 곳으로 일원화 + 보존 정책(깨끗한 원본 + 최신만 유지, `prune_backups`).
- 재서명 실패 시 py가 원본을 **자동 복구** — claude 실행 불능 상태 방지 강화 (NFR-04).

### 신뢰성

- 미패치 판정 sentinel 다중화(Pondering·Thinking·Generating) + `--check` CLI로 일원화 (FR-07). 셸 3곳의 `strings | grep` 중복 제거.
- 테스트 하네스: fixture 바이너리 생성기 + Python 단위 34건 + 셸 회귀/E2E 38건 (`tests/run.sh`). launchctl·codesign mock, 샌드박스 HOME으로 실기 완전 격리.

### 문서

- README 폴더 구조 실제화, 무간섭 업데이트 보장 절 추가, hardcoded plist → `reference/` 이동 (DOC-01).
- ARCHITECTURE에 무간섭 머지·백업 보존 정책 절 추가, TROUBLESHOOTING 갱신.
- `docs/` 신설: PRD · TRD · REQUIREMENTS · MILESTONES.

## 0.9 — 2026-06-21 (M0 기준선)

- 3-레이어 시스템: PreToolUse hook 20 matcher + 바이너리 verb 178개 치환 + LaunchAgent 자동 재패치.
- install / uninstall(--restore-bin) / verify 스크립트, 배포 템플릿화.
- 2026-06-19 의미 통일 개정: 위트 1:1 번역 → "응답 생성 중" 의미 수렴 풀 매핑.
