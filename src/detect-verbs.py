#!/usr/bin/env python3
"""Claude Code 바이너리에서 미매핑 신규 spinner verb 감지 (FR-31).

원리:
  spinner verb는 바이너리에 두 포맷으로 embed된다 — (A) JSON 배열 "VERB",
  (B) NUL 경계 \\0VERB\\0. **두 패턴 모두**에 등장하는 gerund(-ing / -in')만
  후보로 본다. 일반 코드 문자열("Loading" 류)은 한 패턴에만 나타나므로
  오탐이 차단된다.

  패치 여부와 무관하게 동작한다 — 매핑된 verb는 패치로 한국어가 되고,
  미매핑 신규 verb만 영문으로 남아 그대로 감지된다.

사용:
  detect-verbs.py <binary>            # 미매핑 verb 리포트 (byte 길이 포함)
  detect-verbs.py --count <binary>    # 미매핑 수만 stdout에 출력 (auto-patch 연동)
"""
import argparse
import importlib.util
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# 의도적으로 매핑하지 않는 verb — 보고 대상 아님
KNOWN_UNMAPPED = frozenset({"Doing"})

# 대문자 시작 + 2~30 byte 연속(경계 문자 제외). 비ASCII(é 등) 허용 후 decode로 거른다.
_JSON_RE = re.compile(rb'"([A-Z][^"\x00\\]{2,30})"')
_NUL_RE = re.compile(rb"\x00([A-Z][^\x00]{2,30})(?=\x00)")


def _load_patcher():
    spec = importlib.util.spec_from_file_location(
        "patch_spinner_verbs", SCRIPT_DIR / "patch-spinner-verbs.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _gerundish(word: str) -> bool:
    if not (word.endswith("ing") or word.endswith("in'")):
        return False
    return all(c.isalpha() or c in "'-" for c in word)


def _extract(regex: re.Pattern, data: bytes) -> set[str]:
    found: set[str] = set()
    for m in regex.finditer(data):
        try:
            word = m.group(1).decode("utf-8")
        except UnicodeDecodeError:
            continue
        if _gerundish(word):
            found.add(word)
    return found


# 매핑된 verb 목록 — 모듈 로드 시 1회 계산
KNOWN_VERBS = frozenset(
    v for verbs in _load_patcher().EN_VERBS_BY_LENGTH.values() for v in verbs)


def find_unmapped(data: bytes) -> set[str]:
    """두 패턴 교집합 gerund 중 매핑에 없는 verb 집합."""
    candidates = _extract(_JSON_RE, data) & _extract(_NUL_RE, data)
    return candidates - KNOWN_VERBS - KNOWN_UNMAPPED


def main() -> int:
    parser = argparse.ArgumentParser(description="미매핑 spinner verb 감지")
    parser.add_argument("binary")
    parser.add_argument("--count", action="store_true",
                        help="미매핑 수만 stdout에 출력")
    args = parser.parse_args()

    binary_path = Path(args.binary).expanduser()
    if not binary_path.is_file():
        print(f"바이너리 없음: {binary_path}", file=sys.stderr)
        return 2

    unmapped = find_unmapped(binary_path.read_bytes())

    if args.count:
        print(len(unmapped))
        return 0

    print(f"unmapped={len(unmapped)}")
    for verb in sorted(unmapped):
        nbytes = len(verb.encode("utf-8"))
        print(f"  {verb} ({nbytes} bytes) — "
              f"EN_VERBS_BY_LENGTH[{nbytes}] 에 추가 후 백업 복원·재패치")
    if unmapped:
        print("\n반영 절차: MAPPING.md '풀을 직접 바꾸려면' 참고", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
