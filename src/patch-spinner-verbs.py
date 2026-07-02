#!/usr/bin/env python3
"""
Claude Code 스피너 동사(verb)를 의미 있는 한국어 라벨로 in-place 패치.

설계 원칙:
  Anthropic의 영문 verb 178개는 의미 없는 위트("Pondering", "Schlepping",
  "Boogieing"...)로 모델 추론 대기 시간을 채우는 장식이다. 이걸 그대로
  한국어로 옮기면 "사색중", "끌고가", "춤추기"가 되어 사용자가 "지금 뭐
  하는지" 알 수 없다.

  본 스크립트는 178개 verb 전부를 "모델이 응답을 만드는 중"이라는 단일
  의미로 수렴시키되, byte 길이별 풀에서 동의어를 라운드로빈으로 할당해
  스피너 회전감은 유지한다. 어떤 단어가 떠도 사용자는 즉시 "AI가 답변
  생성 중"임을 안다.

매핑 불변식:
  영문 verb byte 수 == 한국어 라벨 UTF-8 byte 수 (한글 1자=3B, 부족분은
  trailing space로 패딩). 같은 byte 길이라야 surrounding offset이 안전.

원리:
  Claude Code 바이너리(Mach-O Bun compile) 내부에 verb가 두 가지 포맷으로
  embed되어 있다:
    (A) Bun length-prefixed: \\0\\0\\0<len>\\0\\0\\0<len>\\0\\0\\0VERB\\0
    (B) JSON 배열: ,"VERB",

사용:
  patch-spinner-verbs.py <claude-binary-path>
  patch-spinner-verbs.py            # 자동 탐지: ~/.local/bin/claude → readlink
  patch-spinner-verbs.py --check <binary>
      조회 전용 — 영문 sentinel verb 등장 수를 stdout에 출력 (0 == 패치됨).
      파일을 수정하지 않는다. 실패 시 exit 2, stdout 무출력.

재패치 (이미 한국어로 패치된 바이너리는 영문 패턴이 없으니 백업 복구 선행):
  cp -p ~/.local/share/claude/versions/2.1.153.bak.20260618-174657 \\
        ~/.local/share/claude/versions/2.1.153
  patch-spinner-verbs.py
"""
import argparse
import json
import os
import sys
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

# 영문 verb 원본 목록 — byte 길이별 그룹화
# (Anthropic이 Claude Code 바이너리에 embed한 178개 whimsical verbs)
EN_VERBS_BY_LENGTH: dict[int, list[str]] = {
    6:  ["Baking", "Ebbing", "Musing", "Vibing"],
    7:  ["Beaming", "Booping", "Brewing", "Bunning", "Cooking", "Flowing",
         "Forging", "Forming", "Gusting", "Hashing", "Herding", "Honking",
         "Misting", "Mulling", "Nesting", "Stewing", "Warping", "Working",
         "Zesting"],
    8:  ["Churning", "Clauding", "Crafting", "Creating", "Doodling",
         "Frosting", "Grooving", "Hatching", "Ideating", "Infusing",
         "Ionizing", "Moseying", "Noodling", "Orbiting", "Osmosing",
         "Perusing", "Pouncing", "Proofing", "Puzzling", "Roosting",
         "Spinning", "Swirling", "Swooping", "Thinking", "Twisting",
         "Waddling", "Whirring", "Whisking", "Wibbling"],
    9:  ["Actioning", "Beboppin'", "Billowing", "Blanching", "Boogieing",
         "Burrowing", "Cascading", "Composing", "Computing", "Crunching",
         "Drizzling", "Effecting", "Finagling", "Galloping", "Gitifying",
         "Imagining", "Inferring", "Mustering", "Pondering", "Puttering",
         "Sautéing", "Scurrying", "Sketching", "Smooshing", "Sprouting",
         "Tempering", "Tinkering", "Unfurling", "Wandering", "Wrangling"],
    10: ["Befuddling", "Bloviating", "Canoodling", "Channeling",
         "Coalescing", "Cogitating", "Concocting", "Enchanting",
         "Fermenting", "Flambéing", "Flummoxing", "Fluttering",
         "Frolicking", "Garnishing", "Generating", "Incubating",
         "Levitating", "Marinating", "Meandering", "Nebulizing",
         "Nucleating", "Processing", "Ruminating", "Scampering",
         "Schlepping", "Slithering", "Spelunking", "Symbioting",
         "Thundering", "Undulating", "Zigzagging"],
    11: ["Actualizing", "Calculating", "Catapulting", "Cerebrating",
         "Channelling", "Considering", "Cultivating", "Deciphering",
         "Determining", "Elucidating", "Envisioning", "Evaporating",
         "Germinating", "Harmonizing", "Improvising", "Manifesting",
         "Moonwalking", "Percolating", "Pollinating", "Propagating",
         "Sublimating", "Transmuting", "Unravelling"],
    12: ["Architecting", "Boondoggling", "Caramelizing", "Deliberating",
         "Embellishing", "Gallivanting", "Hyperspacing", "Lollygagging",
         "Newspapering", "Quantumizing", "Reticulating", "Sock-hopping",
         "Synthesizing", "Tomfoolering", "Whirlpooling"],
    13: ["Accomplishing", "Bootstrapping", "Combobulating", "Contemplating",
         "Crystallizing", "Gesticulating", "Jitterbugging", "Orchestrating",
         "Perambulating", "Pontificating", "Precipitating", "Razzmatazzing",
         "Transfiguring"],
    14: ["Choreographing", "Dilly-dallying", "Hullaballooing",
         "Metamorphosing", "Philosophising", "Topsy-turvying"],
    15: ["Fiddle-faddling", "Razzle-dazzling", "Recombobulating"],
    16: ["Discombobulating", "Prestidigitating"],
    17: ["Photosynthesizing"],
    18: ["Flibbertigibbeting", "Whatchamacalliting"],
}

