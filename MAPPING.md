# Verb Mapping — 178개 → 한국어 풀

## 핵심 설계

영문 verb 178개는 Anthropic이 모델 추론 대기를 채우려고 만든 **무작위 위트**(`Pondering`, `Schlepping`, `Boogieing`, `Photosynthesizing`...). 어떤 verb가 떠도 의미는 같다 — **"모델이 응답을 만드는 중"**.

본 배포본은 위트를 그대로 한국어로 옮기지 않는다(그러면 "춤추기", "끌고가", "소용돌이"가 되어 사용자가 "지금 뭐 하는지" 알 수 없다). 대신 byte 길이별 한국어 풀에 라운드로빈으로 매핑한다 — 어떤 단어가 떠도 즉시 "AI가 답변 생성 중"임을 안다. 회전감은 풀 내 동의어로 유지.

### 매핑 불변식

```
영문 verb byte 수 == 한국어 라벨 UTF-8 byte 수
```

한글 1자 = 3 byte, 부족분은 trailing space(1 byte)로 패딩. **같은 byte 길이라야 Mach-O 안 모든 offset이 보존된다.**

## 한국어 풀 (byte 길이별)

| byte | 풀 (모두 "응답 생성 중" 의미) | 영문 verb 수 |
|---|---|---|
| 5  | (영문 유지 — "Doing"; 한글 1자 3 byte로는 의미 부족) | 1 |
| 6  | 추론 · 사고 · 응답 · 생성 | 4 |
| 7  | 추론· 사고· 응답· 생성· 분석· 처리· 작업 (+ trailing space) | 19 |
| 8  | (7 byte 풀 7종 + 검토) + 2 spaces | 29 |
| 9  | 추론중 · 사고중 · 응답중 · 생성중 · 분석중 · 처리중 · 작업중 · 검토중 · 준비중 | 30 |
| 10 | 9 byte 풀 8종 + trailing space | 31 |
| 11 | 9 byte 풀 7종 + 2 spaces | 23 |
| 12 | 답변추론 · 응답생성 · 코드작성 · 문맥분석 · 결과정리 · 추론진행 · 답변구성 | 15 |
| 13 | 12 byte 풀 6종 + trailing space | 13 |
| 14 | 답변추론 · 응답생성 · 코드작성 · 문맥분석 + 2 spaces | 6 |
| 15 | 답변생성중 · 응답생성중 · 코드작성중 | 3 |
| 16 | 답변생성중 · 응답생성중 + trailing space | 2 |
| 17 | 답변생성중 + 2 spaces | 1 |
| 18 | 답변을생성중 · 응답을생성중 | 2 |

총 178개 verb → 한국어 풀에 라운드로빈 매핑 (영문 5 byte "Doing" 제외).

## 실제 매핑 샘플

이전 위트 1:1 매핑 vs 현재 의미 통일 매핑 비교:

| 영문 verb | 옛 (2026-06-18 초기) | 현재 (2026-06-19 개정) |
|---|---|---|
| Pondering         | 사색중       | 추론중 |
| Boogieing         | 춤추기       | 분석중 |
| Schlepping        | 끌고가       | 응답중 (+ space) |
| Whirlpooling      | 소용돌이     | 답변추론 |
| Synthesizing      | 결과조합     | 답변추론 |
| Photosynthesizing | 광합성하기   | 답변생성중 (+ 2 spaces) |
| Discombobulating  | 혼란시키기   | 답변생성중 (+ space) |
| Flibbertigibbeting | 쓸데없는수다 | 답변을생성중 |
| Whatchamacalliting | 이름모를일중 | 응답을생성중 |

## 전체 매핑 dump

```bash
python3 -c "
import sys; sys.path.insert(0, '$HOME/.claude/scripts')
from importlib import import_module
m = import_module('patch-spinner-verbs')
import json
print(json.dumps(m.VERB_MAP, indent=2, ensure_ascii=False))
"
```

또는 본 배포본의 [src/patch-spinner-verbs.py](./src/patch-spinner-verbs.py) 의 `EN_VERBS_BY_LENGTH` (영문 원본)와 `KO_LABEL_POOLS` (한국어 풀)를 직접 확인.

