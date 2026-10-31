import importlib.util
import io
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "package.py"
SPEC = importlib.util.spec_from_file_location("roku_package", SCRIPT)
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name)
        self.write("manifest", "title=Test\nmajor_version=0\nminor_version=1\nbuild_version=1\nui_resolutions=hd\n")
        self.write("source/main.brs", "sub Main()\nend sub\n")
        self.write("components/Test.xml", '<component name="Test" extends="Scene"><script uri="pkg:/source/main.brs" /></component>')

    def write(self, name, content):
        path = self.app / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="")

    def test_deterministic_zip_has_root_manifest_fixed_metadata_and_sorted_files(self):
        files, _ = package.validate(self.app, "0.1.0-beta.1")
        first = package.archive_bytes(files)
        self.assertEqual(first, package.archive_bytes(dict(reversed(list(files.items())))))
        with zipfile.ZipFile(io.BytesIO(first)) as archive:
            self.assertEqual(archive.namelist(), sorted(files))
            self.assertIn("manifest", archive.namelist())
            self.assertNotIn("app/manifest", archive.namelist())
            for entry in archive.infolist():
                self.assertEqual(entry.date_time, (1980, 1, 1, 0, 0, 0))
                self.assertEqual(entry.compress_type, zipfile.ZIP_STORED)
                self.assertEqual(entry.external_attr >> 16, 0o100644)

    def test_windows_line_endings_produce_identical_archive(self):
        baseline, _ = package.validate(self.app)
        for path in self.app.rglob("*"):
            if path.is_file():
                path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
        windows, _ = package.validate(self.app)
        self.assertEqual(package.archive_bytes(baseline), package.archive_bytes(windows))

    def test_rejects_unexpected_private_file(self):
        self.write(".env", "SECRET=not-public")
        with self.assertRaises(package.PackageError):
            package.validate(self.app)

    def test_rejects_symlink_even_when_target_is_allowed(self):
        (self.app / "source" / "alias.brs").symlink_to(self.app / "source" / "main.brs")
        with self.assertRaisesRegex(package.PackageError, "Symlinks"):
            package.validate(self.app)

    def test_rejects_missing_asset(self):
        self.write("components/Test.xml", '<component name="Test" extends="Scene"><Poster uri="pkg:/images/missing.png" /></component>')
        with self.assertRaisesRegex(package.PackageError, "Missing package reference"):
            package.validate(self.app)

    def test_rejects_external_xml_entities(self):
        self.write("components/Test.xml", '<!DOCTYPE component [<!ENTITY secret SYSTEM "file:///private">]><component name="Test" extends="Scene"/>')
        with self.assertRaisesRegex(package.PackageError, "External XML"):
            package.validate(self.app)

    def test_rejects_duplicate_manifest_and_version_mismatch(self):
        with self.assertRaisesRegex(package.PackageError, "disagree"):
            package.validate(self.app, "1.0.0")
        with (self.app / "manifest").open("a") as handle:
            handle.write("title=Other\n")
        with self.assertRaisesRegex(package.PackageError, "duplicate"):
            package.validate(self.app)

    def test_release_allowlist_excludes_tests_dependencies_and_parent_paths(self):
        for name in ("../manifest", "/manifest", "tests/test.brs", "node_modules/a.brs", "source/.secret.brs", "README.md", "source/app.bs"):
            self.assertFalse(package.allowed_path(name), name)

    def test_explicit_monotonic_build_number_must_match_manifest(self):
        package.validate(self.app, "0.1.0-beta.1", 1)
        for build in (0, 2, True, "1"):
            with self.assertRaisesRegex(package.PackageError, "rokuBuild"):
                package.validate(self.app, "0.1.0-beta.2", build)


if __name__ == "__main__":
    unittest.main()
