#!/usr/bin/env python3
"""Export a self-contained Windows evaluator with exact source/build identity.

Use an official Godot 4.7.2 editor and verified matching export templates.
This script never downloads an unpinned runtime or includes host user data.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

GODOT_VERSION = "4.7.2.stable"


def run(command: list[str], *, cwd: Path) -> None:
    result = subprocess.run(command, cwd=cwd, text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="")
    if result.returncode or any(token in result.stdout for token in ("SCRIPT ERROR:", "Parse Error:", "Shader compilation failed", "ERROR: Cannot export")):
        raise RuntimeError(f"Command failed: {command[0]} (exit {result.returncode})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--templates", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("build"))
    parser.add_argument("--source-sha")
    parser.add_argument("--skip-tests", action="store_true")
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    app = root / "app"
    actual_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    sha = options.source_sha or actual_sha
    if sha != actual_sha:
        raise RuntimeError("Requested source SHA does not equal the checked-out commit")
    tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=root, text=True).strip())
    if dirty:
        raise RuntimeError("Refusing to label a modified tracked working tree with a committed source SHA")
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "app", "tools", "tests", "packaging"], cwd=root, text=True).strip()
    if untracked:
        raise RuntimeError("Refusing to package uncommitted source files: " + untracked)
    actual_engine = subprocess.check_output([options.godot, "--version"], text=True).strip()
    if not actual_engine.startswith(GODOT_VERSION + "."):
        raise RuntimeError("Expected pinned Godot " + GODOT_VERSION + ", got " + actual_engine)
    output = options.output.resolve()
    package = output / "Xenovection-Windows"
    if package.exists():
        shutil.rmtree(package)
    package.mkdir(parents=True, exist_ok=True)
    build = {"schema": "xenovection.build.v1", "source_sha": sha, "tree_sha": tree,
             "repository": "https://github.com/techrote/Xenovection", "godot": actual_engine,
             "status": "Draft/HOLD", "primary_renderer": "Vulkan Forward+",
             "specimen_sha256": "745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c"}
    (app / "build_info.json").write_text(json.dumps(build, indent=2) + "\n", encoding="utf-8", newline="\n")
    # Custom templates keep the package reproducible without a machine-wide install.
    export_file = app / "export_presets.cfg"
    original = export_file.read_bytes()
    configuration = original.decode()
    templates = options.templates.resolve()
    for kind in ("debug", "release"):
        template = templates / f"windows_{kind}_x86_64.exe"
        if not template.is_file():
            raise FileNotFoundError(template)
        configuration = configuration.replace(f'custom_template/{kind}=""', f'custom_template/{kind}="{template.as_posix()}"')
    export_file.write_text(configuration, encoding="utf-8", newline="\n")
    try:
        run([options.godot, "--headless", "--path", str(app), "--editor", "--import"], cwd=root)
        if not options.skip_tests:
            for test in ("../tests/test_core.gd", "../tests/test_integration.gd", "res://rendering/filaments/verify_filaments.gd", "res://rendering/optical/verify_optical.gd"):
                run([options.godot, "--headless", "--path", str(app), "--script", test], cwd=root)
            import sys
            run([sys.executable, str(root / "tests" / "verify_source_exact.py"), "--godot", options.godot], cwd=root)
        run([options.godot, "--headless", "--path", str(app), "--export-release", "Windows Desktop", str(package / "Xenovection.exe")], cwd=root)
    finally:
        export_file.write_bytes(original)
    for filename in ("Xenovection.exe", "Xenovection.console.exe", "Xenovection.pck"):
        if not (package / filename).is_file():
            raise RuntimeError("Missing required evaluator file: " + filename)
    (package / "BUILD.json").write_text(json.dumps(build, indent=2) + "\n", encoding="utf-8", newline="\n")
    shutil.copy2(root / "packaging" / "START-HERE.txt", package / "START-HERE.txt")
    shutil.copytree(root / "packaging" / "licenses", package / "licenses", dirs_exist_ok=True)
    launchers = {
        "Launch-Xenovection.cmd": '@echo off\r\ncd /d "%~dp0"\r\nstart "" "Xenovection.exe" --rendering-method forward_plus --rendering-driver vulkan %*\r\n',
        "Launch-Compatibility.cmd": '@echo off\r\ncd /d "%~dp0"\r\nstart "" "Xenovection.exe" --rendering-method gl_compatibility --rendering-driver opengl3 %*\r\n',
        "Profile-This-PC.cmd": '@echo off\r\ncd /d "%~dp0"\r\n"Xenovection.console.exe" --rendering-method forward_plus --rendering-driver vulkan --disable-vsync -- --preset=hybrid --warmup=120 --profile-frames=600 --profile="%~dp0owner-performance.json"\r\necho Performance receipt: owner-performance.json\r\npause\r\n',
    }
    for filename, content in launchers.items():
        (package / filename).write_bytes(content.encode("utf-8"))
    hashes = {}
    for path in sorted(package.rglob("*")):
        if path.is_file() and path.name != "SHA256SUMS.json":
            hashes[path.relative_to(package).as_posix()] = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
    (package / "SHA256SUMS.json").write_text(json.dumps(hashes, indent=2) + "\n", encoding="utf-8", newline="\n")
    archive = output / f"Xenovection-FOUND-002-Windows-{sha[:12]}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as target:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                target.write(path, "Xenovection/" + path.relative_to(package).as_posix())
    receipt = {"archive": archive.name, "bytes": archive.stat().st_size,
               "sha256": hashlib.file_digest(archive.open("rb"), "sha256").hexdigest(), "build": build,
               "payload_files": len(hashes)}
    (output / "package-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(receipt, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
