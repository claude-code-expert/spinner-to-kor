#!/usr/bin/env python3
"""patch-spinner-verbs.py 단위 테스트.

대상 요구사항·버그: FR-01/03/07/21/23, BUG-01(간접)/03/05
실행: python3 -m unittest tests.test_patch  (또는 tests/run.sh)
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PY_SCRIPT = ROOT / "src" / "patch-spinner-verbs.py"

sys.path.insert(0, str(ROOT / "tests"))
mf = importlib.util.spec_from_file_location("make_fixture", ROOT / "tests" / "make-fixture.py")
make_fixture = importlib.util.module_from_spec(mf)
mf.loader.exec_module(make_fixture)


def load_module():
    spec = importlib.util.spec_from_file_location("patch_spinner_verbs", PY_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TestMapping(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load_module()

    def test_validate_map_passes(self):
        self.m.validate_map()  # 불일치 시 sys.exit(2)

    def test_verb_count_is_178(self):
        self.assertEqual(len(self.m.VERB_MAP), 178)

    def test_byte_length_invariant(self):
        for en, ko in self.m.VERB_MAP.items():
            self.assertEqual(len(en.encode()), len(ko.encode()), f"{en} → {ko}")

    def test_sentinels_are_mapped_verbs(self):
        """FR-07: 다중 sentinel — 정의가 존재하고 전부 실제 verb여야 한다."""
        self.assertGreaterEqual(len(self.m.SENTINEL_VERBS), 3)
        for s in self.m.SENTINEL_VERBS:
            self.assertIn(s, self.m.VERB_MAP)


class TestPatchBinary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load_module()

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="spinner-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.bin = make_fixture.build_fixture(self.tmp / "2.1.170")
        self.original = self.bin.read_bytes()

    def test_patch_preserves_size(self):
        self.m.patch_binary(self.bin)
        self.assertEqual(len(self.bin.read_bytes()), len(self.original))

    def test_patch_removes_all_english_verbs(self):
        self.m.patch_binary(self.bin)
        data = self.bin.read_bytes()
        for en in self.m.VERB_MAP:
            b = en.encode()
            self.assertNotIn(b'"' + b + b'"', data, en)
            self.assertNotIn(b"\x00" + b + b"\x00", data, en)

    def test_patch_inserts_korean(self):
        self.m.patch_binary(self.bin)
        data = self.bin.read_bytes()
        self.assertIn("추론중".encode(), data)

    def test_decoys_untouched(self):
        """경계 패턴 밖 부분 일치는 절대 치환 금지."""
        self.m.patch_binary(self.bin)
        data = self.bin.read_bytes()
        for decoy in make_fixture.DECOYS:
            self.assertIn(decoy, data)

    def test_count_english_verbs(self):
        """FR-07: sentinel 카운트 — 미패치>0, 패치 후 0."""
        self.assertGreater(self.m.count_english_verbs(self.original), 0)
        self.m.patch_binary(self.bin)
        self.assertEqual(self.m.count_english_verbs(self.bin.read_bytes()), 0)

    def test_count_survives_missing_single_sentinel(self):
        """FR-07: sentinel 1개가 verb 목록에서 사라져도 감지 유지."""
        first = self.m.SENTINEL_VERBS[0]
        nobin = make_fixture.build_fixture(self.tmp / "no-first", omit=(first,))
        self.assertGreater(self.m.count_english_verbs(nobin.read_bytes()), 0)


class TestAutodetect(unittest.TestCase):
    """BUG-03: 백업(.bak.<ts>)·.tmp·숨김 파일을 활성 바이너리로 오탐 금지."""

    def setUp(self):
        self.m = load_module()
        self.tmp = Path(tempfile.mkdtemp(prefix="spinner-home-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.tmp)
        self.addCleanup(self._restore_home)
        self.versions = self.tmp / ".local" / "share" / "claude" / "versions"
        self.versions.mkdir(parents=True)

    def _restore_home(self):
        os.environ["HOME"] = self.old_home

    def test_skips_bak_tmp_hidden(self):
        real = self.versions / "2.1.170"
        real.write_bytes(b"real")
        # 백업이 mtime상 더 최신이어도 선택되면 안 된다
        (self.versions / "2.1.170.bak.20990101-000000").write_bytes(b"bak")
        (self.versions / "2.1.170.tmp").write_bytes(b"tmp")
        (self.versions / ".hidden").write_bytes(b"hidden")
        detected = self.m.autodetect_binary()
        self.assertEqual(detected, real.resolve())

    def test_only_backups_present_exits(self):
        (self.versions / "2.1.170.bak.20260101-000000").write_bytes(b"bak")
        with self.assertRaises(SystemExit):
            self.m.autodetect_binary()


class TestBackupPolicy(unittest.TestCase):
    """BUG-05: 백업 보존 정책 — 가장 오래된(깨끗한 원본) + 최신만 유지."""

    def setUp(self):
        self.m = load_module()
        self.tmp = Path(tempfile.mkdtemp(prefix="spinner-bak-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.bin = self.tmp / "2.1.170"
        self.bin.write_bytes(b"bin")

    def test_prune_keeps_oldest_and_newest(self):
        stamps = ["20260101-000000", "20260201-000000", "20260301-000000",
                  "20260401-000000", "20260501-000000"]
        for s in stamps:
            (self.tmp / f"2.1.170.bak.{s}").write_bytes(s.encode())
        removed = self.m.prune_backups(self.bin)
        remaining = sorted(p.name for p in self.tmp.glob("2.1.170.bak.*"))
        self.assertEqual(remaining, ["2.1.170.bak.20260101-000000",
                                     "2.1.170.bak.20260501-000000"])
        self.assertEqual(len(removed), 3)

    def test_prune_noop_when_two_or_fewer(self):
        (self.tmp / "2.1.170.bak.20260101-000000").write_bytes(b"a")
        (self.tmp / "2.1.170.bak.20260201-000000").write_bytes(b"b")
        self.assertEqual(self.m.prune_backups(self.bin), [])
        self.assertEqual(len(list(self.tmp.glob("2.1.170.bak.*"))), 2)

    def test_prune_ignores_other_binaries_backups(self):
        for s in ["20260101-000000", "20260201-000000", "20260301-000000"]:
            (self.tmp / f"2.1.170.bak.{s}").write_bytes(b"x")
        other = self.tmp / "2.1.171.bak.20260101-000000"
        other.write_bytes(b"other")
        self.m.prune_backups(self.bin)
        self.assertTrue(other.exists())


class TestOverlayAndStyle(unittest.TestCase):
    """FR-32 커스텀 매핑 오버레이 + FR-33 스타일 프리셋.

    계약:
      - ~/.claude/spinner-map.json (SPINNER_MAP_FILE 로 재지정 가능):
        {"pools": {"9": [...]}, "overrides": {"Pondering": "궁리중"}}
      - byte 불변식은 오버레이에도 동일 강제 — 위반 시 exit 2, 바이너리 무변경.
      - --style witty 는 위트 1:1 매핑(구버전 보존본)으로 패치.
    """

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="spinner-ov-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.bin = make_fixture.build_fixture(self.tmp / "2.1.170")
        self.fakebin = self.tmp / "fakebin"
        self.fakebin.mkdir()
        cs = self.fakebin / "codesign"
        cs.write_text("#!/bin/sh\nexit 0\n")
        cs.chmod(0o755)

    def run_py(self, *args, overlay=None, style=None):
        env = dict(os.environ, PATH=f"{self.fakebin}:{os.environ['PATH']}")
        if overlay is not None:
            ov = self.tmp / "spinner-map.json"
            ov.write_text(overlay)
            env["SPINNER_MAP_FILE"] = str(ov)
        else:
            env["SPINNER_MAP_FILE"] = str(self.tmp / "no-overlay.json")
        if style:
            env["SPINNER_STYLE"] = style
        return subprocess.run([sys.executable, str(PY_SCRIPT), *args],
                              capture_output=True, text=True, env=env)

    def test_overlay_pool_replaces_labels(self):
        overlay = '{"pools": {"9": ["탐색중", "추리중"]}}'
        r = self.run_py(str(self.bin), overlay=overlay)
        self.assertEqual(r.returncode, 0, r.stderr)
        data = self.bin.read_bytes()
        self.assertIn("탐색중".encode(), data)
        self.assertNotIn("준비중".encode(), data)  # 기본 9B 풀은 사용 안 됨

    def test_overlay_override_pins_single_verb(self):
        overlay = '{"overrides": {"Pondering": "궁리중"}}'
        r = self.run_py(str(self.bin), overlay=overlay)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("궁리중".encode(), self.bin.read_bytes())

    def test_overlay_invariant_violation_rejected(self):
        """9B 풀에 12B 라벨 → exit 2 + 바이너리 무변경."""
        before = self.bin.read_bytes()
        overlay = '{"pools": {"9": ["너무긴라벨"]}}'
        r = self.run_py(str(self.bin), overlay=overlay)
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.bin.read_bytes(), before)

    def test_overlay_unknown_override_key_rejected(self):
        """오타 방어 — 존재하지 않는 verb override는 거부."""
        before = self.bin.read_bytes()
        overlay = '{"overrides": {"Ponderingg": "궁리중"}}'
        r = self.run_py(str(self.bin), overlay=overlay)
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.bin.read_bytes(), before)

    def test_overlay_broken_json_rejected(self):
        before = self.bin.read_bytes()
        r = self.run_py(str(self.bin), overlay='{broken!!')
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.bin.read_bytes(), before)

    def test_witty_style_env(self):
        r = self.run_py(str(self.bin), style="witty")
        self.assertEqual(r.returncode, 0, r.stderr)
        data = self.bin.read_bytes()
        self.assertIn("사색중".encode(), data)   # Pondering
        self.assertIn("춤추기".encode(), data)   # Boogieing

    def test_witty_style_cli_flag(self):
        r = self.run_py("--style", "witty", str(self.bin))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("소용돌이".encode(), self.bin.read_bytes())  # Whirlpooling

    def test_witty_map_satisfies_invariant(self):
        """위트 178개 전부 byte 길이 일치 — 전수 검증."""
        m = load_module()
        witty = m.build_verb_map(style="witty")
        self.assertEqual(len(witty), 178)
        for en, ko in witty.items():
            self.assertEqual(len(en.encode()), len(ko.encode()), f"{en} → {ko!r}")

    def test_check_unaffected_by_style(self):
        r = self.run_py("--check", str(self.bin), style="witty")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertGreater(int(r.stdout.strip()), 0)


class TestCli(unittest.TestCase):
    """CLI 계약: --check(조회 전용), 패치 skip, 서명 실패 자동 복구."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="spinner-cli-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.bin = make_fixture.build_fixture(self.tmp / "2.1.170")
        self.fakebin = self.tmp / "fakebin"
        self.fakebin.mkdir()

    def run_py(self, *args, codesign_exit=0):
        """PATH 앞에 가짜 codesign을 놓고 CLI 실행 (실기 서명 없이 검증)."""
        cs = self.fakebin / "codesign"
        cs.write_text(f"#!/bin/sh\nexit {codesign_exit}\n")
        cs.chmod(0o755)
        env = dict(os.environ, PATH=f"{self.fakebin}:{os.environ['PATH']}")
        return subprocess.run([sys.executable, str(PY_SCRIPT), *args],
                              capture_output=True, text=True, env=env)

    def test_check_reports_count_and_never_modifies(self):
        before = self.bin.read_bytes()
        r = self.run_py("--check", str(self.bin))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertGreater(int(r.stdout.strip()), 0)
        self.assertEqual(self.bin.read_bytes(), before)
        self.assertEqual(list(self.tmp.glob("*.bak.*")), [])

    def test_check_zero_after_patch(self):
        r = self.run_py(str(self.bin))
        self.assertEqual(r.returncode, 0, r.stderr)
        r2 = self.run_py("--check", str(self.bin))
        self.assertEqual(r2.stdout.strip(), "0")

    def test_check_missing_file_exit2_no_stdout(self):
        """BUG-01 계열 방지: 실패 시 stdout에 숫자 출력 금지 (이중 출력 차단)."""
        r = self.run_py("--check", str(self.tmp / "nope"))
        self.assertEqual(r.returncode, 2)
        self.assertEqual(r.stdout.strip(), "")

    def test_patch_skips_already_patched_without_backup(self):
        self.run_py(str(self.bin))
        baks_before = sorted(self.tmp.glob("*.bak.*"))
        r = self.run_py(str(self.bin))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(self.tmp.glob("*.bak.*")), baks_before)

    def test_sign_failure_restores_original(self):
        """NFR-04: 재서명 실패 시 원본 자동 복구 — claude 사용 불능 상태 금지."""
        original = self.bin.read_bytes()
        r = self.run_py(str(self.bin), codesign_exit=1)
        self.assertEqual(r.returncode, 3)
        self.assertEqual(self.bin.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
