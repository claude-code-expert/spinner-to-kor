# Changelog

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
