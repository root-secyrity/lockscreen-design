#!/usr/bin/env python3
"""Integrity check for every lockscreen package in this repository.

Runs on the published tree only: no designs/, no pack.py. It proves that the
bytes a user would install are exactly the bytes the manifest describes.

Checks, per lockscreens/<id>/:
  manifest.json   schema 1, id matches the directory, destination is
                  qylock/themes/<id>, version present
  files[]         every source exists, size and sha256 match, mode is 0644-style,
                  destination is a safe relative path, install is a bool
  assets          every file under content/ and assets/ is declared in the
                  manifest (a forgotten asset fails instead of shipping)
  limits          no file over 5 MiB, no absolute home path, no U+2014
  registry.json   every entry resolves: path exists, version equals the manifest,
                  manifestSha256 equals the sha256 of manifest.json, official is
                  a bool, lastUpdated is YYYY-MM-DD, upstream is an https URL,
                  and every declared preview/screenshot exists

Exit 0 means clean. Any finding prints one line and exit is 1.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

MAX_FILE = 5 * 1024 * 1024
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
MODE = re.compile(r"^0[0-7]{3}$")
URL = re.compile(r"^https://[^\s/]+\.[^\s]+/\S+$")
TEXT_SUFFIX = {".qml", ".conf", ".desktop", ".txt", ".md", ".json", ".glsl",
               ".frag", ".vert", ".sh", ".yml", ".yaml", ""}

errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_relative(value: object) -> bool:
    if not isinstance(value, str) or not value:
        return False
    if value.startswith(("/", "\\")) or ".." in Path(value).parts:
        return False
    return "\\" not in value


def check_text(path: Path, rel: str) -> None:
    if path.suffix.lower() not in TEXT_SUFFIX:
        return
    try:
        body = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return
    if "\u2014" in body:
        fail(f"{rel}: contains U+2014 (em dash); use a plain hyphen")
    for line in body.splitlines():
        stripped = line.lstrip()
        if stripped.startswith(("//", "#", "*", "<!--")):
            continue
        if re.search(r"/(home|root)/[A-Za-z0-9._-]+", line) and "<user>" not in line:
            fail(f"{rel}: absolute home path in a non-comment line: {line.strip()[:80]}")


def check_package(pkg: Path) -> None:
    rel = pkg.as_posix()
    name = pkg.name
    manifest_path = pkg / "manifest.json"
    if not manifest_path.is_file():
        fail(f"{rel}: no manifest.json")
        return
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"{rel}/manifest.json: invalid JSON: {exc}")
        return

    if manifest.get("schema") != 1:
        fail(f"{rel}/manifest.json: schema must be 1")
    if manifest.get("id") != name:
        fail(f"{rel}/manifest.json: id {manifest.get('id')!r} does not match the directory {name!r}")
    if manifest.get("destination") != f"qylock/themes/{name}":
        fail(f"{rel}/manifest.json: destination must be qylock/themes/{name}")
    if not isinstance(manifest.get("version"), str) or not manifest["version"]:
        fail(f"{rel}/manifest.json: version missing")

    declared: set[str] = set()
    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        fail(f"{rel}/manifest.json: files[] is empty")
        return

    for item in files:
        if not isinstance(item, dict):
            fail(f"{rel}/manifest.json: files[] entry is not an object")
            continue
        source = str(item.get("source") or "")
        if not safe_relative(source):
            fail(f"{rel}/manifest.json: unsafe source {source!r}")
            continue
        declared.add(source)
        target = pkg / source
        if not target.is_file():
            fail(f"{rel}: manifest lists {source} but the file is missing")
            continue
        size = target.stat().st_size
        if size != item.get("size"):
            fail(f"{rel}/{source}: size {size} != manifest {item.get('size')}")
        digest = sha256(target)
        if digest != item.get("sha256"):
            fail(f"{rel}/{source}: sha256 {digest[:16]}... != manifest {str(item.get('sha256'))[:16]}...")
        if not MODE.match(str(item.get("mode", ""))):
            fail(f"{rel}/{source}: mode {item.get('mode')!r} is not 0NNN")
        if not isinstance(item.get("install"), bool):
            fail(f"{rel}/{source}: install must be true or false")
        if not safe_relative(str(item.get("destination") or "")):
            fail(f"{rel}/{source}: unsafe destination {item.get('destination')!r}")
        if size > MAX_FILE:
            fail(f"{rel}/{source}: {size} bytes is over the 5 MiB limit")
        check_text(target, f"{rel}/{source}")

    for folder in ("content", "assets"):
        root = pkg / folder
        if not root.is_dir():
            fail(f"{rel}: no {folder}/ directory")
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file():
                source = path.relative_to(pkg).as_posix()
                if source not in declared:
                    fail(f"{rel}: {source} exists but is not declared in manifest.json")

    for extra in ("LICENSE", "PROVENANCE.txt"):
        if not (pkg / extra).is_file():
            fail(f"{rel}: missing {extra}")


def check_registry(root: Path) -> None:
    reg_path = root / "lockscreens/registry.json"
    if not reg_path.is_file():
        fail("lockscreens/registry.json is missing")
        return
    try:
        registry = json.loads(reg_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"lockscreens/registry.json: invalid JSON: {exc}")
        return
    if registry.get("schema") != 1:
        fail("lockscreens/registry.json: schema must be 1")
    entries = registry.get("lockscreens")
    if not isinstance(entries, list) or not entries:
        fail("lockscreens/registry.json: lockscreens[] is empty")
        return

    seen: set[str] = set()
    for entry in entries:
        label = f"registry:{entry.get('id', '?')}"
        for field in ("id", "name", "version", "path", "author", "upstream",
                      "summary", "description", "tags", "accent", "surface",
                      "preview", "screenshots", "manifest", "manifestSha256"):
            if field not in entry:
                fail(f"{label}: missing {field}")
        ident = entry.get("id")
        if not isinstance(ident, str) or not re.match(r"^[a-z0-9]+(?:-[a-z0-9]+)*$", ident):
            fail(f"{label}: id is not lowercase-with-hyphens")
            continue
        if ident in seen:
            fail(f"{label}: duplicate entry")
        seen.add(ident)

        pkg = root / "lockscreens" / ident
        if not pkg.is_dir():
            fail(f"{label}: path does not exist")
            continue
        if entry.get("path") != f"lockscreens/{ident}":
            fail(f"{label}: path must be lockscreens/{ident}")

        manifest_path = pkg / str(entry.get("manifest", "manifest.json"))
        if not manifest_path.is_file():
            fail(f"{label}: manifest {entry.get('manifest')!r} does not exist")
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if entry.get("version") != manifest.get("version"):
            fail(f"{label}: registry version {entry.get('version')!r} != manifest {manifest.get('version')!r}")
        digest = sha256(manifest_path)
        if entry.get("manifestSha256") != digest:
            fail(f"{label}: manifestSha256 {str(entry.get('manifestSha256'))[:16]}... != {digest[:16]}...")
        if not HEX64.match(str(entry.get("manifestSha256", ""))):
            fail(f"{label}: manifestSha256 is not lowercase sha256")
        if not isinstance(entry.get("official"), bool):
            fail(f"{label}: official must be true or false")
        if not DATE.match(str(entry.get("lastUpdated", ""))):
            fail(f"{label}: lastUpdated must be YYYY-MM-DD")
        if not URL.match(str(entry.get("upstream", ""))):
            fail(f"{label}: upstream must be an https URL")
        media_all = [entry.get("preview")] + list(entry.get("screenshots") or [])
        for media in media_all:
            if not safe_relative(str(media or "")) or not (pkg / str(media)).is_file():
                fail(f"{label}: media {media!r} does not exist")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    packages = sorted(p for p in (root / "lockscreens").glob("*") if p.is_dir())
    if not packages:
        fail("lockscreens/ contains no package directories")
    for pkg in packages:
        check_package(pkg)
    check_registry(root)

    if errors:
        for line in errors:
            print(f"FAIL {line}")
        print(f"\n{len(errors)} problem(s) in {len(packages)} package(s).")
        return 1
    print(f"package integrity OK: {len(packages)} package(s) verified against their manifests.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
