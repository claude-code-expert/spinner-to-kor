# Claude Code 한국어 스피너

Claude Code CLI 실행 시 회전하는 영문 동사("Pondering...", "Schlepping...", "Boogieing..." 등 178개)를 모두 **"AI가 응답 생성 중"이라는 의미로 수렴하는 한국어 라벨**로 교체하고, 도구 호출 시에도 한국어 상태("파일 읽는 중", "쉘 명령 실행 중" 등)를 함께 표시합니다.

```
[추론중]      ← 회전 (옛 "Pondering")
파일 읽는 중   ← 도구별 라벨 (Read 호출 시)
```

> macOS(LaunchAgent + Mach-O ad-hoc 재서명) · Linux/WSL(systemd path unit, 재서명 불요) 지원. 네이티브 Windows 미지원.

## 빠른 시작 — 한 줄 설치

```bash
curl -fsSL https://raw.githubusercontent.com/claude-code-expert/spinner/main/bootstrap.sh | bash
```

부트스트랩이 GitHub 최신 release 를 받아 설치하고, `spinner-to-kor` 명령을 `~/.local/bin` 에 심습니다. 새 터미널에서 `claude` 실행 → 스피너에 한국어가 보이면 성공.

이후 설치·업데이트·제거는 모두 이 한 명령으로:

```bash
spinner-to-kor update                 # 최신 release 로 무간섭 업데이트 (재설치·삭제 불필요)
spinner-to-kor uninstall              # 제거 (hook·자동재패치·스크립트·스냅샷)
spinner-to-kor uninstall --restore-bin  # 제거 + 바이너리 영문 복원
spinner-to-kor status                 # 버전·패치·자동재패치 상태 요약
spinner-to-kor verify                 # 6항목 자가 진단
```

> `~/.local/bin` 이 PATH에 없으면 설치 로그가 안내합니다. shell 설정에 추가하거나 `~/.local/bin/spinner-to-kor` 전체 경로로 실행하세요.

### 특정 프로젝트에만 (Layer A hook)

```bash
spinner-to-kor install --project /path/to/project   # 생략 시 현재 디렉터리
```

바이너리 verb 한국어화(Layer B/C)는 머신 전역 자원이라 전역 설치가 필요합니다.

### 소스에서 직접 (개발자)

```bash
git clone https://github.com/claude-code-expert/spinner
cd spinner
./install.sh          # release 없이 로컬 소스로 설치
tests/run.sh          # 전체 테스트
```

## 무엇이 설치되는가

3 레이어가 동시에 동작해 결함을 상호 보완합니다.

| 레이어 | 무엇 | 어디에 |
|---|---|---|
| **A. Hook statusMessage** | 도구별 한국어 라벨("파일 읽는 중" 등 20개) | `~/.claude/settings.json` (`hooks.PreToolUse`에 머지) |
| **B. 바이너리 verb 치환** | Mach-O 안 영문 verb 178개 → 한국어로 in-place 치환 + ad-hoc 재서명 | `~/.local/share/claude/versions/<버전>` |
| **C. 자동 재패치** | Claude Code 자동 업데이트로 새 바이너리 도착 시 감시 → 자동 패치 | macOS: `~/Library/LaunchAgents/dev.claude-spinner-patch.plist` / Linux·WSL: `~/.config/systemd/user/spinner-patch.path` |

자세한 원리는 [ARCHITECTURE.md](./ARCHITECTURE.md), 풀 매핑은 [MAPPING.md](./MAPPING.md).


## 자주 하는 일

| 상황 | 명령 |
|---|---|
| 설치 상태 점검 | `spinner-to-kor verify` |
| **이 도구를 새 버전으로 업데이트** | `spinner-to-kor update` — 최신 release 로 무간섭 반영, 재설치·삭제 불필요 |
| 특정 프로젝트에만 hook 설치/제거 | `spinner-to-kor install --project [DIR]` / `uninstall --project [DIR]` — 전역 설정 무접촉 |
| Claude Code 자동 업데이트 후 영문 verb가 보임 | `~/.claude/scripts/auto-patch-claude.sh` 수동 실행 |
| 특정 바이너리만 패치 | `~/.claude/scripts/patch-spinner-verbs.sh /path/to/binary` |
| 패치 여부만 조회 (수정 없음) | `python3 src/patch-spinner-verbs.py --check /path/to/binary` |
| 신규 미매핑 verb 확인 | `python3 ~/.claude/scripts/detect-verbs.py /path/to/binary` |
| 라벨 커스텀 / 위트 스타일 | `~/.claude/spinner-map.json` 작성 / `--style witty` — [MAPPING.md](./MAPPING.md) 참고 |
| 패치 활동 실시간 모니터링 | `tail -f ~/.claude/logs/spinner-patch.log` |
| 영문 복귀 (테스트용) | `spinner-to-kor uninstall --restore-bin` |
| 전체 테스트 실행 (개발) | `tests/run.sh` |

## 무간섭 업데이트 보장

이미 설치한 사용자는 **재설치·삭제 없이** `spinner-to-kor update` 한 번으로 새 기능·패치가 반영된다:

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



## 메인테이너 — 새 버전 릴리스

한 줄 설치는 GitHub **Releases** 의 최신 태그 tarball 을 받습니다. 새 버전 배포 절차:

```bash
# 1. VERSION 파일 갱신 + CHANGELOG 항목 추가 후 커밋
# 2. 태그 + push
git tag -a v2.1.0 -m "v2.1.0 — ..."
git push origin main --tags
# 3. GitHub Release 발행 (tarball 자동 첨부)
gh release create v2.1.0 --title "v2.1.0" --notes-file <(sed -n '/## 2.1.0/,/## /p' CHANGELOG.md)
```

release 발행 즉시 기존 사용자의 `spinner-to-kor update` 가 새 버전을 받습니다. release 가 아직 없으면 부트스트랩이 `git clone` 대체 안내를 출력합니다.

전체 절차·버전 정책·롤백·검증은 [docs/release/RELEASE.md](./docs/release/RELEASE.md), 매 릴리스 실행 목록은 [docs/release/CHECKLIST.md](./docs/release/CHECKLIST.md).

## 오픈소스 배포시 참고
  - hardcoded plist는 reference/ 로 이동 완료 (사용자는 templates/만 보면 됩니다).
  - 부트스트랩은 순수 bash+python3 — Node/npm 의존 없음. `bootstrap.sh` 는 `SPINNER_REPO`·`SPINNER_SOURCE_TARBALL` env 로 포크·오프라인 설치 지원.
  - 개발 계획·요구사항은 [docs/MILESTONES.md](./docs/MILESTONES.md)·[docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md) 참고.