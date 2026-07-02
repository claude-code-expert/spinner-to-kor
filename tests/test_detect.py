#!/usr/bin/env python3
"""detect-verbs.py 단위 테스트 — 신규 verb 자동 감지 (FR-31).

계약:
  - 두 embed 패턴(JSON 경계 + NUL 경계) **모두**에 등장하는 gerund만 후보로 본다
    (일반 문자열 "Loading" 류 오탐 차단).
  - 매핑된 178개·의도적 제외("Doing")는 보고하지 않는다.
  - 패치 여부와 무관하게 동작 — 패치 후 남은 미매핑 영문도 잡는다.
  - --count 는 stdout에 숫자 1개만 (auto-patch 연동 계약).
"""
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DETECT = ROOT / "src" / "detect-verbs.py"

mf = importlib.util.spec_from_file_location("make_fixture", ROOT / "tests" / "make-fixture.py")
make_fixture = importlib.util.module_from_spec(mf)
mf.loader.exec_module(make_fixture)


def load_detect():
    spec = importlib.util.spec_from_file_location("detect_verbs", DETECT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class DetectTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = load_detect()
        cls.tmp = Path(tempfile.mkdtemp(prefix="spinner-detect-"))

    def unmapped_of(self, path):
        return self.d.find_unmapped(Path(path).read_bytes())

    def test_clean_fixture_has_no_unmapped(self):
        """기존 178개 verb 전부 '알려진 것'으로 인식 — 오탐 0."""
        bin_ = make_fixture.build_fixture(self.tmp / "clean")
        self.assertEqual(self.unmapped_of(bin_), set())

    def test_detects_new_verb(self):
        bin_ = make_fixture.build_fixture(self.tmp / "extra", extra_verbs=["Zooming"])
        self.assertEqual(self.unmapped_of(bin_), {"Zooming"})

    def test_detects_new_verb_after_patch(self):
        """패치 후에도 미매핑 verb는 영문으로 남아 감지된다."""
        bin_ = make_fixture.build_fixture(self.tmp / "extra-patched",
                                          extra_verbs=["Zooming"], patched=True)
        self.assertEqual(self.unmapped_of(bin_), {"Zooming"})

    def test_doing_is_intentionally_ignored(self):
        bin_ = make_fixture.build_fixture(self.tmp / "doing", extra_verbs=["Doing"])
        self.assertEqual(self.unmapped_of(bin_), set())

    def test_single_pattern_word_is_not_candidate(self):
        """한 패턴에만 등장하는 gerund(일반 코드 문자열)는 후보 아님."""
        bin_ = make_fixture.build_fixture(self.tmp / "single")
        data = bin_.read_bytes() + b'"OnlyJsonning" plain Loadinging \x00OnlyNulling\x00'
        self.assertEqual(self.d.find_unmapped(data), set())

    def test_non_gerund_boundary_word_ignored(self):
        bin_ = make_fixture.build_fixture(self.tmp / "nongerund")
        data = bin_.read_bytes() + b'"Version"\x00Version\x00'
        self.assertEqual(self.d.find_unmapped(data), set())

    def test_unicode_verb_detected(self):
        """Sautéing 류 비ASCII gerund도 처리 (기존 매핑엔 있으므로 신규만 확인)."""
        bin_ = make_fixture.build_fixture(self.tmp / "uni", extra_verbs=["Flambéeing"])
        self.assertEqual(self.unmapped_of(bin_), {"Flambéeing"})

    # ── CLI 계약 ─────────────────────────────────────────

    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(DETECT), *args],
                              capture_output=True, text=True)

    def test_cli_count_prints_single_int(self):
        bin_ = make_fixture.build_fixture(self.tmp / "cli", extra_verbs=["Zooming"])
        r = self.run_cli("--count", str(bin_))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), "1")

    def test_cli_report_lists_verb_and_bytes(self):
        bin_ = make_fixture.build_fixture(self.tmp / "cli2", extra_verbs=["Zooming"])
        r = self.run_cli(str(bin_))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Zooming", r.stdout)
        self.assertIn("7", r.stdout)  # byte 길이 안내

    def test_cli_missing_file_exit2_no_stdout(self):
        r = self.run_cli("--count", str(self.tmp / "nope"))
        self.assertEqual(r.returncode, 2)
        self.assertEqual(r.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
