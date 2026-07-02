# Claude Code 한국어 스피너

Claude Code CLI 실행 시 회전하는 영문 동사("Pondering...", "Schlepping...", "Boogieing..." 등 178개)를 모두 **"AI가 응답 생성 중"이라는 의미로 수렴하는 한국어 라벨**로 교체하고, 도구 호출 시에도 한국어 상태("파일 읽는 중", "쉘 명령 실행 중" 등)를 함께 표시합니다.

```
[추론중]      ← 회전 (옛 "Pondering")
파일 읽는 중   ← 도구별 라벨 (Read 호출 시)
```

> macOS 전용 (LaunchAgent + Mach-O 코드서명 의존). Linux/Windows 미지원.

## 빠른 시작

```bash
git clone <this-repo> claude-code-korean-spinner
cd claude-code-korean-spinner
./install.sh
```

새 터미널에서 `claude` 실행 → 스피너에 한국어가 보이면 성공.

특정 프로젝트에만 도구 라벨(Layer A)을 적용하려면:

```bash
./install.sh --project /path/to/project   # 생략 시 현재 디렉터리
```

바이너리 verb 한국어화(Layer B/C)는 머신 전역 자원이라 전역 설치(`./install.sh`)가 필요합니다.

## 무엇이 설치되는가

3 레이어가 동시에 동작해 결함을 상호 보완합니다.

| 레이어 | 무엇 | 어디에 |
|---|---|---|
| **A. Hook statusMessage** | 도구별 한국어 라벨("파일 읽는 중" 등 20개) | `~/.claude/settings.json` (`hooks.PreToolUse`에 머지) |
| **B. 바이너리 verb 치환** | Mach-O 안 영문 verb 178개 → 한국어로 in-place 치환 + ad-hoc 재서명 | `~/.local/share/claude/versions/<버전>` |
| **C. 자동 재패치** | Claude Code 자동 업데이트로 새 바이너리 도착 시 FSEvents 감시 → 자동 패치 | `~/Library/LaunchAgents/dev.claude-spinner-patch.plist` |

자세한 원리는 [ARCHITECTURE.md](./ARCHITECTURE.md), 풀 매핑은 [MAPPING.md](./MAPPING.md).

## 폴더 구조

```
.
├── README.md                 ← 이 문서 (한 페이지 요약 + 빠른 시작)
├── ARCHITECTURE.md           3 레이어 동작 원리 + 매핑 불변식
├── TROUBLESHOOTING.md        흔한 증상·진단 명령·복구 절차
├── MAPPING.md                178개 verb 한국어 풀 정책 + 샘플 표
├── VERSION                   배포 버전 (설치 시 스탬프로 기록)
├── CHANGELOG.md              변경 이력
├── install.sh                원클릭 설치·무간섭 업데이트 (--update, --no-patch)
├── uninstall.sh              제거 (--restore-bin 으로 바이너리도 영문 복귀)
├── verify.sh                 설치 상태 자가 진단 (6개 항목 체크)
├── src/
│   ├── patch-spinner-verbs.py        178 verb 매핑 + 바이너리 치환 + 재서명 + --check 본체
│   ├── patch-spinner-verbs.sh        단일 파일 패치 래퍼
│   ├── auto-patch-claude.sh          LaunchAgent용 헬퍼 (versions/ 전체 스캔, 쓰기 안정화 대기)
│   └── merge-hooks.py                settings.json 무간섭 머지/제거 (사용자 hook 보존)
├── templates/
│   └── LaunchAgent.plist.template    {{HOME}}·{{HOMEBREW_PREFIX}} 변수화된 배포본
├── snippets/
│   └── settings-hooks.json           settings.json 의 PreToolUse 에 머지할 청크
├── tests/
│   ├── run.sh                        전체 테스트 실행기
│   ├── make-fixture.py               가짜 바이너리 생성기 (실바이너리 없이 검증)
│   ├── test_patch.py · test_merge_hooks.py   Python 단위 테스트
│   └── shell/                        설치 E2E·회귀 셸 테스트 (샌드박스 격리)
├── docs/
│   ├── PRD.md · TRD.md · REQUIREMENTS.md · MILESTONES.md   제품·기술·요구사항·마일스톤
└── reference/
    ├── original-author-guide.md      작업 시 작성한 풀 가이드 (개정 이력 포함)
    └── dev.codevillain.claude-spinner-patch.plist   과거 실사용 설치본 (참고용, 사용 금지)
```