# 한국어 라벨 풀 — byte 길이별, 모두 "모델이 응답을 만드는 중" 의미로 수렴
# 한글 1자 = 3B, 부족분은 trailing space(1B)로 패딩
KO_LABEL_POOLS: dict[int, list[str]] = {
    6:  ["추론", "사고", "응답", "생성"],
    7:  ["추론 ", "사고 ", "응답 ", "생성 ", "분석 ", "처리 ", "작업 "],
    8:  ["추론  ", "사고  ", "응답  ", "생성  ", "분석  ", "처리  ", "작업  ", "검토  "],
    9:  ["추론중", "사고중", "응답중", "생성중", "분석중", "처리중", "작업중", "검토중", "준비중"],
    10: ["추론중 ", "사고중 ", "응답중 ", "생성중 ", "분석중 ", "처리중 ", "작업중 ", "검토중 "],
    11: ["추론중  ", "사고중  ", "응답중  ", "생성중  ", "분석중  ", "처리중  ", "작업중  "],
    12: ["답변추론", "응답생성", "코드작성", "문맥분석", "결과정리", "추론진행", "답변구성"],
    13: ["답변추론 ", "응답생성 ", "코드작성 ", "문맥분석 ", "결과정리 ", "추론진행 "],
    14: ["답변추론  ", "응답생성  ", "코드작성  ", "문맥분석  "],
    15: ["답변생성중", "응답생성중", "코드작성중"],
    16: ["답변생성중 ", "응답생성중 "],
    17: ["답변생성중  "],
    18: ["답변을생성중", "응답을생성중"],
}


