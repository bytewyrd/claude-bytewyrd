#!/usr/bin/env python3
"""Rebuild scripts/_vendor/yaml/ and scripts/_vendor/PyYAML-LICENSE from the
PyYAML sdist that uv.lock pins, or, with --check, compare them both ways and
change nothing (RFC 2026-11-09-scaffold-and-drift, D9). Standard library only.

Usage: vendor-pyyaml.py [--check] [--root DIR]

uv.lock must hold one pyyaml package, from PyPI, and pyproject.toml's dev
group must pin exactly its version. The sdist's size and sha256 are checked
against uv.lock before anything is read from it; then only its regular files
directly under lib/yaml/, and LICENSE, are read, and nothing is extracted. A
link, a device or an unsafe path anywhere in it fails the run. --check skips
__pycache__. --root defaults to the repository that holds this script.

Exit status: 0 when the copy matches or was rebuilt, 1 otherwise.
"""

import argparse
import hashlib
import io
import os
import re
import shutil
import sys
import tarfile
import tempfile
import tomllib
import urllib.request
from pathlib import Path

PYPI = "https://pypi.org/simple"
FILES = "https://files.pythonhosted.org/packages/"


class VendorError(Exception):
    """A check failed; the message says which."""


def locked_sdist(root):
    """PyYAML's version and its sdist's URL, sha256 (hex) and size, from ROOT's uv.lock."""
    lock = tomllib.loads((root / "uv.lock").read_text(encoding="utf-8"))
    found = [p for p in lock.get("package", []) if p.get("name") == "pyyaml"]
    if len(found) != 1 or found[0].get("source") != {"registry": PYPI}:
        raise VendorError("uv.lock must hold exactly one pyyaml package, from %s" % PYPI)
    version, sdist = found[0].get("version"), found[0].get("sdist") or {}
    url, digest, size = sdist.get("url"), sdist.get("hash"), sdist.get("size")
    tail = "/pyyaml-%s.tar.gz" % version
    if not (isinstance(version, str) and isinstance(url, str) and url.startswith(FILES) and url.endswith(tail)):
        raise VendorError("uv.lock's pyyaml sdist url %r is not under %s or does not end in %s" % (url, FILES, tail))
    if not (isinstance(digest, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", digest)):
        raise VendorError("uv.lock's pyyaml sdist hash %r is not sha256:<64 hex digits>" % (digest,))
    if not (isinstance(size, int) and size > 0):
        raise VendorError("uv.lock's pyyaml sdist size %r is not a byte count" % (size,))
    dev = tomllib.loads((root / "pyproject.toml").read_text(encoding="utf-8")).get("dependency-groups", {}).get("dev")
    pins = [d for d in dev or [] if isinstance(d, str) and re.match(r"(?i)pyyaml\s*([\[<>=!~;@]|$)", d)]
    if pins != ["pyyaml==" + version]:
        raise VendorError("pyproject.toml's dev group pins %r, not exactly pyyaml==%s" % (pins, version))
    return version, url, digest[len("sha256:") :], size


def fetch(url, limit):
    """At most LIMIT bytes of URL's body."""
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read(limit)


def sdist_files(data, version):
    """The vendored files in the sdist DATA, as {path under scripts/_vendor: bytes}."""
    top, files = "pyyaml-%s/" % version, {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for member in tar:
            name = member.name
            if name.startswith("/") or ".." in name.split("/"):
                raise VendorError("the sdist holds an unsafe path: %r" % name)
            if not (member.isreg() or member.isdir()):
                raise VendorError("the sdist holds %r, which is not a regular file or a directory" % name)
            rest = name[len(top + "lib/yaml/") :] if name.startswith(top + "lib/yaml/") else ""
            if member.isreg() and name == top + "LICENSE":
                files["PyYAML-LICENSE"] = tar.extractfile(member).read()
            elif member.isreg() and rest and "/" not in rest:
                files["yaml/" + rest] = tar.extractfile(member).read()
    if "PyYAML-LICENSE" not in files or len(files) == 1:
        raise VendorError("the sdist lacks %sLICENSE or the files of %slib/yaml/" % (top, top))
    return files


def differences(vendor, want):
    """One line per file of WANT missing from VENDOR, extra in it, or different there."""
    have = {}
    if (vendor / "PyYAML-LICENSE").is_file():
        have["PyYAML-LICENSE"] = (vendor / "PyYAML-LICENSE").read_bytes()
    for directory, subdirectories, names in os.walk(vendor / "yaml"):
        subdirectories[:] = [d for d in subdirectories if d != "__pycache__"]
        for name in names:
            path = Path(directory, name)
            have[path.relative_to(vendor).as_posix()] = path.read_bytes()
    lines = [(p, "is missing; the sdist has it") for p in want.keys() - have.keys()]
    lines += [(p, "is not in the sdist") for p in have.keys() - want.keys()]
    lines += [(p, "differs from the sdist's") for p in want.keys() & have.keys() if want[p] != have[p]]
    return ["scripts/_vendor/%s %s" % line for line in sorted(lines)]


def rebuild(vendor, files):
    """Write FILES to a temporary directory in VENDOR, swap them into place, and remove the old copy."""
    vendor.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".vendor-pyyaml-", dir=vendor))
    try:
        for rel, data in files.items():
            (temporary / rel).parent.mkdir(parents=True, exist_ok=True)
            (temporary / rel).write_bytes(data)
        if os.path.lexists(vendor / "yaml"):
            os.rename(vendor / "yaml", temporary / "stale-yaml")
        os.rename(temporary / "yaml", vendor / "yaml")
        os.replace(temporary / "PyYAML-LICENSE", vendor / "PyYAML-LICENSE")
    finally:
        shutil.rmtree(temporary)


def main(argv=None, fetch=fetch):
    parser = argparse.ArgumentParser(description="Rebuild, or check, the vendored PyYAML from uv.lock's sdist.")
    parser.add_argument("--check", action="store_true", help="compare both ways and change nothing")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2], help="the repository root")
    args = parser.parse_args(argv)
    vendor = args.root / "scripts" / "_vendor"
    try:
        version, url, digest, size = locked_sdist(args.root)
        data = fetch(url, size + 1)
        got = hashlib.sha256(data).hexdigest()
        if (len(data), got) != (size, digest):
            raise VendorError("%s: read %d bytes, sha256 %s; uv.lock has %d, %s" % (url, len(data), got, size, digest))
        want, sdist = sdist_files(data, version), "pyyaml-%s.tar.gz" % version
        if not args.check:
            rebuild(vendor, want)
            print("rebuilt scripts/_vendor from %s" % sdist)
            return 0
        problems = differences(vendor, want)
    except (VendorError, OSError, ValueError, tarfile.TarError) as e:
        print("vendor-pyyaml: %s" % e, file=sys.stderr)
        return 1
    for line in problems:
        print("vendor-pyyaml: %s" % line, file=sys.stderr)
    if problems:
        print("vendor-pyyaml: run .github/scripts/vendor-pyyaml.py to rebuild from %s" % sdist, file=sys.stderr)
        return 1
    print("scripts/_vendor matches %s" % sdist)
    return 0


if __name__ == "__main__":
    sys.exit(main())
