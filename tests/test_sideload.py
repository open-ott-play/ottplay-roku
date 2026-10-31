import importlib.util
import contextlib
import io
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "sideload.py"
SPEC = importlib.util.spec_from_file_location("roku_sideload", SCRIPT)
sideload = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sideload)


class SideloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / "app.zip"
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("manifest", "title=Test")
            archive.writestr("source/main.brs", "sub Main()\nend sub")

    def test_explicit_host_rejects_urls_credentials_ports_and_shell_characters(self):
        for host in ("", " http://roku.local", "http://roku.local", "user:pass@roku.local", "roku.local:80", "roku.local/x", "roku.local\nother", "a;cmd", "a..local"):
            self.assertFalse(sideload.valid_host(host), host)
        for host in ("192.168.1.123", "roku.local", "roku", "::1"):
            self.assertTrue(sideload.valid_host(host), host)

    def test_missing_credentials_never_attempt_network(self):
        with patch.object(sideload.urllib.request, "build_opener") as opener:
            with self.assertRaises(ValueError):
                sideload.install("roku.local", "", Path("unused.zip"))
            opener.assert_not_called()

    def test_redirect_is_never_followed(self):
        request = sideload.urllib.request.Request("http://roku.local/plugin_install")
        with self.assertRaises(sideload.urllib.error.HTTPError) as caught:
            sideload.NoRedirect().redirect_request(request, None, 302, "Found", {}, "http://other.local/")
        caught.exception.close()

    def test_multipart_has_fixed_safe_filename_and_preserves_archive_bytes(self):
        data = b"PK\x00\xfftest"
        boundary, body = sideload.make_body(data)
        self.assertIn(b'name="mysubmit"\r\n\r\nInstall', body)
        self.assertIn(b'filename="ottplay-roku-sideload.zip"', body)
        self.assertIn(data, body)
        self.assertTrue(body.endswith(f"--{boundary}--\r\n".encode()))

    def test_http_200_upload_receipt_does_not_mean_install_success(self):
        for response in (b"Application Received", b"Application Received: Install Failure: Compilation Failed", b"Install Success. Compilation Failed"):
            opener = Mock()
            opener.open.return_value = io.BytesIO(response)
            with patch.object(sideload.urllib.request, "build_opener", return_value=opener):
                with self.assertRaisesRegex(ValueError, "did not confirm"):
                    sideload.install("roku.local", "test-secret", self.archive)

    def test_success_disables_proxy_and_never_places_password_in_request(self):
        opener = Mock()
        opener.open.return_value = io.BytesIO(b"<p>Install Success.</p>")
        output = io.StringIO()
        with patch.object(sideload.urllib.request, "build_opener", return_value=opener) as build:
            with contextlib.redirect_stdout(output):
                sideload.install("roku.local", "test-secret", self.archive)
        handlers = build.call_args.args
        self.assertEqual(handlers[0].proxies, {})
        self.assertIsInstance(handlers[2], sideload.NoRedirect)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, "http://roku.local/plugin_install")
        self.assertNotIn("test-secret", str(request.headers))
        self.assertNotIn(b"test-secret", request.data)
        self.assertNotIn("test-secret", output.getvalue())
        self.assertIn("Install Success", output.getvalue())

    def test_identical_package_is_reported_as_no_change(self):
        opener = Mock()
        opener.open.return_value = io.BytesIO(b"Application is Identical to previous version")
        output = io.StringIO()
        with patch.object(sideload.urllib.request, "build_opener", return_value=opener):
            with contextlib.redirect_stdout(output):
                sideload.install("roku.local", "test-secret", self.archive)
        self.assertIn("no change", output.getvalue())


if __name__ == "__main__":
    unittest.main()