# 위트 1:1 매핑 (2026-06-18 초기 버전 보존본) — --style witty 로 선택.
# 패딩(trailing space)은 build 시 자동 계산되므로 원 단어만 기록한다.
WITTY_RAW: dict[str, str] = {
    # 6B
    "Baking": "굽기", "Ebbing": "썰물", "Musing": "사색", "Vibing": "감각",
    # 7B
    "Beaming": "환함", "Booping": "톡톡", "Brewing": "끓임", "Bunning": "묶음",
    "Cooking": "요리", "Flowing": "흐름", "Forging": "단조", "Forming": "형성",
    "Gusting": "돌풍", "Hashing": "해싱", "Herding": "몰이", "Honking": "경적",
    "Misting": "안개", "Mulling": "숙고", "Nesting": "둥지", "Stewing": "조림",
    "Warping": "왜곡", "Working": "작업", "Zesting": "갈기",
    # 8B
    "Churning": "휘저", "Clauding": "코딩", "Crafting": "제작", "Creating": "생성",
    "Doodling": "낙서", "Frosting": "장식", "Grooving": "흥얼", "Hatching": "부화",
    "Ideating": "발상", "Infusing": "주입", "Ionizing": "이온", "Moseying": "산책",
    "Noodling": "끼적", "Orbiting": "공전", "Osmosing": "삼투", "Perusing": "정독",
    "Pouncing": "덮침", "Proofing": "교정", "Puzzling": "고민", "Roosting": "쉼터",
    "Spinning": "회전", "Swirling": "휘말", "Swooping": "활강", "Thinking": "사고",
    "Twisting": "비틈", "Waddling": "뒤뚱", "Whirring": "윙윙", "Whisking": "휘젓",
    "Wibbling": "흔들",
    # 9B
    "Actioning": "실행중", "Beboppin'": "박자중", "Billowing": "물결중",
    "Blanching": "데치기", "Boogieing": "춤추기", "Burrowing": "굴파기",
    "Cascading": "쏟아짐", "Composing": "작성중", "Computing": "계산중",
    "Crunching": "처리중", "Drizzling": "흩뿌리", "Effecting": "효과중",
    "Finagling": "꾀하기", "Galloping": "질주중", "Gitifying": "버전중",
    "Imagining": "상상중", "Inferring": "추론중", "Mustering": "준비중",
    "Pondering": "사색중", "Puttering": "만지작", "Sautéing": "볶음중",
    "Scurrying": "달리기", "Sketching": "스케치", "Smooshing": "뭉치기",
    "Sprouting": "발아중", "Tempering": "조절중", "Tinkering": "만지기",
    "Unfurling": "펼치기", "Wandering": "방황중", "Wrangling": "다투기",
    # 10B
    "Befuddling": "헷갈중", "Bloviating": "장광설", "Canoodling": "어루만",
    "Channeling": "전달중", "Coalescing": "융합중", "Cogitating": "사고중",
    "Concocting": "조합중", "Enchanting": "매혹중", "Fermenting": "발효중",
    "Flambéing": "플람베", "Flummoxing": "당황중", "Fluttering": "팔랑중",
    "Frolicking": "장난중", "Garnishing": "장식중", "Generating": "생성중",
    "Incubating": "부화중", "Levitating": "부양중", "Marinating": "재우는",
    "Meandering": "굽이굽", "Nebulizing": "성운화", "Nucleating": "핵형성",
    "Processing": "처리중", "Ruminating": "되새김", "Scampering": "쪼르륵",
    "Schlepping": "끌고가", "Slithering": "스르륵", "Spelunking": "탐험중",
    "Symbioting": "공생중", "Thundering": "쾅쾅중", "Undulating": "물결중",
    "Zigzagging": "지그재",
    # 11B
    "Actualizing": "실현중", "Calculating": "계산중", "Catapulting": "발사중",
    "Cerebrating": "두뇌중", "Channelling": "전달중", "Considering": "고려중",
    "Cultivating": "재배중", "Deciphering": "해독중", "Determining": "결정중",
    "Elucidating": "해명중", "Envisioning": "상상중", "Evaporating": "증발중",
    "Germinating": "발아중", "Harmonizing": "조화중", "Improvising": "즉흥중",
    "Manifesting": "구현중", "Moonwalking": "춤추기", "Percolating": "우려내",
    "Pollinating": "수분중", "Propagating": "전파중", "Sublimating": "승화중",
    "Transmuting": "변환중", "Unravelling": "풀어내",
    # 12B
    "Architecting": "구조설계", "Boondoggling": "허튼소리", "Caramelizing": "캐러멜화",
    "Deliberating": "심사숙고", "Embellishing": "꾸미는중", "Gallivanting": "쏘다니기",
    "Hyperspacing": "공간이동", "Lollygagging": "꾸물거리", "Newspapering": "기사작성",
    "Quantumizing": "양자처리", "Reticulating": "그물짜기", "Sock-hopping": "껑충뛰기",
    "Synthesizing": "결과조합", "Tomfoolering": "장난질중", "Whirlpooling": "소용돌이",
    # 13B
    "Accomplishing": "완수하기", "Bootstrapping": "초기화중", "Combobulating": "정리하기",
    "Contemplating": "곰곰생각", "Crystallizing": "결정화중", "Gesticulating": "몸짓표현",
    "Jitterbugging": "흥겹게춤", "Orchestrating": "총괄지휘", "Perambulating": "산책하기",
    "Pontificating": "잘난체중", "Precipitating": "강수발생", "Razzmatazzing": "야단법석",
    "Transfiguring": "형상변환",
    # 14B
    "Choreographing": "안무작성", "Dilly-dallying": "어슬렁대", "Hullaballooing": "와글와글",
    "Metamorphosing": "탈바꿈중", "Philosophising": "철학사색", "Topsy-turvying": "뒤죽박죽",
    # 15B
    "Fiddle-faddling": "꼼지락대기", "Razzle-dazzling": "와르르번쩍",
    "Recombobulating": "다시정리중",
    # 16B
    "Discombobulating": "혼란시키기", "Prestidigitating": "마술부리기",
    # 17B
    "Photosynthesizing": "광합성하기",
    # 18B
    "Flibbertigibbeting": "쓸데없는수다", "Whatchamacalliting": "이름모를일중",
}

