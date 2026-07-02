# Requirements — Claude Code 한국어 스피너

> 작성일: 2026-07-02 · 상태: 기준선(baseline) v1
> 관련 문서: [PRD](./PRD.md) · [TRD](./TRD.md) · [MILESTONES](./MILESTONES.md)
> 표기: FR=기능 요구, NFR=비기능 요구, BUG=결함, DOC=문서 결함. `[M0]`=구현 완료, `[M1..M4]`=목표 마일스톤.

## 1. 기능 요구사항 (FR)

### 1.1 핵심 변환 기능

| ID | 요구사항 | 수용 기준 | 상태 |
|---|---|---|---|
| FR-01 | 스피너 영문 verb 178개를 "응답 생성 중" 의미의 한국어 라벨로 치환한다 | 패치 후 `strings` 기준 영문 verb 잔존 0건, 한국어 라벨 검출 | [M0] 완료 |
| FR-02 | 도구 호출 시 도구별 한국어 상태 라벨을 표시한다 (PreToolUse 20 matcher) | 새 세션에서 Read→"파일 읽는 중" 등 표시 | [M0] 완료 |
| FR-03 | 치환은 byte 길이 불변식을 강제한다 — 위반 매핑은 실행 거부 | `validate_map()` 불일치 시 exit 2 + 위반 entry 출력 | [M0] 완료 |
| FR-04 | 패치 후 바이너리가 정상 실행된다 (ad-hoc 재서명) | `claude --version` 정상, `codesign -dv`에 `Signature=adhoc` | [M0] 완료 |
| FR-05 | Claude Code 자동 업데이트로 새 바이너리 도착 시 자동 재패치한다 | versions/ 변경 → 로그에 스캔 entry, 새 바이너리 한국어화 | [M0] 완료 |
| FR-06 | 파일 쓰기 중 트리거로 인한 skip을 자동 복구한다 (mtime 안정화 + 연기 후 재시도) | 쓰기 도중 트리거 시뮬레이션에서 연기 → 완료 후 패치 성공 | [M1] **완료** (`deferred` 로그, 회귀 테스트) |
| FR-07 | 미패치 판정 sentinel을 다중화하고 정의를 한 곳으로 일원화한다 | sentinel 1개 소실 시에도 감지 정상, 셸 3곳 중복 제거 | [M1] **완료** (`--check` CLI, sentinel 3종) |

### 1.2 설치·업데이트·제거

| ID | 요구사항 | 수용 기준 | 상태 |
|---|---|---|---|
| FR-10 | 원클릭 전역 설치 (`install.sh`) — 스크립트 배치·hook 머지·LaunchAgent 등록·즉시 패치·검증 | 클린 macOS에서 명령 1개로 5단계 완료, verify 전항목 ✓ | [M0] 완료 |
| FR-11 | 설치는 멱등이다 — 재실행 시 중복 hook·중복 LaunchAgent 없음 | install.sh 2회 실행 후 hook 수·plist 동일 | [M0] 완료 |
| FR-12 | hook 머지 시 사용자 정의 hook을 보존한다 | 동일 matcher의 사용자 hook 존재 상태에서 설치→제거 후 사용자 hook 원형 유지 | [M1] **완료** (merge-hooks.py) |
| FR-13 | 원클릭 제거 (`uninstall.sh`) — LaunchAgent·hook·스크립트 제거, `--restore-bin` 시 바이너리 원본 복원 | 제거 후 verify 전항목 설치 전 상태, `--restore-bin` 후 sha256 원본 일치 | [M0] 완료 |
| FR-14 | 프로젝트 스코프 설치 — `install.sh --project [DIR]`로 해당 프로젝트 `.claude/settings.json`에만 Layer A 적용 | 프로젝트 설치 후 타 프로젝트·전역 설정 무변경, `--project` 제거 대칭 동작 | [M2] **완료** (E2E 20 assertion, 전역↔프로젝트 상호 무간섭 검증) |
| FR-15 | 도구 자체의 버전 스탬프와 업데이트 명령 제공 (`--update`) | 설치본 버전 파일 존재, repo 갱신 후 update 실행 시 재배치+리포트 | [M1] **완료** (M2에서 전방 배치 — FR-17 지원 목적) |
| FR-16 | 단일 CLI 진입점 `spinner-to-kor <subcommand>` (기존 스크립트 하위 호환 유지) | 6개 서브커맨드 동작, 기존 `./install.sh` 등도 계속 동작 | [M2] |
| FR-17 | **무간섭 in-place 업데이트 (핵심)** — 기설치 사용자는 재설치·삭제 없이 새 버전이 반영되고, 사용자 설정·기존 설치 자산에 어떤 간섭도 없다. 구버전(마커 없는) 설치본은 in-place 업그레이드된다 | E2E: 레거시 설치 + 사용자 hook 상태에서 `install.sh --update` → 중복 0·사용자 hook 원형·멱등, 깨진 JSON 시 무변경 중단 | [M1] **완료** (마커 기반 머지 + 레거시 폴백) |

