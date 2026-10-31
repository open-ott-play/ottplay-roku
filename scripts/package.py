#!/usr/bin/env python3
"""Validate and reproducibly package the public Roku app, without a device."""

import argparse
import hashlib
import io
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = "ottplay-roku-sideload.zip"
TEXT_SUFFIXES = {".brs", ".xml", ".m3u"}
REQUIRED = {"manifest", "source/main.brs"}
MAX_PACKAGE_BYTES = 10 * 1024 * 1024


class PackageError(ValueError):
    pass


def allowed_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or any(p.startswith(".") for p in path.parts):
        return False
    if name == "manifest":
        return True
    if len(path.parts) < 2:
        return False
    suffix = path.suffix.lower()
    return (
        (path.parts[0] == "source" and suffix == ".brs")
        or (path.parts[0] == "components" and suffix in {".brs", ".xml"})
        or (path.parts[0] == "images" and suffix in {".png", ".jpg", ".jpeg", ".webp"})
        or (path.parts[0] == "fonts" and suffix in {".ttf", ".otf"})
        or (path.parts[0] == "data" and suffix == ".m3u")
    )


def read_files(app):
    files = {}
    for path in sorted(app.rglob("*")):
        if path.is_symlink():
            raise PackageError("Symlinks are not allowed in app/")
        if not path.is_file():
            continue
        name = path.relative_to(app).as_posix()
        if not allowed_path(name):
            raise PackageError(f"Unexpected app asset: {name}")
        data = path.read_bytes()
        if name == "manifest" or path.suffix.lower() in TEXT_SUFFIXES:
            text = data.decode("utf-8")
            if text.startswith("\ufeff"):
                raise PackageError(f"UTF-8 BOM is not allowed: {name}")
            data = text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
        files[name] = data
    if not REQUIRED.issubset(files):
        raise PackageError("app/ requires manifest and source/main.brs")
    if sum(map(len, files.values())) > MAX_PACKAGE_BYTES:
        raise PackageError("App exceeds the project package size budget")
    return files


def read_manifest(data):
    values = {}
    for line in data.decode("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise PackageError("Malformed manifest entry")
        key, value = (part.strip() for part in line.split("=", 1))
        if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_]*", key) or key in values:
            raise PackageError("Invalid or duplicate manifest key")
        values[key] = value
    for key in ("title", "major_version", "minor_version", "build_version", "ui_resolutions"):
        if not values.get(key):
            raise PackageError(f"Missing manifest field: {key}")
    for key in ("major_version", "minor_version", "build_version"):
        if not re.fullmatch(r"\d{1,5}", values[key]):
            raise PackageError(f"Invalid numeric manifest field: {key}")
    if values["ui_resolutions"] not in {"hd", "fhd", "hd,fhd", "fhd,hd"}:
        raise PackageError("Unexpected UI resolution")
    return values


def verify_reference(value, files, relative_to=None):
    if value.startswith("pkg:/"):
        name = value[5:]
    elif relative_to and not re.match(r"[a-zA-Z]+:", value):
        name = str(PurePosixPath(relative_to).parent / value)
    else:
        return
    if name not in files:
        raise PackageError(f"Missing package reference: {name}")


def validate(app=ROOT / "app", version=None, roku_build=None):
    files = read_files(app)
    manifest = read_manifest(files["manifest"])
    if version:
        match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.-]+)?", version)
        if not match or int(manifest["major_version"]) != int(match[1]) or int(manifest["minor_version"]) != int(match[2]):
            raise PackageError("Package version and Roku manifest major/minor disagree")
    if roku_build is not None and (not isinstance(roku_build, int) or isinstance(roku_build, bool) or roku_build < 1 or int(manifest["build_version"]) != roku_build):
        raise PackageError("package.json rokuBuild must match manifest build_version")
    component_names = set()
    for name, data in files.items():
        if name.endswith(".xml"):
            if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
                raise PackageError("External XML entities are not allowed")
            node = ElementTree.fromstring(data)
            if node.tag != "component" or not node.get("name") or not node.get("extends"):
                raise PackageError(f"Invalid SceneGraph component: {name}")
            component_name = node.get("name").lower()
            if component_name in component_names:
                raise PackageError("Duplicate SceneGraph component name")
            component_names.add(component_name)
            for child in node.iter():
                for attribute, value in child.attrib.items():
                    if attribute in {"uri", "fontUri", "posterUri"}:
                        verify_reference(value, files, name if child.tag == "script" else None)
        if name.endswith(".brs"):
            # Literal package references must be real assets. Dynamic URLs are runtime data.
            for value in re.findall(r'"(pkg:/[^"\r\n]+)"', data.decode("utf-8")):
                verify_reference(value, files)
    for value in manifest.values():
        if value.startswith("pkg:/"):
            verify_reference(value, files)
    return files, manifest


def archive_bytes(files):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, files[name])
    return buffer.getvalue()


def source_commit():
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=False)
    value = result.stdout.strip()
    return value if result.returncode == 0 and re.fullmatch(r"[0-9a-f]{40}", value) else None


def source_dirty():
    result = subprocess.run(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=ROOT, capture_output=True, text=True, check=False)
    return result.returncode != 0 or bool(result.stdout.strip())


def build(out=ROOT / "dist", verify=False):
    config = json.loads((ROOT / "package.json").read_text())
    version = config["version"]
    files, manifest = validate(version=version, roku_build=config["rokuBuild"])
    license_path = ROOT / "LICENSE"
    if license_path.is_symlink() or not license_path.is_file():
        raise PackageError("Root LICENSE is required and cannot be a symlink")
    files["LICENSE"] = license_path.read_text(encoding="utf-8").replace("\r\n", "\n").encode("utf-8")
    data = archive_bytes(files)
    if verify and data != archive_bytes(dict(reversed(list(files.items())))):
        raise PackageError("ZIP reproducibility failed")
    sha = hashlib.sha256(data).hexdigest()
    out.mkdir(parents=True, exist_ok=True)
    (out / ARTIFACT).write_bytes(data)
    (out / "SHA256SUMS").write_text(f"{sha}  {ARTIFACT}\n", encoding="utf-8", newline="\n")
    receipt = {
        "schema": 1,
        "version": version,
        "artifact": ARTIFACT,
        "format": "roku-sideload-zip",
        "sha256": sha,
        "bytes": len(data),
        "sourceCommit": source_commit(),
        "sourceDirty": source_dirty(),
        "manifestVersion": ".".join(manifest[k] for k in ("major_version", "minor_version", "build_version")),
        "signedPackage": False,
        "hardwareTested": False,
        "files": [{"path": name, "sha256": hashlib.sha256(files[name]).hexdigest()} for name in sorted(files)],
    }
    (out / "release.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Built {ARTIFACT}: {len(files)} files, {len(data)} bytes, SHA256 {sha}")
    if verify:
        print("Deterministic ZIP verified (sorted assets, fixed metadata, normalized text, no compression)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "build", "verify"])
    args = parser.parse_args()
    try:
        if args.command == "check":
            config = json.loads((ROOT / "package.json").read_text())
            files, _ = validate(version=config["version"], roku_build=config["rokuBuild"])
            print(f"Package structure verified: {len(files)} public app assets")
        else:
            build(verify=args.command == "verify")
    except (PackageError, UnicodeError, ElementTree.ParseError) as error:
        print(f"Package validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
