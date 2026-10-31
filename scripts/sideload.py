#!/usr/bin/env python3
"""Opt-in install of the unsigned development ZIP on one explicitly named Roku."""

import argparse
import ipaddress
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def valid_host(value):
    if not value or value != value.strip():
        return False
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return len(value) <= 253 and all(
            re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
            for label in value.split(".")
        )


def make_body(data):
    boundary = "ottplay-" + uuid.uuid4().hex
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"mysubmit\"\r\n\r\nInstall\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"archive\"; filename=\"ottplay-roku-sideload.zip\"\r\n"
        "Content-Type: application/zip\r\n\r\n"
    ).encode("ascii") + data + f"\r\n--{boundary}--\r\n".encode("ascii")
    return boundary, body


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, "Redirect refused", headers, fp)


def install(host, password, archive):
    if not valid_host(host) or not password or "\r" in password or "\n" in password:
        raise ValueError("Set valid ROKU_HOST and ROKU_PASSWORD environment variables")
    if not archive.is_file() or archive.stat().st_size > 10 * 1024 * 1024:
        raise ValueError("Build the sideload ZIP first (maximum 10 MiB)")
    with zipfile.ZipFile(archive) as check:
        names = check.namelist()
        if "manifest" not in names or "source/main.brs" not in names:
            raise ValueError("ZIP must have manifest and source/main.brs at its root")
    authority = f"[{host}]" if ":" in host else host
    url = f"http://{authority}/plugin_install"
    passwords = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    passwords.add_password(None, url, "rokudev", password)
    # Developer installer is a local HTTP endpoint. Never route its credentials through
    # an environment proxy or follow a redirect to another host.
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}), urllib.request.HTTPDigestAuthHandler(passwords), NoRedirect()
    )
    boundary, body = make_body(archive.read_bytes())
    request = urllib.request.Request(url, data=body, headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with opener.open(request, timeout=30) as response:
        payload = response.read(1024 * 1024 + 1)
    if len(payload) > 1024 * 1024:
        raise ValueError("Unexpectedly large installer response")
    text = payload.decode("utf-8", errors="replace")
    if re.search(r"Install\s+Failure|Compilation\s+Failed", text, re.IGNORECASE) or not re.search(r"Install\s+Success|Identical\s+to\s+previous", text, re.IGNORECASE):
        raise ValueError("Installer did not confirm success; inspect the device's developer page")
    if re.search(r"Identical\s+to\s+previous", text, re.IGNORECASE):
        print("Developer installer reports an identical package; no change was installed.")
    else:
        print("Developer installer confirmed Install Success. Verify startup and playback on the Roku.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm", action="store_true", help="replace the selected device's existing sideloaded app")
    parser.add_argument("--archive", type=Path, default=ROOT / "dist" / "ottplay-roku-sideload.zip")
    args = parser.parse_args()
    if not args.confirm:
        parser.error("--confirm is required; this replaces the device's existing sideloaded app")
    try:
        install(os.environ.get("ROKU_HOST", ""), os.environ.get("ROKU_PASSWORD", ""), args.archive)
    except urllib.error.HTTPError as error:
        print(f"Sideload failed: installer HTTP {error.code}", file=sys.stderr)
        return 1
    except (urllib.error.URLError, TimeoutError, OSError, zipfile.BadZipFile):
        print("Sideload failed: could not complete the direct developer-installer request", file=sys.stderr)
        return 1
    except ValueError as error:
        print(f"Sideload failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