## 자주 하는 일

| 상황 | 명령 |
|---|---|
| 설치 상태 점검 | `./verify.sh` |
| **이 도구를 새 버전으로 업데이트** | `git pull && ./install.sh --update` — 기존 설치·사용자 설정 무간섭, 재설치·삭제 불필요 |
| 특정 프로젝트에만 hook 설치/제거 | `./install.sh --project [DIR]` / `./uninstall.sh --project [DIR]` — 전역 설정 무접촉 |
| Claude Code 자동 업데이트 후 영문 verb가 보임 | `~/.claude/scripts/auto-patch-claude.sh` 수동 실행 |
| 특정 바이너리만 패치 | `~/.claude/scripts/patch-spinner-verbs.sh /path/to/binary` |
| 패치 여부만 조회 (수정 없음) | `python3 src/patch-spinner-verbs.py --check /path/to/binary` |
| 패치 활동 실시간 모니터링 | `tail -f ~/.claude/logs/spinner-patch.log` |
| 영문 복귀 (테스트용) | `./uninstall.sh --restore-bin` |
| 전체 테스트 실행 | `tests/run.sh` |

## 무간섭 업데이트 보장

이미 설치한 사용자는 **재설치·삭제 없이** `./install.sh --update` 한 번으로 새 기능·패치가 반영된다:

- 사용자가 직접 등록한 `settings.json` hook은 어떤 경우에도 파괴·변형되지 않는다 (같은 matcher라도 별도 entry로 공존).
- 구버전 설치본의 hook은 in-place 업그레이드된다 — 중복 생성 없음.
- 우리 hook 식별은 `command` 안의 `# spinner-to-kor` 마커로 한다. 이 주석을 지우면 업데이트·제거 시 해당 entry를 우리 것으로 인식하지 못한다.
- settings.json 이 깨져 있으면 아무것도 쓰지 않고 중단한다.

## 정상 동작 확인 기준

새 터미널에서 `claude` 실행 시:

- ✓ 스피너 옆 회전 단어가 한국어 — `추론중`, `사고중`, `답변생성중`, `응답을생성중` 등
- ✓ 도구 호출 시 한국어 상태 라벨 — `파일 읽는 중`, `코드 검색 중`, `쉘 명령 실행 중` 등
- ✓ `claude --version` 정상 출력 (코드서명 깨지지 않음)

`./verify.sh`가 위 항목을 포함해 6개 항목(바이너리·verb 잔존·LaunchAgent·hook·로그·버전)을 자동 점검합니다.

## 흔한 증상 → 빠른 답

> **"새 세션을 열어도 영문이 나옵니다"**
> Claude Code가 자동 업데이트로 새 버전을 받았는데 LaunchAgent가 미트리거됐을 가능성이 가장 큽니다. `~/.claude/scripts/auto-patch-claude.sh` 한 번 실행하세요. 자세한 진단·복구는 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

> **"`killed: 9` 로 즉시 종료됩니다"**
> ad-hoc 서명이 Gatekeeper에 차단된 경우입니다. `uninstall.sh --restore-bin` 으로 백업에서 즉시 복원하세요.

## 라이선스·면책

- Claude Code는 Anthropic의 독점 소프트웨어이며, 본 도구는 사용자 머신의 로컬 바이너리만 수정합니다.
- 바이너리 패치 후 Apple Developer 서명이 ad-hoc 서명으로 교체됩니다. 엔터프라이즈 MDM 정책에 따라 차단될 수 있습니다.
- 사용자의 책임 하에 사용하세요. 모든 작업은 백업이 생성되며 `uninstall.sh --restore-bin` 으로 완전 복원 가능합니다.



## 오픈소스 배포시 참고
  - hardcoded plist는 reference/ 로 이동 완료 (사용자는 templates/만 보면 됩니다).
  - install.sh가 {{HOME}}·{{HOMEBREW_PREFIX}} 자동 치환하므로 어느 macOS 계정에서도 그대로 동작합니다.
  - 개발 계획·요구사항은 [docs/MILESTONES.md](./docs/MILESTONES.md)·[docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md) 참고.