### 1.3 진단·복구

| ID | 요구사항 | 수용 기준 | 상태 |
|---|---|---|---|
| FR-20 | 자가 진단 `verify.sh` — 레이어별 상태를 ✓/✗로 표시 (v1.0: 6항목, 버전 포함) | 각 레이어 고장을 인위 유발 시 해당 항목만 ✗ | [M0] 완료 |
| FR-21 | 진단 결과에 거짓 양성·거짓 음성이 없다 | 패치 완료 상태에서 [2] ✓, 미패치 상태에서 [2] ✗ (회귀 테스트) | [M1] **완료** (BUG-01 수정) |
| FR-22 | 모든 파괴적 작업(바이너리 치환·settings 수정) 전 백업 자동 생성 | 백업 파일 존재 + 타임스탬프 규칙 준수 | [M0] 완료 |
| FR-23 | 백업 보존 정책 — 버전당 "깨끗한 원본 1개 + 최신 1개"만 유지, 중복 백업 생성 제거 | 반복 패치 후 버전당 .bak ≤ 2개, 원본 sha256 보존 | [M1] **완료** (prune_backups, 백업 py 일원화) |

### 1.4 매핑 관리

| ID | 요구사항 | 수용 기준 | 상태 |
|---|---|---|---|
| FR-30 | 매핑은 byte 길이별 풀 + 라운드로빈으로 정의하고 코드 한 곳에서 관리한다 | `EN_VERBS_BY_LENGTH`·`KO_LABEL_POOLS`만 수정하면 전체 반영 | [M0] 완료 |
| FR-31 | 신규 Claude Code 버전의 미매핑 verb를 자동 감지·리포트한다 | `detect-verbs.py`가 미매핑 verb를 byte 길이와 함께 출력, auto-patch 로그에 WARN | [M3] |
| FR-32 | 사용자 커스텀 매핑 오버레이 (`~/.claude/spinner-map.json`) | 오버레이 적용·불변식 검증·위반 시 명확한 에러 | [M3] |
| FR-33 | 매핑 스타일 선택 — semantic(기본) / witty(위트 1:1) | `--style witty`로 재패치 시 가이드 §5-옛 매핑 적용 | [M3] |

### 1.5 플랫폼

| ID | 요구사항 | 수용 기준 | 상태 |
|---|---|---|---|
| FR-40 | macOS (Apple Silicon·Intel) 지원 | 양 아키텍처 설치 검증 | [M0] arm64 검증 / Intel 검증 [M1] |
| FR-41 | Linux 지원 — systemd path unit 기반 자동 재패치, 재서명 no-op | Linux에서 install→verify→uninstall 왕복 성공 | [M4] |
| FR-42 | WSL 지원 (WSL 내 Claude Code 설치본 한정) | WSL Ubuntu에서 FR-41과 동일 기준 | [M4] |

## 2. 비기능 요구사항 (NFR)

| ID | 요구사항 | 기준 | 상태 |
|---|---|---|---|
| NFR-01 | 가역성 — 어떤 상태에서도 명령 1개로 설치 전 완전 복원 | `uninstall.sh --restore-bin` 후 원본 sha256 일치 | [M0] |
| NFR-02 | 무의존성 — macOS 기본 도구(python3·codesign·launchctl·bash) 외 요구 금지 | jq·brew 패키지 등 추가 설치 없이 동작 | [M0] |
| NFR-03 | 무간섭 — 사용자 설정·타 도구 hook 파괴 금지 | FR-12와 동일 | [M1] **완료** |
| NFR-04 | 안전 실패 — 어떤 실패도 claude 실행 불능 상태로 남기지 않는다 (서명 실패 시 py가 원본 자동 복구) | 서명 실패 주입 테스트에서 원본 복구 확인 | [M1] **완료** (py 내장 복구로 강화) |
| NFR-05 | 관측 가능성 — 자동 동작은 전부 로그에 남는다 (`deferred` 포함) | `spinner-patch.log`에 스캔·패치·skip·연기·에러 기록 | [M0] |
| NFR-06 | 테스트 가능성 — 실제 Claude 바이너리 없이 핵심 로직 검증 가능 | fixture 기반 테스트 통과, 샌드박스로 실기 격리 | [M1] **완료** (`tests/run.sh`, 72 assertion) |
| NFR-07 | 문서 정합성 — 문서 기술과 실제 코드·구조 일치 | DOC-01 해소, 릴리스 전 문서 diff 점검 절차 | [M1] **완료** |
| NFR-08 | CI — 매 커밋에 shellcheck + 매핑 검증 + 단위 테스트 자동 실행 | GitHub Actions green | [M4] (초안은 M1 로컬 스크립트) |

