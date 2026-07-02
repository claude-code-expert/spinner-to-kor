# 릴리스 가이드 — 버전업·빌드·배포

> 대상: 메인테이너. 한 줄 설치(`curl … bootstrap.sh | bash`)가 GitHub Release tarball 을 받으므로, **새 버전을 사용자에게 전달하는 유일한 경로는 Release 발행**이다.
> 관련: [../REQUIREMENTS.md](../REQUIREMENTS.md) (FR-18/19) · [../../CHANGELOG.md](../../CHANGELOG.md) · [체크리스트](./CHECKLIST.md)

## 1. 이 프로젝트에 "빌드"는 없다

순수 bash + python3다. 컴파일·번들·트랜스파일 단계가 없고 산출물 아티팩트도 없다.

| 일반 프로젝트 | 이 프로젝트 |
|---|---|
| 소스 → 컴파일 → 바이너리/번들 | (없음) |
| 아티팩트 업로드 | GitHub 이 태그에서 tarball 자동 생성 |
| 릴리스 = 빌드 + 배포 | 릴리스 = **VERSION 갱신 + 태그 + Release 발행** |

부트스트랩(`bootstrap.sh`)은 `https://api.github.com/repos/<repo>/releases/latest` 로 최신 release 의 `tarball_url` 을 조회해 그 소스를 받는다. 즉 **Release 로 발행되지 않은 태그는 사용자에게 보이지 않는다.**

## 2. 버전 정책 (SemVer)

`VERSION` 파일 한 곳이 진실의 출처다. 설치 시 `~/.claude/scripts/.spinner-to-kor-version` 으로 스탬프되어 `spinner-to-kor status`·`verify` 가 비교한다.

| 자리 | 올리는 경우 | 예 |
|---|---|---|
| MAJOR | 하위 호환 깨짐 (CHANGELOG 에 `BREAKING CHANGE`) | 2.0.0 — install.sh 의 macOS 전용 게이트 제거 |
| MINOR | 기능 추가, 호환 유지 | 2.1.0 — curl 원격 설치 |
| PATCH | 버그 수정만 | 2.1.1 — 부트스트랩 URL 파싱 수정 |

매핑 byte 불변식·hook 무간섭 계약을 깨는 변경은 자동으로 MAJOR다.

## 3. 릴리스 절차 (단계별)

### 3.1 사전 점검 — 하나라도 실패하면 중단

```bash
git switch main && git pull
tests/run.sh                                  # 전체 green
shellcheck -x bootstrap.sh install.sh uninstall.sh verify.sh spinner-to-kor \
  src/platform.sh src/auto-patch-claude.sh src/patch-spinner-verbs.sh
[[ -z "$(git status --porcelain)" ]] && echo "clean" || echo "미커밋 존재 — 정리 후 진행"
```

### 3.2 버전 + CHANGELOG

```bash
echo "2.1.1" > VERSION
# CHANGELOG.md 최상단에 이번 버전 섹션 추가 (사용자 관점 변경만, why 위주)
```

### 3.3 커밋 · 태그 · push

```bash
git add VERSION CHANGELOG.md
git commit -m "chore: release v2.1.1"
git tag -a v2.1.1 -m "v2.1.1 — <한 줄 요약>"
git push origin main --tags
```

태그는 **annotated(`-a`)** — 태거·날짜·메시지를 보존하는 독립 객체라 릴리스 지점 기록에 적합하다. lightweight 태그 금지.

### 3.4 GitHub Release 발행 (= 실제 배포)

```bash
# CHANGELOG 해당 섹션을 릴리스 노트로 사용
gh release create v2.1.1 \
  --title "v2.1.1" \
  --notes "$(awk '/^## 2\.1\.1/{f=1;next} /^## /{f=0} f' CHANGELOG.md)"
```

발행 즉시 `latest` 가 이 태그로 바뀌고, 기존 사용자의 `spinner-to-kor update` 가 새 버전을 받는다.

### 3.5 배포 검증 — 실제 설치 흐름으로

```bash
# 격리 환경(새 컨테이너·계정) 권장. 로컬이면 HOME 위장:
curl -fsSL https://raw.githubusercontent.com/claude-code-expert/spinner/main/bootstrap.sh | bash
spinner-to-kor status      # repo/설치본 버전 == 방금 발행한 버전
spinner-to-kor verify      # 6항목 전부 ✓
```

## 4. 최초 배포 (현재 상황)

로컬에 태그 `v1.0.0`~`v2.1.0` 5개가 있으나 **원격 push·Release 발행은 아직 안 됨**. 한 줄 설치가 동작하려면 최소 **최신 태그 1개의 Release 가 필요**하다.

```bash
# 1. 브랜치 + 태그 전부 원격 반영
git push origin main --tags

# 2. 최신 버전 Release 발행 (부트스트랩은 latest 만 받으므로 이것만으로 설치 가능)
gh release create v2.1.0 --title "v2.1.0" \
  --notes "$(awk '/^## 2\.1\.0/{f=1;next} /^## /{f=0} f' CHANGELOG.md)"

# (선택) 과거 버전도 이력용으로 발행하려면 각 태그 반복
for v in 1.0.0 1.1.0 1.2.0 2.0.0; do
  gh release create "v$v" --title "v$v" \
    --notes "$(awk -v ver="$v" '$0 ~ "^## " ver {f=1;next} /^## /{f=0} f' CHANGELOG.md)"
done
```

과거 버전 Release 는 없어도 설치엔 지장 없다(부트스트랩은 latest 만 사용). 이력·재현 목적이면 발행.

## 5. 롤백

발행한 버전에 결함이 발견되면:

```bash
# A. 문제 Release 를 내려 latest 를 직전 안정 버전으로 되돌림
gh release delete v2.1.1 --yes           # 태그는 유지 (이력 보존)
# 필요시 이전 버전을 latest 로:
gh release edit v2.1.0 --latest

# B. 이미 설치한 사용자는 직전 버전으로 재설치
SPINNER_REPO=claude-code-expert/spinner spinner-to-kor update   # latest = 되돌린 버전
```

사용자 측 안전장치는 이미 있다 — 바이너리는 백업에서 `uninstall --restore-bin`, settings.json 은 머지 실패 시 무변경.

## 6. 포크·사설 배포

부트스트랩은 대상 저장소를 env 로 바꿀 수 있다:

```bash
# 포크에서 설치
SPINNER_REPO=myorg/myfork \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/myorg/myfork/main/bootstrap.sh | bash'

# 오프라인/사내 미러 — 로컬 tarball 로 설치
SPINNER_SOURCE_TARBALL=/path/to/spinner-src.tar.gz bash bootstrap.sh
```

## 7. 자동화 (선택 — 미구현)

`git push --tags` 시 Release 를 자동 발행하려면 `.github/workflows/` 에 태그 트리거 잡을 추가한다:

```yaml
on:
  push:
    tags: ['v*']
jobs:
  release:
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v4
      - run: gh release create "${GITHUB_REF_NAME}" --generate-notes
        env: { GH_TOKEN: "${{ github.token }}" }
```

현재는 수동 발행(§3.4)만 지원한다. 릴리스 빈도가 늘면 도입 권장.
