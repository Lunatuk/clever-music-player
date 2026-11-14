import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from release_version import AppVersion, bump_file, read_version, verify_android, verify_windows


class ReleaseVersionTest(unittest.TestCase):
    def test_rejects_ambiguous_or_unrepresentable_versions(self):
        for invalid in ("1.2.3", "01.2.3+4", "1.2.3-beta+4", "1.2.3+0",
                        "1.2.3+65536", "65536.0.0+1", "1.2.3+-1", "1.2.3+4extra"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                AppVersion.parse(invalid)

    def test_bump_resets_smaller_components_and_always_increments_build(self):
        current = AppVersion.parse("0.3.9+2065")
        self.assertEqual(str(current.bump("patch")), "0.3.10+2066")
        self.assertEqual(str(current.bump("minor")), "0.4.0+2066")
        self.assertEqual(str(current.bump("major")), "1.0.0+2066")
        with self.assertRaises(ValueError):
            AppVersion.parse("1.0.0+65535").bump("patch")

    def test_release_cannot_reuse_version_or_downgrade_android_code(self):
        current = AppVersion.parse("0.3.0+2065")
        for previous in ("0.3.0+2064", "0.2.9+2065", "0.4.0+2064", "0.2.9+2066"):
            with self.subTest(previous=previous), self.assertRaises(ValueError):
                current.require_newer_than(AppVersion.parse(previous))
        current.require_newer_than(AppVersion.parse("0.2.1", legacy=True))
        current.require_newer_than(AppVersion.parse("0.2.1+2063"))

    def test_requires_one_top_level_version(self):
        for invalid in ("name: test\n", "  version: 1.0.0+1\n",
                        "version: 1.0.0+1\nversion: 2.0.0+2\n"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                read_version(invalid)

    def test_bump_preserves_other_fields_comments_and_line_endings(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pubspec.yaml"
            before = b"name: example\r\nversion: 0.3.9+2065 # release\r\ndependencies: {}\r\n"
            path.write_bytes(before)
            bump_file(path, "minor")
            self.assertEqual(path.read_bytes(), before.replace(b"0.3.9+2065", b"0.4.0+2066"))

    def test_invalid_bump_leaves_file_intact(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pubspec.yaml"
            before = b"version: 0.3.0+65535\n"
            path.write_bytes(before)
            with self.assertRaises(ValueError):
                bump_file(path, "patch")
            self.assertEqual(path.read_bytes(), before)

    @patch("release_version.output")
    def test_android_detects_split_abi_offset_and_stale_version(self, output):
        version = AppVersion.parse("0.3.0+2065")
        for name, code in (("0.3.0", "4065"), ("0.2.1", "2065")):
            output.return_value = f"package: name='test' versionCode='{code}' versionName='{name}'\n"
            with self.subTest(name=name, code=code), self.assertRaises(ValueError):
                verify_android(version, Path("test.apk"), "aapt")
        output.return_value = "package: name='test' versionCode='2065' versionName='0.3.0'\n"
        self.assertEqual(verify_android(version, Path("test.apk"), "aapt")["versionCode"], "2065")

    @patch("release_version.output")
    def test_windows_checks_numeric_and_display_versions(self, output):
        version = AppVersion.parse("0.3.0+2065")
        output.return_value = ('{"file":[0,3,0,2065],"product":[0,3,0,2065],'
                               '"fileString":"0.3.0+2065","productString":"0.3.0+2065"}')
        verify_windows(version, Path("test.exe"))
        output.return_value = output.return_value.replace('"product":[0,3,0,2065]', '"product":[0,2,1,63]')
        with self.assertRaises(ValueError):
            verify_windows(version, Path("test.exe"))


if __name__ == "__main__":
    unittest.main()