# 사용자 커스텀 매핑 오버레이 파일 (FR-32)
DEFAULT_OVERLAY_FILE = Path.home() / ".claude" / "spinner-map.json"


def _pad_label(ko: str, target_bytes: int) -> str:
    """라벨 뒤에 trailing space를 채워 target byte 수에 맞춘다 (초과분은 validate가 거부)."""
    pad = target_bytes - len(ko.encode("utf-8"))
    return ko + " " * max(0, pad)


def load_overlay() -> dict:
    """~/.claude/spinner-map.json (SPINNER_MAP_FILE 로 재지정) 로드.

    없으면 빈 dict. 깨진 JSON·비정상 구조면 exit 2 — 조용히 기본값으로
    패치해 사용자 의도를 무시하는 것보다 명시적 실패가 안전하다.
    """
    path = Path(os.environ.get("SPINNER_MAP_FILE", DEFAULT_OVERLAY_FILE))
    if not path.exists():
        return {}
    try:
        with open(path) as f:
            overlay = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"오버레이 파일 오류 ({path}): {e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(overlay, dict):
        print(f"오버레이 최상위가 객체가 아님: {path}", file=sys.stderr)
        sys.exit(2)
    return overlay


def build_verb_map(style: str | None = None) -> dict[str, str]:
    """활성 매핑 생성 — 스타일(semantic/witty) + 사용자 오버레이 적용.

    semantic(기본): byte 길이별 풀 라운드로빈. 오버레이 "pools"로 풀 교체 가능.
    witty: 위트 1:1 보존본. "pools"는 무시, "overrides"는 두 스타일 모두 적용.
    """
    style = style or os.environ.get("SPINNER_STYLE", "semantic")
    if style not in ("semantic", "witty"):
        print(f"알 수 없는 스타일: {style} (semantic|witty)", file=sys.stderr)
        sys.exit(2)
    overlay = load_overlay()

    m: dict[str, str] = {}
    if style == "witty":
        for length, verbs in EN_VERBS_BY_LENGTH.items():
            for verb in verbs:
                m[verb] = _pad_label(WITTY_RAW[verb], length)
    else:
        pools = dict(KO_LABEL_POOLS)
        for key, labels in overlay.get("pools", {}).items():
            if not (isinstance(labels, list) and labels
                    and all(isinstance(x, str) for x in labels)):
                print(f"오버레이 pools[{key!r}] 는 비어있지 않은 문자열 배열이어야 함",
                      file=sys.stderr)
                sys.exit(2)
            try:
                pools[int(key)] = labels
            except ValueError:
                print(f"오버레이 pools 키는 byte 수(정수)여야 함: {key!r}", file=sys.stderr)
                sys.exit(2)
        for length, verbs in EN_VERBS_BY_LENGTH.items():
            pool = pools[length]
            for i, verb in enumerate(verbs):
                m[verb] = pool[i % len(pool)]

    for en, ko in overlay.get("overrides", {}).items():
        if en not in m:
            print(f"오버레이 overrides 에 알 수 없는 verb: {en!r} (오타?)", file=sys.stderr)
            sys.exit(2)
        if not isinstance(ko, str):
            print(f"오버레이 overrides[{en!r}] 는 문자열이어야 함", file=sys.stderr)
            sys.exit(2)
        m[en] = _pad_label(ko, len(en.encode("utf-8")))
    return m


