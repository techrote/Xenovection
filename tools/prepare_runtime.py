#!/usr/bin/env python3
"""Prepare pinned Windows CI tools. Nothing here enters the owner evaluator ZIP.

The renderer is Mesa lavapipe, not a physical GPU. Its Vulkan loader is built
from exact Khronos commits so a runner's installed graphics drivers are not a
hidden prerequisite. Download hashes are official release asset identities.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request
import zipfile


ASSETS = {
    "godot": {
        "filename": "Godot_v4.7.2-stable_win64.exe.zip",
        "url": "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip",
        "sha256": "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953",
    },
    "templates": {
        "filename": "Godot_v4.7.2-stable_export_templates.tpz",
        "url": "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz",
        "sha256": "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011",
    },
    "mesa": {
        "filename": "mesa3d-26.3.1-release-msvc.7z",
        "url": "https://github.com/pal1000/mesa-dist-win/releases/download/26.3.1/mesa3d-26.3.1-release-msvc.7z",
        "sha256": "64e84cf13d67dd354640bf443ed0445e6a83afd06a5729f0750b3744d633b3f1",
    },
}

LOADER_COMMIT = "fa218055ff4948b159f31d43f800c808a13d51df"
HEADERS_COMMIT = "6802bb4733b63ed5efd3adb308a6c885ef180ea1"
SDK_TAG = "vulkan-sdk-1.4.363.0"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download(asset: dict[str, str], directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / asset["filename"]
    if target.is_file() and sha256(target) == asset["sha256"]:
        print(f"Verified cached {target.name}", flush=True)
        return target
    temporary = target.with_suffix(target.suffix + ".partial")
    for attempt in range(3):
        try:
            request = urllib.request.Request(asset["url"], headers={"User-Agent": "Xenovection-evaluator/0.2"})
            print(f"Downloading pinned {target.name}", flush=True)
            with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
                shutil.copyfileobj(response, output, length=1024 * 1024)
            actual = sha256(temporary)
            if actual != asset["sha256"]:
                raise RuntimeError(f"SHA-256 mismatch for {target.name}: {actual}")
            temporary.replace(target)
            return target
        except Exception:
            temporary.unlink(missing_ok=True)
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))
    raise AssertionError("Unreachable download state")


def run(command: list[str], log: Path, timeout: int = 600) -> None:
    print("Running: " + subprocess.list2cmdline(command), flush=True)
    with log.open("w", encoding="utf-8") as output:
        completed = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    if completed.returncode:
        print(log.read_text(encoding="utf-8", errors="replace")[-12000:], flush=True)
        raise RuntimeError(f"Command failed ({completed.returncode}); see {log}")


def extract_selected(archive: Path, destination: Path, filenames: set[str]) -> None:
    """Flatten an explicit allowlist; never extract arbitrary archive paths."""
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        found: set[str] = set()
        for member in source.infolist():
            name = member.filename.rsplit("/", 1)[-1]
            if name not in filenames:
                continue
            if name in found:
                raise RuntimeError(f"Ambiguous archive member: {name}")
            with source.open(member) as content, (destination / name).open("wb") as output:
                shutil.copyfileobj(content, output)
            found.add(name)
    if found != filenames:
        raise RuntimeError(f"Missing pinned archive members: {sorted(filenames - found)}")


def checkout(repository: str, commit: str, destination: Path, logs: Path) -> None:
    if (destination / ".git").is_dir():
        current = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
        clean = not subprocess.check_output(["git", "-C", str(destination), "status", "--porcelain"], text=True).strip()
        if current == commit and clean:
            return
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    name = destination.name
    run(["git", "init", str(destination)], logs / f"{name}-init.log")
    run(["git", "-C", str(destination), "remote", "add", "origin", f"https://github.com/KhronosGroup/{repository}.git"], logs / f"{name}-remote.log")
    run(["git", "-C", str(destination), "fetch", "--depth", "1", "origin", commit], logs / f"{name}-fetch.log")
    run(["git", "-C", str(destination), "checkout", "--detach", "FETCH_HEAD"], logs / f"{name}-checkout.log")
    actual = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
    if actual != commit:
        raise RuntimeError(f"Unexpected {repository} revision: {actual}")


def build_loader(runtime: Path, logs: Path) -> tuple[Path, dict]:
    root = runtime / "vulkan-loader"
    root.mkdir(parents=True, exist_ok=True)
    receipt_path = root / "build-receipt.json"
    library = root / "bin" / "vulkan-1.dll"
    if library.is_file() and receipt_path.is_file():
        receipt = json.loads(receipt_path.read_text())
        if (receipt.get("loader_commit") == LOADER_COMMIT
                and receipt.get("headers_commit") == HEADERS_COMMIT
                and receipt.get("sha256") == sha256(library)):
            print("Verified cached Vulkan loader build", flush=True)
            return library, receipt
    sources = root / "sources"
    loader = sources / "Vulkan-Loader"
    headers = sources / "Vulkan-Headers"
    checkout("Vulkan-Loader", LOADER_COMMIT, loader, logs)
    checkout("Vulkan-Headers", HEADERS_COMMIT, headers, logs)
    install = root / "headers-install"
    # Clear toolchain-specific generated state if an incomplete cached build exists.
    for build in (root / "headers-build", root / "loader-build"):
        shutil.rmtree(build, ignore_errors=True)
    run(["cmake", "-S", str(headers), "-B", str(root / "headers-build"), "-A", "x64",
         f"-DCMAKE_INSTALL_PREFIX={install}", "-DVULKAN_HEADERS_ENABLE_TESTS=OFF",
         "-DVULKAN_HEADERS_ENABLE_MODULE=OFF"], logs / "headers-configure.log")
    run(["cmake", "--build", str(root / "headers-build"), "--config", "Release", "--target", "install"], logs / "headers-install.log")
    run(["cmake", "-S", str(loader), "-B", str(root / "loader-build"), "-A", "x64",
         f"-DVULKAN_HEADERS_INSTALL_DIR={install}", "-DBUILD_TESTS=OFF", "-DBUILD_WERROR=OFF",
         "-DUPDATE_DEPS=OFF", "-DLOADER_CODEGEN=OFF"], logs / "loader-configure.log")
    run(["cmake", "--build", str(root / "loader-build"), "--config", "Release", "--target", "vulkan", "--parallel", "4"], logs / "loader-build.log")
    candidates = list((root / "loader-build").rglob("vulkan-1.dll"))
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one x64 loader DLL, found {candidates}")
    library.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(candidates[0], library)
    receipt = {"kind": "CI-only source build", "sdk_tag": SDK_TAG,
               "loader_repository": "https://github.com/KhronosGroup/Vulkan-Loader",
               "loader_commit": LOADER_COMMIT,
               "headers_repository": "https://github.com/KhronosGroup/Vulkan-Headers",
               "headers_commit": HEADERS_COMMIT, "sha256": sha256(library),
               "cmake": subprocess.check_output(["cmake", "--version"], text=True).splitlines()[0],
               "configuration": "Release x64, tests/codegen/update-deps disabled"}
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return library, receipt


def probe_vulkan(runtime: Path, evidence: Path) -> int:
    """Inspect the actual loader's Win32 presentation extensions before Godot."""
    receipt = json.loads((runtime / "runtime.json").read_text(encoding="utf-8"))
    paths = receipt["paths"]

    class ExtensionProperties(ctypes.Structure):
        _fields_ = [("extensionName", ctypes.c_char * 256), ("specVersion", ctypes.c_uint32)]

    result = {"schema": "xenovection.windows-vulkan-preflight.v1",
              "loader": paths["loader"], "icd": paths["icd"],
              "required_extensions": ["VK_KHR_surface", "VK_KHR_win32_surface"]}
    try:
        with os.add_dll_directory(paths["mesa"]):
            # Distinguish missing transitive DLL dependencies from discovery errors.
            driver = ctypes.WinDLL(str(Path(paths["mesa"]) / "vulkan_lvp.dll"))
            result["driver_dll_loaded"] = bool(driver._handle)
            loader = ctypes.WinDLL(paths["loader"])
            enumerate_extensions = loader.vkEnumerateInstanceExtensionProperties
            enumerate_extensions.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_uint32),
                                            ctypes.POINTER(ExtensionProperties)]
            enumerate_extensions.restype = ctypes.c_int32
            count = ctypes.c_uint32()
            code = enumerate_extensions(None, ctypes.byref(count), None)
            if code != 0:
                raise RuntimeError(f"vkEnumerateInstanceExtensionProperties returned {code}")
            extensions = (ExtensionProperties * count.value)()
            code = enumerate_extensions(None, ctypes.byref(count), extensions)
            if code != 0:
                raise RuntimeError(f"Vulkan extension enumeration returned {code}")
            names = sorted(item.extensionName.decode("ascii") for item in extensions)
            result["extensions"] = names
            result["missing_extensions"] = sorted(set(result["required_extensions"]) - set(names))
            result["status"] = "PASS" if not result["missing_extensions"] else "FAIL"
    except Exception as error:
        result["status"] = "FAIL"
        result["error"] = str(error)
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / "vulkan-preflight.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result["status"] == "PASS" else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", type=Path, default=Path(".runtime"))
    parser.add_argument("--evidence", type=Path, default=Path("build/windows-evidence"))
    parser.add_argument("--probe-vulkan", action="store_true")
    options = parser.parse_args()
    if os.name != "nt":
        raise RuntimeError("This preparation command requires native Windows with CMake/MSVC/7-Zip")
    runtime = options.runtime.resolve()
    evidence = options.evidence.resolve()
    if options.probe_vulkan:
        return probe_vulkan(runtime, evidence)
    runtime.mkdir(parents=True, exist_ok=True)
    logs = evidence / "runtime"
    logs.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {name: pool.submit(download, asset, runtime / "downloads") for name, asset in ASSETS.items()}
        # Compile while the larger binary archives download.
        loader, loader_receipt = build_loader(runtime, logs)
        archives = {name: future.result() for name, future in futures.items()}
    editor_dir = runtime / "godot-4.7.2"
    editor_name = "Godot_v4.7.2-stable_win64.exe"
    console_name = "Godot_v4.7.2-stable_win64_console.exe"
    extract_selected(archives["godot"], editor_dir, {editor_name, console_name})
    template_dir = runtime / "templates-4.7.2"
    extract_selected(archives["templates"], template_dir, {
        f"windows_{kind}_x86_64{suffix}.exe"
        for kind in ("debug", "release") for suffix in ("", "_console")
    } | {"version.txt"})
    version = (template_dir / "version.txt").read_text().strip()
    if version != "4.7.2.stable":
        raise RuntimeError(f"Unexpected export template version: {version}")
    seven_zip = shutil.which("7z") or str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "7-Zip/7z.exe")
    mesa_dir = runtime / "mesa-26.3.1"
    mesa_dir.mkdir(parents=True, exist_ok=True)
    run([seven_zip, "x", "-y", f"-o{mesa_dir}", str(archives["mesa"]), "x64/*"], logs / "mesa-extract.log")
    mesa_x64 = mesa_dir / "x64"
    icd = mesa_x64 / "lvp_icd.x86_64.json"
    if not icd.is_file() or not (mesa_x64 / "vulkan_lvp.dll").is_file():
        raise RuntimeError("Pinned Mesa package does not contain the expected x64 lavapipe ICD")
    # Explicit absolute path removes loader-dependent JSON relative-path handling.
    icd_data = json.loads(icd.read_text())
    icd_data["ICD"]["library_path"] = str(mesa_x64 / "vulkan_lvp.dll")
    test_icd = mesa_x64 / "xenovection-ci-icd.json"
    test_icd.write_text(json.dumps(icd_data, indent=2) + "\n", encoding="utf-8")
    shutil.copy2(loader, editor_dir / "vulkan-1.dll")
    receipt = {"schema": "xenovection.ci-runtime.v1", "physical_gpu": False,
               "purpose": "Native Windows Vulkan software execution only; never bundled in owner ZIP",
               "assets": ASSETS, "loader": loader_receipt,
               "paths": {"godot": str(editor_dir / editor_name),
                         "godot_console": str(editor_dir / console_name),
                         "templates": str(template_dir), "mesa": str(mesa_x64),
                         "icd": str(test_icd), "loader": str(loader)},
               "runtime_files": {"godot_sha256": sha256(editor_dir / editor_name),
                                 "mesa_icd_sha256": sha256(mesa_x64 / "vulkan_lvp.dll"),
                                 "loader_sha256": sha256(loader)}}
    (runtime / "runtime.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    (evidence / "runtime.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
