#!/usr/bin/env python3
"""Independently verify a downloaded evaluator artifact without executing its code.

Payload integrity and archived Windows qualification are separate outcomes. A
well-formed evaluator from an incomplete/failed campaign is never reported PASS.
Only Python's standard library is required; neither ZIP layer is extracted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import tempfile
from typing import Any
import zipfile


MISSION = "MAINLINE-CONVERGENCE-001"
SPECIMEN = "745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c"
BINARY64 = "5cbc5684277b613767ca84a7214428a913aab5cdc8969f061591fb6835104629"
PREFIX = "Xenovection/"
MAX_FILES = 4096
MAX_ARCHIVE_BYTES = 2 * 1024**3
MAX_EXPANDED_BYTES = 4 * 1024**3
MAX_JSON_BYTES = 32 * 1024**2
SOURCE_PRESETS = ("hybrid", "filaments", "optical", "membrane", "scientific", "stress", "flow")
MATTER_PRESETS = ("nursery", "garden", "living", "films", "condensation", "ecosystem")
OPTICAL_PRESETS = ("dichroic", "weather", "lens", "garden", "microfibres", "ecosystem")
COMPOSITIONS = ("spectral_vortex", "living_membrane", "excitable_garden",
                "condensation_instrument", "light_terrarium", "matter_orchestra")
SCENE_IDS = ({"source." + name for name in SOURCE_PRESETS}
             | {"matter." + name for name in MATTER_PRESETS}
             | {"optical." + name for name in OPTICAL_PRESETS}
             | {"composition." + name for name in COMPOSITIONS})
EXTRACTED_SCRIPTS = ("test_core", "test_integration", "test_matter", "test_synth",
                     "test_ecology", "test_compositions", "test_matter_optics",
                     "test_convergence_ecology", "test_convergence", "verify_filaments", "verify_optical")
PACKAGED_SCRIPTS = {name + ".gd" for name in EXTRACTED_SCRIPTS} | {
    "test_soak.gd", "export_source_bits.gd", "verify_captures.gd", "gui_material_probe.gd",
    "gui_spatial_ecology_probe.gd", "gui_convergence_probe.gd", "gui_synth_probe.gd",
    "gui_input_probe.gd", "gui_ecology_probe.gd"}
REQUIRED_GATES = {
    "prepare-runtime", "numerical-dependency", "historical-numerical",
    "historical-godot-import", "historical-godot-startup", "editor-import",
    "ecology-world-parse", "ecology-workspace-parse", "ecology-gui-probe-parse",
    "matter-contracts", "core-contracts", "integrated-contracts", "synth-contracts",
    "ecology-contracts", "composition-contracts", "matter-optics-contracts",
    "spatial-ecology-contracts", "convergence-contracts", "filament-contracts", "optical-contracts",
    "source-binary64-exactness", "package", "vulkan-preflight",
    "extracted-full-resource-soak", "extracted-source-export", "extracted-source-binary64-exactness",
    "extracted-graphical-material", "extracted-graphical-spatial_ecology", "extracted-graphical-convergence",
    "filament-vulkan-buffer-roundtrip", "synth-graphical-input", "graphical-input", "ecosystem-disabled",
    "ecology-graphical-input", "ecosystem-vortex-interaction-disabled",
    "composition-orchestra-legacy-optics", "graphical-capture-health",
}
REQUIRED_GATES.update("extracted-" + name for name in EXTRACTED_SCRIPTS)
REQUIRED_GATES.update(name + "-playable-vulkan" for name in SOURCE_PRESETS)
REQUIRED_GATES.update("optical_" + name + "-playable-vulkan" for name in OPTICAL_PRESETS)
REQUIRED_GATES.update("synth-%d-packaged" % index for index in range(1, 7))
REQUIRED_GATES.update(name + "-procedural-vulkan" for name in MATTER_PRESETS)
REQUIRED_GATES.update("optical_" + name + "-close" for name in OPTICAL_PRESETS)
REQUIRED_GATES.update("optical_" + name + "-legacy" for name in ("weather", "lens", "garden", "ecosystem"))
REQUIRED_GATES.update("ecosystem-%d-extracted-vulkan" % index for index in range(6))
REQUIRED_GATES.update("composition-%s-%s" % (name, view) for name in COMPOSITIONS for view in ("overview", "close"))
REQUIRED_LAUNCHERS = {"Launch-Xenovection.cmd", "Launch-Compatibility.cmd", "Launch-Ecosystem.cmd",
                      "Launch-Integrated.cmd", "Profile-This-PC.cmd", "Profile-Ecosystem.cmd", "Profile-Integrated.cmd"}
REQUIRED_LICENSES = {"licenses/GODOT_LICENSE.txt", "licenses/GODOT_COPYRIGHT.txt"}
GUI_RECEIPTS = {
    "gui-material": {"suite": "graphical-generated-optical-authoring", "checks": 42,
                     "pngs": ["-legacy", "-optical", "-authoring"]},
    "gui-spatial_ecology": {"suite": "spatial ecology real graphical input", "checks": 60,
                            "pngs": ["", "-material-low", "-material-high"]},
    "gui-convergence": {"suite": "graphical-integrated-authoring", "checks": 90,
                        "pngs": ["-authoring", "-composition"]},
    # The inherited SYNTH receipt deliberately has no status or suite field.
    "synth-gui": {"suite": None, "checks": 10, "pngs": [""]},
    "gui-input": {"suite": "graphical-input-routing", "checks": 37, "pngs": [""]},
    "ecology-gui": {"suite": "ecology graphical input", "checks": 23, "pngs": [""]},
}
ENGINE_ERROR = re.compile(
    r"SCRIPT ERROR:|Parse Error:|Shader compilation failed|^ERROR:|ObjectDB instances leaked|resources still in use|RIDs of type",
    re.IGNORECASE | re.MULTILINE,
)


class InvalidArtifact(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise InvalidArtifact(message)


def digest_stream(stream) -> tuple[str, int]:
    hasher = hashlib.sha256()
    count = 0
    while chunk := stream.read(1024 * 1024):
        count += len(chunk)
        hasher.update(chunk)
    return hasher.hexdigest(), count


def safe_path(name: str, directory: bool = False) -> str:
    require(isinstance(name, str) and bool(name), "Archive path is missing")
    value = name[:-1] if directory and name.endswith("/") else name
    require(value and not value.startswith("/") and "\\" not in value, "Absolute/backslash path: " + name)
    parts = value.split("/")
    require(all(part not in ("", ".", "..") for part in parts), "Non-canonical archive path: " + name)
    reserved = {"CON", "PRN", "AUX", "NUL"} | {"COM%d" % i for i in range(1, 10)} | {"LPT%d" % i for i in range(1, 10)}
    for part in parts:
        require(not any(ord(c) < 32 or c in '<>:"|?*' for c in part), "Unsafe Windows path: " + name)
        require(not part.endswith((".", " ")), "Windows path alias: " + name)
        require(part.split(".", 1)[0].upper() not in reserved, "Reserved Windows path: " + name)
    return value


def inventory(archive: zipfile.ZipFile, label: str) -> dict[str, zipfile.ZipInfo]:
    rows = archive.infolist()
    require(0 < len(rows) <= MAX_FILES, label + " file-count bound exceeded")
    require(sum(row.file_size for row in rows) <= MAX_EXPANDED_BYTES, label + " expanded-size bound exceeded")
    seen: set[str] = set()
    files: dict[str, zipfile.ZipInfo] = {}
    for row in rows:
        canonical = safe_path(row.filename, row.is_dir())
        folded = canonical.casefold()
        require(folded not in seen, label + " duplicate/case-colliding path: " + row.filename)
        seen.add(folded)
        require(not row.flag_bits & 1, label + " encrypted member: " + row.filename)
        mode = row.external_attr >> 16
        require(not stat.S_ISLNK(mode), label + " symbolic link: " + row.filename)
        require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR), label + " special member: " + row.filename)
        if not row.is_dir():
            files[row.filename] = row
    file_names = {name.casefold() for name in files}
    for name in files:
        require(not any(str(parent).casefold() in file_names for parent in PurePosixPath(name).parents if str(parent) != "."),
                label + " file is also a parent directory: " + name)
    return files


def unique_json_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(archive: zipfile.ZipFile, files: dict, name: str) -> Any:
    require(name in files, "Missing JSON receipt: " + name)
    require(files[name].file_size <= MAX_JSON_BYTES, "JSON size bound exceeded: " + name)
    result = json.loads(archive.read(name).decode("utf-8-sig"), object_pairs_hook=unique_json_pairs,
                        parse_constant=lambda value: (_ for _ in ()).throw(InvalidArtifact("Non-finite JSON value: " + value)))
    require(isinstance(result, dict), "Expected a JSON object: " + name)
    return result


def member_digest(archive: zipfile.ZipFile, name: str) -> str:
    with archive.open(name) as stream:
        return digest_stream(stream)[0]


def check_build(build: dict, source: str, tree: str, label: str) -> None:
    require(isinstance(build, dict), label + " build identity is not an object")
    require(build.get("schema") == "xenovection.build.v1", label + " BUILD schema mismatch")
    require(build.get("source_sha") == source and build.get("tree_sha") == tree, label + " source/tree mismatch")
    require(build.get("mission") == MISSION and build.get("status") == "Draft/HOLD", label + " custody disposition mismatch")
    require(build.get("primary_renderer") == "Vulkan Forward+", label + " renderer identity mismatch")
    require(build.get("godot") == "4.7.2.stable.official.ed1daf0bf", label + " engine identity mismatch")
    require(build.get("repository") == "https://github.com/techrote/Xenovection", label + " repository identity mismatch")
    require(build.get("specimen_sha256") == SPECIMEN, label + " specimen identity mismatch")


def check_pe(archive: zipfile.ZipFile, files: dict, name: str) -> dict:
    require(name in files and files[name].file_size > 512, "Missing PE executable: " + name)
    with archive.open(name) as stream:
        dos = stream.read(64)
        require(dos[:2] == b"MZ", "Invalid DOS header: " + name)
        offset = struct.unpack_from("<I", dos, 60)[0]
        require(64 <= offset <= files[name].file_size - 26, "PE offset out of bounds: " + name)
        stream.seek(offset)
        header = stream.read(26)
    require(header[:4] == b"PE\0\0", "Invalid PE signature: " + name)
    machine, sections = struct.unpack_from("<HH", header, 4)
    magic = struct.unpack_from("<H", header, 24)[0]
    require(machine == 0x8664 and magic == 0x20B and sections > 0, "PE is not x64 PE32+: " + name)
    return {"file": name.removeprefix(PREFIX), "machine": "AMD64", "optional_header": "PE32+", "sections": sections}


def check_examples(archive: zipfile.ZipFile, files: dict) -> dict:
    index = read_json(archive, files, PREFIX + "samples/INDEX.json")
    require(index.get("schema") == "xenovection.examples.v1", "Example index schema mismatch")
    rows = index.get("scenes")
    require(isinstance(rows, list) and len(rows) == 25, "Exactly 25 indexed scenes required")
    ids = [row.get("id") for row in rows]
    require(len(set(ids)) == 25 and set(ids) == SCENE_IDS, "Scene IDs are duplicated or do not preserve all 25 compositions")
    expected_paths = set()
    for row in rows:
        relative = safe_path(row.get("scene"))
        require(relative == "scenes/" + row["id"] + ".json", "Scene index path/identity mismatch")
        name = PREFIX + "samples/" + relative
        expected_paths.add(name)
        scene = read_json(archive, files, name)
        require(scene.get("schema") == "xenovection.scene.v2" and scene.get("preset_id") == row["id"],
                "Scene v2 identity mismatch: " + name)
    actual_paths = {name for name in files if name.startswith(PREFIX + "samples/scenes/")}
    require(actual_paths == expected_paths, "Scene file-set differs from INDEX.json")
    patch_names = {PREFIX + "samples/patches/composition." + name + ".json" for name in COMPOSITIONS}
    patch_names.update(PREFIX + "samples/patches/synth-%02d.json" % i for i in range(1, 7))
    actual_patches = {name for name in files if name.startswith(PREFIX + "samples/patches/")}
    require(actual_patches == patch_names, "Exactly six integrated and six inherited patches required")
    patch_presets = {}
    for name in sorted(patch_names):
        patch = read_json(archive, files, name)
        require(patch.get("schema") == "xenovection.patch.v1" and patch.get("preset_id") in SCENE_IDS,
                "Patch schema or stable preset mismatch: " + name)
        require(isinstance(patch.get("sources"), list) and len(patch["sources"]) <= 48
                and isinstance(patch.get("routes"), list) and len(patch["routes"]) <= 96,
                "Patch graph bounds invalid: " + name)
        patch_presets[name] = patch["preset_id"]
    indexed_patches = 0
    # Earlier valid v1 payloads omitted patch rows. Keep their payload integrity
    # result meaningful, while final campaign completeness requires all 12 rows.
    if "patches" in index:
        patch_rows = index["patches"]
        require(isinstance(patch_rows, list) and len(patch_rows) == 12, "Exactly 12 patch index rows required")
        expected_ids = {"patch.composition." + name for name in COMPOSITIONS}
        expected_ids.update("patch.synth.%02d" % i for i in range(1, 7))
        ids = [row.get("id") for row in patch_rows]
        require(len(set(ids)) == 12 and set(ids) == expected_ids, "Patch index IDs are duplicated or incomplete")
        indexed_paths = set()
        for row in patch_rows:
            relative = safe_path(row.get("patch"))
            name = PREFIX + "samples/" + relative
            expected_filename = (row["id"].removeprefix("patch.") if row["id"].startswith("patch.composition.")
                                 else row["id"].removeprefix("patch.").replace("synth.", "synth-")) + ".json"
            require(relative == "patches/" + expected_filename, "Patch index path/identity mismatch")
            require(name in patch_presets and row.get("preset_id") == patch_presets[name],
                    "Patch index referenced preset differs from authored patch: " + name)
            require(isinstance(row.get("title"), str) and bool(row["title"].strip()), "Patch index title is empty")
            indexed_paths.add(name)
        require(indexed_paths == actual_patches, "Patch file-set differs from INDEX.json")
        indexed_patches = len(patch_rows)
    return {"indexed_scenes": 25, "unique_stable_ids": 25, "scene_schema": "xenovection.scene.v2",
            "integrated_patches": 6, "inherited_patches": 6, "indexed_patches": indexed_patches,
            "patch_schema": "xenovection.patch.v1"}


def workflow_check(outer: zipfile.ZipFile, files: dict, package: dict, source: str, tree: str, script_custody: dict,
                   examples: dict) -> dict:
    name = "windows-evidence/qualification.json"
    if name not in files:
        return {"status": "INCOMPLETE", "recorded_status": "MISSING", "failures": ["Missing Windows qualification receipt"]}
    q = read_json(outer, files, name)
    errors = []
    def check(ok: bool, message: str) -> None:
        if not ok:
            errors.append(message)
    check(q.get("schema") == "xenovection.windows-qualification.v1", "Unexpected qualification schema")
    check(q.get("status") == "PASS", "Recorded Windows qualification is " + str(q.get("status", "MISSING")))
    check(q.get("source_sha") == source and q.get("source_tree") == tree, "Windows qualification source/tree mismatch")
    check(q.get("package", {}).get("sha256") == package["sha256"], "Qualification archive digest differs from package receipt")
    check(q.get("embedded_build") == package["build"], "Qualification embedded BUILD differs from package receipt")
    check(q.get("script_custody") == script_custody, "Executed script custody differs from payload manifest")
    check(q.get("physical_gpu_qualified") is False, "Hosted receipt must preserve physical-GPU qualification boundary")
    check(examples.get("indexed_patches") == 12, "Final campaign requires 12 discoverable indexed patches")
    steps = q.get("steps", [])
    names = [step.get("name") for step in steps]
    check(len(names) == len(set(names)), "Duplicate qualification gate names")
    missing = sorted(REQUIRED_GATES - set(names))
    check(not missing, "Required Windows gates are missing")
    bad_steps = [step.get("name") for step in steps if step.get("status") != "PASS" or step.get("exit_code") != 0
                 or step.get("timeout") is not False or step.get("engine_error_detected") is not False]
    check(not bad_steps, "Failed/timed-out/engine-error qualification gates exist")
    retained_logs = {path for path in files if path.startswith("windows-evidence/") and path.endswith("-engine.log")}
    for step in steps:
        log_name = "windows-evidence/" + safe_path(step.get("log", ""))
        check(log_name in files, "Missing gate log: " + log_name)
        if log_name in files:
            retained_logs.add(log_name)
        requests = [arg.split("=", 1)[1] for arg in step.get("arguments", []) if str(arg).startswith("--qualification-script=")]
        if requests and log_name in files and files[log_name].file_size <= MAX_JSON_BYTES:
            content = outer.read(log_name).decode("utf-8-sig", errors="replace")
            check(len(requests) == 1 and "XENOVECTION_QUALIFICATION_SCRIPT_STARTED " + requests[0] in content,
                  "Missing exact release-dispatch marker: " + str(step.get("name")))
    engine_matches = []
    for log_name in sorted(retained_logs):
        if files[log_name].file_size > MAX_JSON_BYTES:
            check(False, "Retained gate/engine log exceeds bounded scan size: " + log_name)
            continue
        content = outer.read(log_name).decode("utf-8-sig", errors="replace")
        for number, line in enumerate(content.splitlines(), 1):
            if ENGINE_ERROR.search(line):
                engine_matches.append({"file": log_name, "line": number, "text": line[:500]})
    check(not engine_matches, "Retained gate/engine logs contain actual script, shader, engine or resource errors")
    gui_checks = []
    for stem, contract in GUI_RECEIPTS.items():
        receipt_path = "windows-evidence/" + stem + ".json"
        check(receipt_path in files, "Missing required GUI receipt: " + receipt_path)
        if receipt_path not in files:
            continue
        gui = read_json(outer, files, receipt_path)
        count = gui.get("checks", 0)
        valid = isinstance(count, int) and not isinstance(count, bool) and count >= contract["checks"] and gui.get("failures") == []
        if contract["suite"] is not None:
            valid = valid and gui.get("suite") == contract["suite"] and gui.get("status") == "PASS"
        if "passed" in gui:
            valid = valid and gui["passed"] == count
        check(valid, "Incomplete/failed actual GUI assertions: " + stem)
        if "renderer" in gui or stem == "synth-gui":
            check(gui.get("renderer") == "forward_plus", "GUI receipt used the wrong renderer: " + stem)
        if "display" in gui:
            check(str(gui["display"]).lower() == "windows", "GUI receipt is not a Windows display: " + stem)
        if "source_revision" in gui:
            check(gui["source_revision"] == "sha256:" + SPECIMEN, "GUI source revision changed: " + stem)
        if stem == "gui-input":
            check(gui.get("capture_result") == 0, "Inherited GUI capture did not save successfully")
        if stem == "gui-convergence":
            check(gui.get("build", {}).get("source_sha") == source and gui.get("build", {}).get("tree_sha") == tree,
                  "Integrated GUI build/source identity mismatch")
        if stem == "gui-spatial_ecology":
            seed = gui.get("seed_authoring", {})
            check(seed.get("pending_seed") == seed.get("displayed_seed_after_refresh") == seed.get("reset_seed") == 81234
                  and seed.get("previous_world_seed") != 81234
                  and seed.get("recalled_composition") == "composition.light_terrarium"
                  and seed.get("recalled_seed") == 51571,
                  "Missing pending-seed edit/refresh/reset/composition-recall witness")
        if stem == "ecology-gui":
            layout = gui.get("layout", {})
            viewport, panel, area, clip = (layout.get(key, []) for key in ("viewport", "panel", "world_area", "scroll_clip"))
            rectangles = (viewport, panel, area, clip)
            valid_rectangles = all(isinstance(rect, list) and len(rect) == 4
                                   and all(isinstance(value, (int, float)) and not isinstance(value, bool)
                                           and math.isfinite(value) for value in rect)
                                   and rect[2] > 0 and rect[3] > 0 for rect in rectangles)
            check(valid_rectangles, "Missing finite planar layout measurements")
            if valid_rectangles:
                check(panel[0] >= viewport[0] and panel[1] >= viewport[1]
                      and panel[0] + panel[2] <= viewport[0] + viewport[2] - 11
                      and panel[1] + panel[3] <= viewport[1] + viewport[3]
                      and area[0] + area[2] < panel[0], "Planar rail or numerical area overflows its qualified bounds")
                controls = layout.get("control_horizontal_bounds", [])
                check(len(controls) >= 11 and all(row.get("left", -1) >= clip[0] - 0.01
                      and row.get("right", float("inf")) <= clip[0] + clip[2] + 0.01 for row in controls),
                      "Planar checkbox indicators or slider endpoints overflow the scroll clip")
            check(0 <= layout.get("roundtrip_max_error", float("inf")) < 0.000001
                  and 0 <= layout.get("pointer_plant_error", float("inf")) < 0.00001,
                  "Missing planar coordinate roundtrip and actual pointer planting witness")
        captures = []
        for suffix in contract["pngs"]:
            path = "windows-evidence/" + stem + suffix + ".png"
            check(path in files, "Missing required GUI capture: " + path)
            if path in files:
                with outer.open(path) as stream:
                    header = stream.read(24)
                check(files[path].file_size > 24 and header[:8] == b"\x89PNG\r\n\x1a\n", "Invalid required GUI PNG: " + path)
                captures.append({"file": path, "sha256": member_digest(outer, path)})
        gui_checks.append({"file": receipt_path, "checks": count, "minimum_checks": contract["checks"],
                           "assertions_pass": valid, "captures": captures})
    expected_scenes = set(SOURCE_PRESETS) | set(MATTER_PRESETS) | {"optical_" + item for item in OPTICAL_PRESETS}
    check({row.get("preset") for row in q.get("scenes", [])} == expected_scenes and len(q.get("scenes", [])) == 19,
          "Incomplete inherited source/matter/optical scene population")
    check(len(q.get("synth_patches", [])) == 6, "Incomplete inherited synth population")
    check({row.get("preset") for row in q.get("ecology", [])} == set(range(6)), "Incomplete inherited ecology population")
    pairs = {(row.get("composition"), row.get("view")) for row in q.get("compositions", [])}
    check(pairs == {("composition." + item, view) for item in COMPOSITIONS for view in ("overview", "close")}
          and len(q.get("compositions", [])) == 12, "Incomplete integrated overview/close population")
    comparison_pairs = {(row.get("preset"), row.get("mode")) for row in q.get("comparisons", [])}
    expected_comparisons = {("optical_" + item, "close") for item in OPTICAL_PRESETS}
    expected_comparisons.update(("optical_" + item, "legacy-optics") for item in ("weather", "lens", "garden", "ecosystem"))
    check(comparison_pairs == expected_comparisons and len(q.get("comparisons", [])) == 10,
          "Incomplete optical close/disabled comparison population")
    for preset in ("weather", "lens", "garden", "ecosystem"):
        filename = "optical_" + preset + "-legacy.png"
        matching = [row for row in q.get("comparisons", []) if row.get("preset") == "optical_" + preset and row.get("mode") == "legacy-optics"]
        check("windows-evidence/" + filename in files and len(matching) == 1 and matching[0].get("capture") == filename,
              "Missing final disabled-optics capture/receipt: " + filename)
    check(q.get("capture_health", {}).get("status") == "PASS", "Capture-health audit missing or unsuccessful")
    capture_hashes = 0
    profile_identities = 0
    for group in ("scenes", "synth_patches", "ecology", "compositions", "comparisons"):
        for row in q.get(group, []):
            if "profile" in row:
                profile_path = "windows-evidence/" + safe_path(row["profile"])
                check(profile_path in files, "Missing referenced profile: " + profile_path)
                if profile_path in files:
                    profile = read_json(outer, files, profile_path)
                    build = profile.get("build", {})
                    check(build.get("source_sha") == source and build.get("tree_sha") == tree,
                          "Executed profile source/tree mismatch: " + profile_path)
                    profile_identities += 1
            if "capture" not in row:
                continue
            capture = "windows-evidence/" + safe_path(row["capture"])
            check(capture in files, "Missing referenced capture: " + capture)
            if capture in files:
                actual = member_digest(outer, capture)
                check(actual == row.get("capture_sha256"), "Capture digest mismatch: " + capture)
                capture_hashes += 1
    audit = q.get("capture_health", {})
    audit_rows = audit.get("captures", [])
    audited_paths = set()
    for row in audit_rows:
        path = "windows-evidence/" + safe_path(row.get("file", ""))
        audited_paths.add(path)
        check(path in files and row.get("status") == "PASS", "Missing/failed audited capture: " + path)
        if path in files:
            check(member_digest(outer, path) == row.get("sha256"), "Capture-audit digest mismatch: " + path)
    actual_captures = {path for path in files if path.startswith("windows-evidence/") and path.lower().endswith(".png")}
    check(bool(audit_rows) and len(audit_rows) == len(audited_paths) == audit.get("captures_checked")
          and audited_paths == actual_captures, "Capture-health receipt does not cover every uploaded PNG exactly once")
    bits_path = "windows-evidence/extracted-source-f64.bin"
    check(bits_path in files, "Missing independently extracted scientific binary64 stream")
    if bits_path in files:
        with outer.open(bits_path) as stream:
            actual, count = digest_stream(stream)
        check(count == 11568 * 8 and actual == BINARY64, "Extracted scientific binary64 stream changed")
    if q.get("runner_elevated"):
        check(q.get("icd_registration_restored") is True, "Temporary CI driver registration cleanup not confirmed")
    return {"status": "PASS" if not errors else "FAIL", "recorded_status": q.get("status", "MISSING"),
            "source_sha": q.get("source_sha"), "tree_sha": q.get("source_tree"),
            "observed_gates": len(steps), "required_gates": len(REQUIRED_GATES),
            "missing_required_gates": missing, "failed_gates": bad_steps,
            "capture_hashes_verified": capture_hashes, "recorded_failure": q.get("failure"),
            "profile_source_tree_identities_checked": profile_identities, "audited_pngs_checked": len(audit_rows),
            "gui_receipts": gui_checks, "retained_logs_scanned": len(retained_logs), "engine_error_matches": engine_matches,
            "physical_gpu_qualified": False, "failures": errors}


def verify(args) -> dict:
    report = {"schema": "xenovection.downloaded-artifact-verification.v1", "mission": MISSION,
              "verification_scope": "Independent archive integrity and recorded qualification evidence; no executable is run by this verifier",
              "source_sha": args.source_sha, "tree_sha": args.tree_sha,
              "payload_status": "FAIL", "workflow_qualification_status": "NOT_EVALUATED", "overall_status": "FAIL",
              "owner_physical_gpu_acceptance": "Pending owner evaluation", "failures": []}
    try:
        require(args.outer.is_file() and args.outer.stat().st_size <= MAX_ARCHIVE_BYTES, "Outer artifact missing or exceeds size bound")
        with args.outer.open("rb") as stream:
            actual, count = digest_stream(stream)
        report["outer"] = {"filename": args.outer.name, "bytes": count, "sha256": actual,
                           "expected_sha256": args.expected_outer_sha256}
        require(actual == args.expected_outer_sha256, "Outer artifact SHA-256 mismatch")
        with zipfile.ZipFile(args.outer) as outer:
            outer_files = inventory(outer, "Outer artifact")
            inner_names = [name for name in outer_files if name.lower().endswith(".zip")]
            require(len(inner_names) == 1, "Exactly one inner evaluator ZIP required")
            package = read_json(outer, outer_files, "package-receipt.json")
            check_build(package.get("build"), args.source_sha, args.tree_sha, "Package receipt")
            inner_name = inner_names[0]
            require(inner_name == package.get("archive"), "Inner archive filename differs from package receipt")
            require(inner_name == f"Xenovection-{MISSION}-Windows-{args.source_sha[:12]}.zip", "Inner archive identity/name mismatch")
            require(outer_files[inner_name].file_size <= MAX_ARCHIVE_BYTES, "Inner archive exceeds size bound")
            with tempfile.TemporaryFile() as spool:
                hasher = hashlib.sha256()
                size = 0
                with outer.open(inner_name) as stream:
                    while chunk := stream.read(1024 * 1024):
                        hasher.update(chunk)
                        spool.write(chunk)
                        size += len(chunk)
                digest = hasher.hexdigest()
                report["inner"] = {"filename": inner_name, "bytes": size, "sha256": digest}
                require(size == package.get("bytes") and digest == package.get("sha256"), "Inner ZIP size/digest mismatch")
                spool.seek(0)
                with zipfile.ZipFile(spool) as inner:
                    files = inventory(inner, "Evaluator payload")
                    require(all(name.startswith(PREFIX) for name in files), "Payload has files outside Xenovection/")
                    manifest = read_json(inner, files, PREFIX + "SHA256SUMS.json")
                    require(isinstance(manifest, dict) and bool(manifest), "Payload hash manifest is empty or invalid")
                    for relative, expected in manifest.items():
                        safe_path(relative)
                        require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected) is not None,
                                "Invalid manifest digest: " + relative)
                    require(set(files) == {PREFIX + name for name in manifest} | {PREFIX + "SHA256SUMS.json"},
                            "Payload file-set differs from hash manifest (missing or unlisted files)")
                    require(package.get("payload_files") == len(manifest), "Package payload-file count mismatch")
                    for relative, expected in manifest.items():
                        with inner.open(PREFIX + relative) as stream:
                            actual, _ = digest_stream(stream)
                        require(actual == expected, "Payload SHA-256 mismatch: " + relative)
                    build = read_json(inner, files, PREFIX + "BUILD.json")
                    check_build(build, args.source_sha, args.tree_sha, "Payload")
                    require(build == package["build"], "Payload and package BUILD records differ")
                    report["build"] = build
                    report["payload_files_verified"] = len(manifest)
                    report["pe_headers"] = [check_pe(inner, files, PREFIX + name) for name in ("Xenovection.exe", "Xenovection.console.exe")]
                    pck_name = PREFIX + "Xenovection.pck"
                    require(pck_name in files and files[pck_name].file_size > 128, "Missing/empty PCK")
                    with inner.open(pck_name) as stream:
                        header = stream.read(20)
                    require(header[:4] == b"GDPC" and struct.unpack_from("<III", header, 8) == (4, 7, 2), "PCK/engine header mismatch")
                    report["pck"] = {"bytes": files[pck_name].file_size, "format": struct.unpack_from("<I", header, 4)[0], "engine": [4, 7, 2]}
                    require(manifest.get("data/synthetic_foundry.json") == SPECIMEN, "Immutable specimen payload digest mismatch")
                    required = REQUIRED_LAUNCHERS | REQUIRED_LICENSES | {"START-HERE.txt", "qualification/SOURCE.json"}
                    require(required <= set(manifest), "Missing owner launcher, instructions, licence or script manifest")
                    require(all(files[PREFIX + name].file_size > 0 for name in required), "Empty required owner file")
                    forbidden = []
                    for name in manifest:
                        base = PurePosixPath(name).name.lower()
                        if base in {"vulkan-1.dll", "vulkan_lvp.dll", "opengl32.dll"} or (base.endswith(".dll") and any(token in base for token in ("lavapipe", "llvmpipe", "mesa"))):
                            forbidden.append(name)
                    require(not forbidden, "Hosted software-rendering DLLs entered owner payload: " + ", ".join(forbidden))
                    report["bundled_ci_loader_dlls"] = forbidden
                    report["examples"] = check_examples(inner, files)
                    script_custody = read_json(inner, files, PREFIX + "qualification/SOURCE.json")
                    require(isinstance(script_custody, dict) and set(script_custody) == PACKAGED_SCRIPTS,
                            "Qualification manifest does not contain the exact 20 required scripts")
                    for entry in script_custody.values():
                        safe_path(entry.get("source_path", ""))
                        require(re.fullmatch(r"[0-9a-f]{64}", str(entry.get("sha256", ""))) is not None,
                                "Invalid qualification script source digest")
                    report["script_custody_entries"] = len(script_custody)
                    report["payload_status"] = "PASS"
            workflow = workflow_check(outer, outer_files, package, args.source_sha, args.tree_sha, script_custody,
                                      report["examples"])
            report["workflow"] = workflow
            report["workflow_qualification_status"] = workflow["status"]
            report["overall_status"] = "PASS" if workflow["status"] == "PASS" else "FAIL"
    except (InvalidArtifact, OSError, ValueError, KeyError, TypeError, AttributeError, IndexError, zipfile.BadZipFile, RuntimeError, struct.error) as error:
        report["failures"].append(str(error))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outer", type=Path, required=True, help="Downloaded outer GitHub artifact ZIP")
    parser.add_argument("--expected-outer-sha256", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--tree-sha", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    for name, length in (("expected_outer_sha256", 64), ("source_sha", 40), ("tree_sha", 40)):
        value = getattr(args, name).lower()
        if re.fullmatch("[0-9a-f]{%d}" % length, value) is None:
            parser.error(name.replace("_", "-") + " must be an exact hexadecimal identity")
        setattr(args, name, value)
    report = verify(args)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.report.with_name(args.report.name + ".tmp")
    temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    temporary.replace(args.report)
    summary = {key: report[key] for key in ("payload_status", "workflow_qualification_status", "overall_status", "failures")}
    summary["workflow_failures"] = report.get("workflow", {}).get("failures", [])
    print(json.dumps(summary, indent=2))
    return 0 if report["overall_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
