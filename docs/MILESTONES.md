# Milestones — 개발 착수 계획

> 작성일: 2026-07-02 · 기준 문서: [PRD](./PRD.md) · [TRD](./TRD.md) · [REQUIREMENTS](./REQUIREMENTS.md)
> 진행 원칙: 마일스톤 순차 진행. 각 태스크는 요구사항 ID로 추적. 코드 변경은 TDD 사이클(`/tdd-red` → `/tdd-green` → `/tdd-refactor`) 적용 — 테스트 하네스(M1-T1)가 선행 조건.

## 전체 로드맵

```
M0 ──────── M1 ─────────── M2 ─────────── M3 ─────────── M4
완료         v1.0 안정화     v1.1 설치 UX    v1.2 매핑 확장   v2.0 플랫폼
(현재)       버그 6건+테스트  스코프/업데이트  감지/커스텀      Linux/WSL/CI
```

---

## M0 — 현재 완성된 버전 (기준선, 완료)

**상태: 동작 확인 완료 (macOS 14+ / Apple Silicon / Claude Code 2.1.153·2.1.170)**

| 완료 항목 | 근거 |
|---|---|
| 3-레이어 시스템 (hook 20 matcher + verb 178 치환 + LaunchAgent 자동 재패치) | FR-01~05 |
| install / uninstall(--restore-bin) / verify 스크립트 | FR-10, 11, 13, 20 |
| byte 불변식 검증(`validate_map`) + ad-hoc 재서명 + 전 과정 백업 | FR-03, 04, 22 |
| 배포 템플릿화 (`{{HOME}}`·`{{HOMEBREW_PREFIX}}` 치환) | 다계정 이식성 |
| 문서 5종 (README·ARCHITECTURE·MAPPING·TROUBLESHOOTING·작업 가이드) | — |

**알려진 미해결 결함**: BUG-01~06, DOC-01 ([REQUIREMENTS §4](./REQUIREMENTS.md)) — M1에서 전량 해소.

---

## M1 — v1.0 안정화 (**코드 완료 — 2026-07-02**)

**목표**: 알려진 결함 0건 + 회귀 테스트로 보호되는 첫 정식 릴리스.
**중점 반영**: 무간섭 in-place 업데이트(FR-17)가 핵심 요구로 격상되어, M2의 버전 스탬프·`--update`(FR-15)를 T9로 전방 배치함.

### 태스크 (RED → GREEN → REFACTOR 순으로 진행됨)

| # | 태스크 | 요구사항 | 내용 | 상태 |
|---|---|---|---|---|
| T1 | 테스트 하네스 구축 | NFR-06 | `tests/make-fixture.py`(두 embed 포맷 fixture) + Python unittest 2본 + 셸 테스트 3본(샌드박스 HOME/PATH, launchctl·codesign mock) + `tests/run.sh` | ✅ 완료 (72 assertion) |
| T2 | BUG-01: verify.sh 거짓 미패치 | FR-21 | `grep -c \|\| echo 0` 이중 출력 제거 → py `--check` 위임 | ✅ 완료 (회귀 테스트) |
| T3 | BUG-03: autodetect 백업 오탐 | — | `.bak.`·`.tmp`·숨김 필터 강화 + resolve() | ✅ 완료 |
| T4 | BUG-02+06: hook 머지 로직 추출 | FR-12/17, NFR-03 | `src/merge-hooks.py` 신설 — `# spinner-to-kor` command 마커(스키마 비표준 키 회피), 레거시 라벨 폴백, atomic write, 실패 시 무변경 | ✅ 완료 (14 테스트) |
| T5 | BUG-04: FSEvents race | FR-06 | mtime 안정화 대기(최근 10초 내 변경 파일만) + `deferred` 로그, `SPINNER_PATCH_SETTLE_SECS` | ✅ 완료 (race 시뮬레이션 테스트) |
| T6 | BUG-05: 백업 일원화+보존 정책 | FR-23 | 백업 생성 py 일원화, `prune_backups()` — 원본+최신만 유지. 서명 실패 시 py가 원본 자동 복구(NFR-04 강화) | ✅ 완료 |
| T7 | FR-07: sentinel 다중화·일원화 | FR-07 | `SENTINEL_VERBS` 3종 + `--check` CLI, 셸 3곳 위임 | ✅ 완료 |
| T8 | DOC-01: 문서 정합화 | NFR-07 | README 구조 실제화, jq 언급 수정, hardcoded plist → reference/ 이동, ARCHITECTURE·TROUBLESHOOTING 동기화 | ✅ 완료 |
| T9 | 버전 스탬프 + 무간섭 업데이트 (M2에서 전방 배치) | FR-15/17 | `VERSION` + 설치 스탬프 + `install.sh --update` + verify [6] 항목. 레거시 설치본 in-place 업그레이드 E2E 검증 | ✅ 완료 |

**릴리스 기준**: 전체 테스트 green ✅ + 실기 스모크(사용자 머신 `./install.sh --update` 1회) ⬜ + Intel Mac 1회 검증(FR-40) ⬜ + `VERSION=1.0.0` 태그 ⬜.