## 3. 제약사항

- **C-01**: Anthropic 독점 바이너리의 로컬 수정 — 재배포 금지, 사용자 머신 내 변경만 허용. 면책 고지 유지.
- **C-02**: byte 길이 불변식은 협상 불가 — 이를 깨는 어떤 기능도 수용하지 않는다.
- **C-03**: Layer B/C는 머신 전역 자원 — 프로젝트 스코프는 Layer A에만 적용 가능.
- **C-04**: hook `command`는 no-op 유지 — 도구 호출 경로에 부작용·지연 추가 금지.
- **C-05**: 문서·주석 한국어, 코드 식별자 영어.

## 4. 버그 레지스터

**전 항목 v1.0.0에서 수정 완료 — 각각 회귀 테스트로 보호됨 (`tests/run.sh`).** 검증 방법·원인 분석 상세는 [TRD §2](./TRD.md) 참조.

| ID | 심각도 | 증상 | 재현 | 수정 파일 |
|---|---|---|---|---|
| BUG-01 | High | 패치 완료 바이너리를 verify.sh가 "✗ 미패치 — Pondering 0\n0 건 잔존"으로 오판 | 재현 확인됨 (pipefail + `grep -c \|\| echo 0`) | `verify.sh` |
| BUG-02 | High | 사용자가 동일 matcher로 등록한 기존 hook을 설치가 무단 교체, 제거 시 소실 | 사용자 Bash hook 등록 → install.sh → hook 소실 | `install.sh`, `uninstall.sh` (머지 로직 추출) |
| BUG-03 | Medium | 바이너리 자동 탐지 폴백이 백업 파일(`*.bak.<ts>`)을 활성 바이너리로 선택 가능 | `~/.local/bin/claude` 부재 + 백업 mtime 최신 상태 | `src/patch-spinner-verbs.py` |
| BUG-04 | Medium | 자동 업데이트 쓰기 도중 FSEvents 트리거 → sentinel 미검출 → 영문 잔존 (수동 실행까지 방치) | 대용량 파일 쓰기 중 트리거 | `src/auto-patch-claude.sh` |
| BUG-05 | Medium | 패치 1회당 백업 최대 2개(각 ~205MB) 생성 + 무제한 누적 → 디스크 누수 | auto-patch 실행 후 `.bak.*` 개수 확인 | `src/auto-patch-claude.sh`, `src/patch-spinner-verbs.py` |
| BUG-06 | Low | uninstall의 KO_MARKERS가 snippets 라벨과 수동 동기화 — 라벨 변경 시 제거 누락 | 라벨 1개 변경 후 uninstall → hook 잔존 | `uninstall.sh` (BUG-02 해법에 통합) |
| DOC-01 | Low | README 폴더 구조(`docs/spinner/`)·snippet의 "jq 머지" 언급이 실제와 불일치 | 육안 | `README.md`, `snippets/settings-hooks.json` |

## 5. 요구사항 ↔ 마일스톤 추적표

| 마일스톤 | 포함 요구사항 |
|---|---|
| M0 (완료) | FR-01~05, 10, 11, 13, 20, 22, 30, 40(arm64) / NFR-01, 02, 04, 05 |
| M1 (v1.0 안정화 — **코드 완료**, Intel 실기 검증만 잔여) | FR-06, 07, 12, 15(전방 배치), 17, 21, 23, 40(Intel 잔여) / NFR-03, 06, 07 / BUG-01~06, DOC-01 |
| M2 (v1.1 설치 UX) | FR-14, 16 (FR-15는 M1으로 이동) |
| M3 (v1.2 매핑 확장) | FR-31, 32, 33 |
| M4 (v2.0 플랫폼) | FR-41, 42 / NFR-08 |