# 5B "Doing"은 한글 1자(3B)로 의미 부족 → 매핑 제외(영문 유지)
VERB_MAP: dict[str, str] = build_verb_map()

# 미패치 판정 sentinel — 다중화 (Anthropic이 verb 하나를 빼도 감지 유지).
# 셸 스크립트는 자체 grep 대신 반드시 `--check` 로 이 정의를 사용한다.
SENTINEL_VERBS: list[str] = ["Pondering", "Thinking", "Generating"]


def count_english_verbs(data: bytes, verbs: list[str] | None = None) -> int:
    """경계 패턴 기준 영문 sentinel verb 등장 수. 0 == 패치 완료."""
    total = 0
    for verb in verbs or SENTINEL_VERBS:
        b = verb.encode("utf-8")
        total += data.count(b'"' + b + b'"')
        total += data.count(b"\x00" + b + b"\x00")
    return total


def prune_backups(binary_path: Path, keep_edges: int = 2) -> list[Path]:
    """백업 보존 정책: 가장 오래된(깨끗한 원본) + 최신만 유지, 중간 삭제.

    백업명의 timestamp(YYYYmmdd-HHMMSS)는 사전순 == 시간순.
    """
    baks = sorted(binary_path.parent.glob(binary_path.name + ".bak.*"))
    if len(baks) <= keep_edges:
        return []
    doomed = baks[1:-1]
    for p in doomed:
        p.unlink()
        print(f"백업 정리: {p.name}", file=sys.stderr)
    return doomed