## 커스텀 매핑 — 파일만 만들면 끝 (v1.2+)

`~/.claude/spinner-map.json` 을 만들면 코드 수정 없이 라벨을 바꿀 수 있다:

```json
{
  "pools": { "9": ["탐색중", "추리중", "궁리중"] },
  "overrides": { "Pondering": "궁리중" }
}
```

- `pools`: 해당 byte 길이 풀 전체 교체 (semantic 스타일에만 적용)
- `overrides`: 개별 verb 고정 (모든 스타일에 적용). 부족한 byte는 자동 space 패딩
- byte 불변식 위반·알 수 없는 verb·깨진 JSON → **패치 거부(exit 2), 바이너리 무변경**
- 파일 위치는 `SPINNER_MAP_FILE` 환경변수로 재지정 가능

## 스타일 프리셋 (v1.2+)

```bash
python3 ~/.claude/scripts/patch-spinner-verbs.py --style witty <binary>   # 위트 1:1 (아래 §5-옛 보존본)
python3 ~/.claude/scripts/patch-spinner-verbs.py --style semantic <binary> # 의미 통일 (기본)
```

이미 패치된 바이너리는 먼저 백업 복원 필요 (아래 "반영" 참고).

## 신규 verb 자동 감지 (v1.2+)

Claude Code 새 버전이 verb를 추가하면 매핑 밖 영문이 잔존한다. 자동 재패치가 성공할 때마다 감지가 함께 돌고, 미매핑 발견 시 로그에 `WARN unmapped=N` 이 남는다. 수동 확인:

```bash
python3 ~/.claude/scripts/detect-verbs.py <binary>
# unmapped=1
#   Zooming (7 bytes) — EN_VERBS_BY_LENGTH[7] 에 추가 후 백업 복원·재패치
```

두 embed 패턴(JSON + NUL 경계) **모두**에 등장하는 gerund만 후보로 보므로 일반 문자열("Loading" 류) 오탐이 차단된다.

## 풀을 직접 바꾸려면

### 좋은 변경

- 같은 byte 길이 안에서 동의어 추가/교체 (예: 9 byte 풀에 "탐색중" 추가)
- trailing space 위치 일관성 유지 (한 풀 내 모든 항목이 같은 byte 수)

### 위험한 변경

- byte 길이 불변식 위반 (예: 9 byte verb에 12 byte 한국어) → `validate_map()` 이 exit 2로 거부
- 풀 항목 개수를 영문 verb 수보다 적게 한다 — 정상 동작 (라운드로빈), 하지만 단조로움 증가

### 검증

```bash
# 매핑 검증
python3 ~/.claude/scripts/patch-spinner-verbs.py --help-validate 2>/dev/null || \
python3 -c "
import sys; sys.path.insert(0, '$HOME/.claude/scripts')
from importlib import import_module
m = import_module('patch-spinner-verbs')
m.validate_map()
print(f'OK — {len(m.VERB_MAP)} entries, all byte lengths match')
"
```

### 반영

이미 패치된 바이너리에는 영문 verb가 남아있지 않으니 매핑만 바꿔서는 반영되지 않는다. **백업 → 재패치** 필요:

```bash
BIN=~/.local/share/claude/versions/2.1.170
OLDEST_BAK=$(ls -1tr ${BIN}.bak.* | head -1)
cp -p "$OLDEST_BAK" "$BIN"   # 깨끗한 원본으로 복구
~/.claude/scripts/patch-spinner-verbs.sh "$BIN"   # 새 매핑으로 재패치
```

## 영문 원본 178개 verb 출처

- [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice/blob/main/reports/claude-spinner-verbs-and-tips.md) — 179개 verb 문서화
- Claude Code 2.1.153 / 2.1.170 바이너리 strings 추출 확인됨

byte 길이별 그룹화된 영문 원본 목록은 [src/patch-spinner-verbs.py](./src/patch-spinner-verbs.py) 의 `EN_VERBS_BY_LENGTH` dict 참고. 만약 새 메이저 버전에서 verb가 추가되면 그 dict에 추가하고 `validate_map()` 으로 byte 길이 점검만 통과시키면 자동으로 매핑된다.
