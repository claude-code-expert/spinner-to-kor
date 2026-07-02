# Architecture — 3 레이어 + 매핑 불변식

## 왜 3 레이어인가

Claude Code의 영문 verb("Pondering", "Schlepping" 등)는 **바이너리 안에 하드코딩된 ASCII 문자열**이라 `settings.json`만으로는 교체할 수 없다. 반대로 도구별 한국어 라벨("파일 읽는 중")은 `settings.json` 의 hook으로 충분하지만 바이너리 안 verb는 못 건드린다. 두 메커니즘이 결함을 상호 보완하고, 자동 업데이트로 인한 무효화는 LaunchAgent가 다시 보완한다.

```
사용자 입력
    │
    ▼
[Layer A] Hook statusMessage     ← ~/.claude/settings.json (PreToolUse 20개 매처)
    │  ex) Read 호출 → "파일 읽는 중"
    ▼
[Layer B] 바이너리 verb 한국어    ← ~/.local/share/claude/versions/<버전>
    │  ex) "추론중", "응답생성중", "답변을생성중" 회전
    ▼
[Layer C] 자동 재패치             ← ~/Library/LaunchAgents/dev.claude-spinner-patch.plist
       FSEvents가 새 바이너리 감지 → auto-patch-claude.sh 실행
```

## Layer A — Hook statusMessage

`~/.claude/settings.json` 의 `hooks.PreToolUse` 배열에 20개 매처를 둔다. 각 매처는 **무해한 `"command": "true"`** 만 실행하고 `statusMessage`로 한국어 라벨을 띄운다.

| 매처(정규식) | statusMessage |
|---|---|
| `Read` | `파일 읽는 중` |
| `Bash` | `쉘 명령 실행 중` |
| `Grep` | `코드 검색 중` |
| `Edit\|MultiEdit` | `파일 편집 중` |
| ... | (총 20개, 전체는 [snippets/settings-hooks.json](./snippets/settings-hooks.json) 참고) |
| `mcp__.*` | `MCP 도구 호출 중` |

핵심: **명령은 no-op**이므로 도구 호출에 부작용·지연이 없다. 오직 라벨 표시 목적.

## Layer B — 바이너리 in-place 패치

### 매핑 정책

영문 verb 178개를 **byte 길이별 한국어 풀**에 라운드로빈으로 매핑한다. 어떤 단어가 떠도 사용자는 즉시 "AI가 응답 생성 중"임을 안다.

| byte | 한국어 풀 (모두 "응답 생성 중" 의미) |
|---|---|
| 6  | 추론, 사고, 응답, 생성 |
| 9  | 추론중, 사고중, 응답중, 생성중, 분석중, 처리중, 작업중, 검토중, 준비중 |
| 12 | 답변추론, 응답생성, 코드작성, 문맥분석, 결과정리, 추론진행, 답변구성 |
| 15 | 답변생성중, 응답생성중, 코드작성중 |
| 18 | 답변을생성중, 응답을생성중 |
| ... | (홀수 byte는 trailing space로 패딩, 전체는 [MAPPING.md](./MAPPING.md)) |

### 핵심 불변식

```
영문 verb byte 수 == 한국어 라벨 UTF-8 byte 수
```

한글 1자 = 3 bytes, 부족분은 trailing space(1 byte)로 패딩한다. **같은 byte 길이라야 surrounding offset이 변하지 않는다** — Mach-O 안 모든 길이 prefix·jump target·section header가 그대로 보존된다.

`patch-spinner-verbs.py` 의 `validate_map()`이 매핑마다 byte 길이를 강제 검사하고, 불일치 시 exit 2로 거부한다.

### 패치 알고리즘

각 verb를 두 가지 경계 패턴으로 안전하게 치환한다 — Claude Code 바이너리(Bun compile)는 두 포맷으로 verb를 embed하기 때문이다:

```python
# 패턴 1: JSON 배열
data.replace(b'"' + en + b'"', b'"' + ko + b'"')

# 패턴 2: Bun length-prefixed
data.replace(b'\x00' + en + b'\x00', b'\x00' + ko + b'\x00')
```

byte 길이 보존 ⇒ 모든 byte offset 유지 ⇒ Mach-O 무결성 유지.

### ad-hoc 재서명

Apple Developer 서명 + hardened runtime 활성 바이너리는 **1 byte라도 수정되면 Gatekeeper가 차단**한다. 패치 직후 ad-hoc 자기 서명으로 교체한다:

```bash
codesign -s - --force --preserve-metadata=entitlements,flags <binary>
```

결과: `Signature=adhoc`, entitlements/flags 보존, 실행 가능.

## Layer C — LaunchAgent 자동 재패치

Claude Code는 백그라운드에서 자동 업데이트로 새 버전을 받아 `~/.local/share/claude/versions/2.1.NNN` 파일을 만든다. **새 파일에는 영문 verb가 다시 들어있다.**

`~/Library/LaunchAgents/dev.claude-spinner-patch.plist` 가 `versions/` 디렉터리를 FSEvents로 감시한다:

```xml
<key>WatchPaths</key>
<array>
    <string>{{HOME}}/.local/share/claude/versions</string>
</array>
<key>ThrottleInterval</key>
<integer>10</integer>
<key>RunAtLoad</key>
<false/>
```

흐름:

```
1. Claude Code 자동 업데이트가 versions/2.1.NNN 새로 생성
   ↓ FSEvents
2. LaunchAgent 10초 throttle 후
3. auto-patch-claude.sh 실행
4. versions/ 전체 스캔 → 영문 verb 잔존 파일만 패치 (idempotent)
5. 백업 → 한국어 치환 → ad-hoc 재서명
6. 로그 기록 (~/.claude/logs/spinner-patch.log)
7. 다음 claude 실행 시 한국어 verb 동작
```

### 알려진 한계와 방어책

- **파일 쓰기 도중 트리거**: 새 바이너리가 versions/에 완전히 기록되기 전에 FSEvents가 트리거될 수 있다. v1.0부터 mtime 안정화 대기(최근 변경 파일은 2초 후 재측정, 변화 시 연기 `deferred=N`)가 내장되어 다음 트리거에서 자동 재시도한다. FSEvents 자체 누락(절전 등) 시에는 `auto-patch-claude.sh` 수동 실행으로 복구.
- **미패치 판정 일원화**: 판정은 `patch-spinner-verbs.py --check`(다중 sentinel: Pondering·Thinking·Generating, 경계 패턴 카운트) 한 곳이 책임진다. verb 목록 변동에 대비해 sentinel 하나가 사라져도 감지가 유지된다.
- **계정·머신 고유**: plist 안 절대 경로가 들어가므로 다른 계정으로 옮길 때는 `install.sh`가 `{{HOME}}` 치환을 수행한다.

## 백업 자산

| 자산 | 위치 |
|---|---|
| `settings.json` 백업 | `~/.claude/settings.json.bak.<timestamp>` (install.sh 실행 직전) |
| 바이너리 백업 | `~/.local/share/claude/versions/<버전>.bak.<timestamp>` (patch-spinner-verbs.py 가 자동 생성) |
| 자동 패치 로그 | `~/.claude/logs/spinner-patch.log` |

백업 생성은 `patch-spinner-verbs.py` 한 곳이 책임진다 (셸 래퍼는 백업하지 않는다 — 이중 백업 방지). 보존 정책: 버전당 **가장 오래된 백업(깨끗한 원본) + 최신 백업**만 유지하고 중간 것은 자동 정리된다 — 바이너리가 개당 ~205MB라 무제한 누적 시 디스크를 잠식하기 때문이다.

## settings.json 무간섭 머지

Layer A hook의 설치·업데이트·제거는 `src/merge-hooks.py` 한 곳이 책임진다:

- 우리 entry 식별: `command` 안의 `# spinner-to-kor` 마커 (스키마 비표준 키를 쓰지 않기 위해 command 주석 사용). 마커 없는 구버전 설치본은 `command == "true"` + 알려진 라벨로 레거시 인식해 in-place 업그레이드한다.
- 사용자 hook은 같은 matcher라도 교체하지 않는다 — 별도 entry로 공존 (Claude Code는 같은 matcher entry를 모두 실행).
- 깨진 JSON·비정상 구조에서는 파일을 쓰지 않고 중단. 쓰기는 tmp + atomic replace.

## 플랫폼 추상화 (macOS / Linux / WSL)

Layer C의 감시 메커니즘만 OS별로 다르고 나머지(Layer A/B)는 공통이다. `src/platform.sh`가 이 차이를 캡슐화하고 install/uninstall/verify가 소싱한다:

| | macOS | Linux / WSL |
|---|---|---|
| 감시 | LaunchAgent `WatchPaths` (FSEvents) | systemd path unit `PathModified` |
| 등록 위치 | `~/Library/LaunchAgents/dev.claude-spinner-patch.plist` | `~/.config/systemd/user/spinner-patch.{path,service}` |
| 활성화 | `launchctl load -w` | `systemctl --user enable --now spinner-patch.path` |
| 재서명 | `codesign -s -` ad-hoc (필수) | no-op (ELF는 서명 없음) |

`spinner_detect_platform`은 `uname -s`로 판정하고 `SPINNER_PLATFORM` env로 오버라이드 가능 — 테스트가 실기 없이 양 경로를 검증한다. systemd가 없는 WSL1 등에서는 unit 파일만 배치하고 `wsl.conf` 안내 후 수동 패치 경로를 남긴다.

## 메이저 버전 업그레이드 시

Claude Code가 3.x로 가더라도 Bun compile + Mach-O 구조가 유지되면 같은 패치가 작동한다. 만약 packaging이 압축/암호화로 바뀌면 `~/.claude/logs/spinner-patch.log` 에 `patched=0 errors=N` 이 누적된다 — 그때 매핑 로직 재설계가 필요하다.