def validate_map(verb_map: dict[str, str] | None = None) -> None:
    """모든 매핑이 영문 byte 수 == UTF-8 byte 수 invariant를 만족하는지 강제."""
    errors = []
    for en, ko in (VERB_MAP if verb_map is None else verb_map).items():
        en_len = len(en.encode("utf-8"))
        ko_len = len(ko.encode("utf-8"))
        if en_len != ko_len:
            errors.append(f"  {en!r} ({en_len}B) != {ko!r} ({ko_len}B)")
    if errors:
        print("매핑 byte 길이 불일치 (불변식 위반):", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        sys.exit(2)


def autodetect_binary() -> Path:
    """~/.local/bin/claude 심볼릭 링크를 따라가 실제 Mach-O 바이너리 탐지."""
    candidate = Path.home() / ".local" / "bin" / "claude"
    if candidate.exists():
        resolved = candidate.resolve()
        if resolved.is_file():
            return resolved
    versions_dir = Path.home() / ".local" / "share" / "claude" / "versions"
    if versions_dir.exists():
        files = sorted(versions_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
        for f in files:
            if not f.is_file():
                continue
            # 백업(.bak.<ts>)·임시(.tmp)·숨김 파일은 활성 바이너리가 아니다 (BUG-03)
            if f.name.startswith(".") or ".bak." in f.name \
                    or f.name.endswith((".bak", ".tmp")):
                continue
            return f.resolve()
    print("Claude Code 바이너리를 자동 탐지하지 못함. 인자로 경로를 지정하세요.",
          file=sys.stderr)
    sys.exit(2)


def patch_binary(binary_path: Path) -> tuple[int, int]:
    """
    바이너리 in-place 패치.

    각 verb에 대해 두 가지 boundary 패턴으로 안전 치환:
      (1) b'"VERB"' (JSON 배열용)
      (2) b'\\0VERB\\0' (Bun length-prefixed용)

    Returns: (총 verb 수, 치환된 occurrence 수)
    """
    print(f"바이너리 읽는 중: {binary_path}", file=sys.stderr)
    data = bytearray(binary_path.read_bytes())
    original_size = len(data)

    total_replacements = 0
    for en, ko in VERB_MAP.items():
        en_bytes = en.encode("utf-8")
        ko_bytes = ko.encode("utf-8")
        assert len(en_bytes) == len(ko_bytes), f"invariant broken at {en}"

        pat1_old = b'"' + en_bytes + b'"'
        pat1_new = b'"' + ko_bytes + b'"'
        count1 = data.count(pat1_old)
        if count1 > 0:
            data = bytearray(bytes(data).replace(pat1_old, pat1_new))
            total_replacements += count1

        pat2_old = b"\x00" + en_bytes + b"\x00"
        pat2_new = b"\x00" + ko_bytes + b"\x00"
        count2 = data.count(pat2_old)
        if count2 > 0:
            data = bytearray(bytes(data).replace(pat2_old, pat2_new))
            total_replacements += count2

    assert len(data) == original_size, "바이너리 크기 변경 — 위험 (오프셋 시프트)"

    tmp_path = binary_path.with_suffix(binary_path.suffix + ".tmp")
    tmp_path.write_bytes(bytes(data))
    tmp_path.chmod(0o755)
    tmp_path.replace(binary_path)
    print(f"패치 완료: {total_replacements} occurrence 치환", file=sys.stderr)
    return len(VERB_MAP), total_replacements


def adhoc_sign(binary_path: Path) -> bool:
    """Apple 서명 무효화 — ad-hoc(self) 재서명. macOS 한정."""
    if sys.platform != "darwin":
        return True
    print("ad-hoc 재서명 중 (codesign -s - --force)...", file=sys.stderr)
    result = subprocess.run(
        ["codesign", "-s", "-", "--force", "--preserve-metadata=entitlements,flags", str(binary_path)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"재서명 실패: {result.stderr}", file=sys.stderr)
        return False
    return True


def main() -> int:
    global VERB_MAP

    parser = argparse.ArgumentParser(description="Claude Code 스피너 verb 한국어 패치")
    parser.add_argument("binary", nargs="?", help="대상 바이너리 (생략 시 자동 탐지)")
    parser.add_argument("--check", action="store_true",
                        help="조회 전용 — 영문 sentinel 수를 stdout에 출력, 무수정")
    parser.add_argument("--style", choices=["semantic", "witty"], default=None,
                        help="매핑 스타일 (기본 semantic, env SPINNER_STYLE)")
    args = parser.parse_args()

    if args.style:
        VERB_MAP = build_verb_map(style=args.style)
    validate_map()
    check_only = args.check

    if args.binary:
        binary_path = Path(args.binary).expanduser().resolve()
    else:
        binary_path = autodetect_binary()

    if not binary_path.is_file():
        print(f"바이너리 없음: {binary_path}", file=sys.stderr)
        return 2

    en_count = count_english_verbs(binary_path.read_bytes())

    if check_only:
        # 조회 전용 계약: 성공 시에만 stdout에 숫자 1개 (BUG-01류 이중 출력 방지)
        print(en_count)
        return 0

    if en_count == 0:
        print("이미 패치됨 (영문 sentinel 0건) — skip.", file=sys.stderr)
        return 0

    # 백업은 여기 한 곳에서만 생성한다 (BUG-05: 셸 래퍼와의 이중 백업 금지)
    backup = binary_path.with_name(
        f"{binary_path.name}.bak.{datetime.now():%Y%m%d-%H%M%S}"
    )
    if not backup.exists():
        print(f"백업 생성: {backup.name}", file=sys.stderr)
        shutil.copy2(binary_path, backup)

    verb_count, replacements = patch_binary(binary_path)
    if not adhoc_sign(binary_path):
        # 실행 불능 상태로 방치 금지 — 원본(유효 서명 보존) 즉시 복원 (NFR-04)
        print(f"재서명 실패 — 백업에서 자동 복구: {backup.name}", file=sys.stderr)
        shutil.copy2(backup, binary_path)
        return 3

    prune_backups(binary_path)
    print(f"✓ 완료: {verb_count}개 verb 매핑, {replacements}개 위치 치환 (백업: {backup.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