---

## M2 — v1.1 설치 UX·업데이트

**목표**: 전역/프로젝트 스코프 선택 + 도구 자체의 버전 관리·업데이트 경험.
**착수 조건**: M1 완료 (merge-hooks.py가 프로젝트 스코프의 기반).

| # | 태스크 | 요구사항 | 내용 | 완료 기준 |
|---|---|---|---|---|
| T1 | 프로젝트 스코프 설치 | FR-14 | `install.sh --project [DIR]` → `DIR/.claude/settings.json`에 Layer A만 머지 (merge-hooks.py `--settings` 인자 재사용). Layer B/C 부재 시 안내. uninstall 대칭 | ✅ **완료 (2026-07-02)** — E2E 20건: 전역↔프로젝트 상호 무간섭·멱등·`$PWD` 기본값·엣지(없는 DIR·깨진 JSON) |
| T2 | ~~버전 스탬프~~ · ~~업데이트 명령~~ | FR-15 | **M1 T9로 전방 배치 완료** | — |
| T3 | 단일 CLI 진입점 | FR-16 | `./spinner-to-kor <install\|uninstall\|update\|verify\|patch\|status>` 디스패처, 기존 진입점 유지 | 서브커맨드 전부 동작 + 하위 호환 |
| T4 | 문서 갱신 | NFR-07 | README 빠른시작에 스코프 반영, TROUBLESHOOTING 증상 추가 | — |

**릴리스 기준**: 신규 머신 클린 설치 → 프로젝트 설치 → update → uninstall 전체 시나리오 통과.

---

## M3 — v1.2 메시지 매핑 확장

**목표**: Claude Code 버전 변화에 대한 자가 적응력 + 사용자 취향 반영.
**착수 조건**: M1 완료 (M2와 병행 가능 — 파일 겹침 없음).

| # | 태스크 | 요구사항 | 내용 | 완료 기준 |
|---|---|---|---|---|
| T1 | 신규 verb 감지 도구 | FR-31 | `src/detect-verbs.py` — 경계 패턴 기반 후보 추출 → 매핑 diff 리포트 | 기존 178개 전부 검출 + 인위 추가 verb 검출 (fixture) |
| T2 | auto-patch 경보 통합 | FR-31 | 패치 후 감지 실행, 미매핑 발견 시 로그 `WARN unmapped=N` | 로그 회귀 테스트 |
| T3 | 커스텀 매핑 오버레이 | FR-32 | `~/.claude/spinner-map.json` 로드 → 풀 오버레이 → 불변식 검증·명확한 에러 | 오버레이 적용/위반 거부 테스트 |
| T4 | 스타일 프리셋 | FR-33 | `--style semantic\|witty` — 가이드 §5-옛 위트 매핑 데이터화 | witty 재패치 후 위트 라벨 검출 |
| T5 | MAPPING.md 갱신 | NFR-07 | 커스텀·스타일 절차 반영 | — |

**릴리스 기준**: 신규 Claude Code 버전(미래 verb 추가 가정 fixture)에서 "감지 → 풀 갱신 → 재패치" 절차가 문서대로 동작.

---

## M4 — v2.0 플랫폼 확장

**목표**: Linux/WSL 지원 + CI 자동화.
**착수 조건**: M1~M3 완료 (sentinel·머지·감지 로직이 플랫폼 중립이어야 이식 비용 최소).

| # | 태스크 | 요구사항 | 내용 | 완료 기준 |
|---|---|---|---|---|
| T1 | 플랫폼 추상화 | FR-41 | install.sh `uname` 분기, 재서명 단계 플랫폼별 no-op 처리 | macOS 회귀 없음 |
| T2 | systemd path unit | FR-41 | `templates/spinner-patch.path/.service` + 등록/해제 로직 | Linux에서 자동 재패치 왕복 |
| T3 | ELF 검증 | FR-41 | Linux용 Claude Code 바이너리에서 embed 패턴·sentinel 실측 재검증 | fixture + 실기 검증 |
| T4 | WSL 검증 | FR-42 | WSL Ubuntu 시나리오 테스트 | FR-41 기준 동일 |
| T5 | CI | NFR-08 | GitHub Actions: shellcheck + validate_map + unittest (ubuntu), macOS job은 mock 기반 | 매 커밋 green |

**릴리스 기준**: macOS·Linux·WSL 3환경 설치 매트릭스 통과 → v2.0.0 태그.

---

## 마일스톤 공통 완료 정의 (Definition of Done)

1. 해당 요구사항 ID의 수용 기준 전부 충족 + 회귀 테스트 포함
2. `tests/run.sh` green, 매핑 `validate_map()` 통과
3. 문서(README·ARCHITECTURE·TROUBLESHOOTING·MAPPING 중 해당분) 동기 갱신
4. `verify.sh` 실기 스모크 통과 (macOS)
5. CHANGELOG 항목 추가 + 버전 태그
