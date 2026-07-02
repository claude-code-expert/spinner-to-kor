# spinner-to-kor — 프로젝트 컨텍스트

Claude Code CLI의 스피너 영문 verb 178개("Pondering...", "Schlepping..." 등)를 "AI가 응답 생성 중" 의미로 수렴하는 한국어 라벨로 교체하는 macOS 전용 도구. 바이너리 in-place 패치 + settings.json hook + LaunchAgent 자동 재패치의 3-레이어 구조.

## 아키텍처 요약 (상세: ARCHITECTURE.md)

| 레이어 | 역할 | 대상 |
|---|---|---|
| A | PreToolUse hook `statusMessage` — 도구별 한국어 라벨 20개 | `~/.claude/settings.json` |
| B | Mach-O 바이너리 verb 178개 in-place 치환 + ad-hoc 재서명 | `~/.local/share/claude/versions/<버전>` |
| C | FSEvents 감시 → 자동 업데이트 후 재패치 | `~/Library/LaunchAgents/dev.claude-spinner-patch.plist` |

## 절대 불변식 — 위반 금지

```
영문 verb byte 수 == 한국어 라벨 UTF-8 byte 수
```

- 한글 1자 = 3 bytes. 부족분은 trailing space(1 byte) 패딩.
- 같은 byte 길이라야 Mach-O 내 모든 offset·length prefix·section header가 보존된다.
- `src/patch-spinner-verbs.py`의 `validate_map()`이 강제 검사 (불일치 시 exit 2).
- 매핑(`KO_LABEL_POOLS`, `EN_VERBS_BY_LENGTH`)을 수정하면 반드시 `validate_map()` 통과 확인 후 커밋.

## 핵심 파일

| 파일 | 역할 |
|---|---|
| `src/patch-spinner-verbs.py` | 매핑 정의(`EN_VERBS_BY_LENGTH`, `KO_LABEL_POOLS`) + 치환 + 백업/prune + ad-hoc 재서명 + `--check`(다중 sentinel 판정) 본체 |
| `src/merge-hooks.py` | settings.json 무간섭 머지/제거 단일 소스 — 마커(`# spinner-to-kor`) + 레거시 라벨 폴백 |
| `src/patch-spinner-verbs.sh` | 단일 바이너리 패치 래퍼 (탐지·안내만, 백업은 py 책임) |
| `src/auto-patch-claude.sh` | LaunchAgent 헬퍼 — versions/ 전체 스캔, mtime 안정화 대기, idempotent |
| `install.sh` / `uninstall.sh` / `verify.sh` | 설치·무간섭 업데이트(`--update`)·제거·6항목 자가진단 |
| `tests/run.sh` | 전체 테스트 (fixture 기반, 실기 격리) — 코드 수정 후 필수 실행 |
| `templates/LaunchAgent.plist.template` | `{{HOME}}`·`{{HOMEBREW_PREFIX}}` 치환용 배포 템플릿 |
| `snippets/settings-hooks.json` | settings.json에 머지할 PreToolUse 20개 매처 |
| `docs/PRD.md` · `docs/TRD.md` · `docs/REQUIREMENTS.md` · `docs/MILESTONES.md` | 제품·기술·요구사항·마일스톤 계획 |

## 작업 규칙

- **문서·주석은 한국어.** 코드 식별자·기술 용어는 원문 유지.
- **핵심 요구 FR-17 — 무간섭 in-place 업데이트**: 어떤 변경도 기설치 사용자의 재설치를 요구하거나 사용자 설정을 파괴하면 안 된다. 사용자 hook은 같은 matcher라도 교체 금지(별도 entry 공존), 실패 시 settings.json 무변경.
- 코드 수정 후 `tests/run.sh` 필수 통과. 새 버그 수정은 회귀 테스트 동반 (RED→GREEN→REFACTOR).
- 셸 스크립트는 `bash` + `set -euo pipefail` 기준. macOS(BSD) 유틸 호환 유지 — GNU 전용 플래그 금지 (`readlink -f`는 macOS 12.3+ OK).
- `set -o pipefail` 환경에서 `grep -c ... || echo 0` 패턴 금지 — 매치 0건 시 `"0\n0"` 이중 출력 (BUG-01, 수정됨). 미패치 판정은 반드시 `patch-spinner-verbs.py --check` 사용.
- settings.json 머지/제거는 `src/merge-hooks.py`만 통해서 한다. 우리 hook 마커는 `command` 안 `# spinner-to-kor` 주석 — snippet에서 지우지 말 것. `LEGACY_LABELS`는 과거 배포본 고정값이므로 새 라벨 추가 금지.
- 바이너리 백업은 `patch-spinner-verbs.py` 한 곳만 생성 (셸 래퍼 백업 금지 — BUG-05). 백업명 `<binary>.bak.<YYYYmmdd-HHMMSS>`, 가장 오래된 .bak = 깨끗한 원본, 보존 정책은 원본+최신 2개.
- sentinel 정의는 py의 `SENTINEL_VERBS` 한 곳 — 셸에서 자체 grep 금지.

## 자주 쓰는 명령

```bash
tests/run.sh                                   # 전체 테스트 (매핑 검증 포함)
./verify.sh                                    # 설치 상태 6항목 점검
./install.sh [--update|--no-patch]             # 전역 설치·무간섭 업데이트
./install.sh --project [DIR]                   # 프로젝트 스코프 (Layer A만)
./uninstall.sh [--restore-bin|--project [DIR]] # 제거 (+바이너리 영문 복원 / 프로젝트만)
python3 src/patch-spinner-verbs.py --check <bin>   # 패치 여부 조회 (수정 없음)
```

## 개발 착수 시 참조 순서

1. `docs/MILESTONES.md` — 현재 마일스톤과 착수 순서
2. `docs/REQUIREMENTS.md` — 요구사항 ID·버그 레지스터·수용 기준
3. `docs/TRD.md` — 기술 설계·결정 근거
