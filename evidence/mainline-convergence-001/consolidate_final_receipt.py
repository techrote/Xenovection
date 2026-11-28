#!/usr/bin/env python3
"""Bind complete executable, archive, profile and actual-image reviews to one build."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

SUITES = [
    ("core-contracts", "test_core", 71),
    ("integrated-contracts", "test_integration", 81),
    ("filament-contracts", "verify_filaments", 34),
    ("optical-contracts", "verify_optical", 62),
    ("matter-contracts", "test_matter", 30),
    ("synth-contracts", "test_synth", 53),
    ("ecology-contracts", "test_ecology", 81),
    ("composition-contracts", "test_compositions", 69),
    ("convergence-contracts", "test_convergence", 68),
    ("spatial-ecology-contracts", "test_convergence_ecology", 103),
    ("matter-optics-contracts", "test_matter_optics", 44),
]
GUI = {"gui-material": 42, "gui-spatial_ecology": 60, "gui-convergence": 90,
       "gui-input": 37, "synth-gui": 10, "ecology-gui": 23}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def assertion_receipt(path, expected):
    matches = []
    content = path.read_text(encoding="utf-8-sig")
    for line in content.splitlines():
        if "{" not in line:
            continue
        try:
            value = json.loads(line[line.index("{"):])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and "checks" in value:
            matches.append(value)
    # These two inherited suites deliberately emit a fixed textual summary.
    for match in re.finditer(r"^ECOLOGY_CONTRACTS (\d+) PASS / (\d+) FAIL\s*$", content, re.MULTILINE):
        passed, failed = map(int, match.groups())
        matches.append({"checks": passed + failed, "failed": failed,
                        "failures": [] if failed == 0 else ["Ecology assertion failure"]})
    for match in re.finditer(r"^CONVERGENCE_ECOLOGY (\d+)/(\d+) PASS; (\d+) FAIL\s*$", content, re.MULTILINE):
        passed, checks, failed = map(int, match.groups())
        require(passed + failed == checks, "Inconsistent ecology assertion summary")
        matches.append({"checks": checks, "failed": failed,
                        "failures": [] if failed == 0 else ["Spatial ecology assertion failure"]})
    require(len(matches) == 1, "Expected one assertion receipt in " + path.name)
    value = matches[0]
    require(value["checks"] == expected and value.get("failures") == []
            and value.get("status", "PASS") == "PASS" and value.get("failed", 0) == 0,
            "Assertion failure/count mismatch in " + path.name)
    return {"file": path.name, "sha256": sha(path), "checks": expected, "status": "PASS"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--artifact-meta", type=Path, required=True)
    args = parser.parse_args()
    source = args.evidence
    output = args.output_dir
    meta = read(args.artifact_meta)
    verify = read(output / "independent-download-verification.json")
    qualification = read(source / "qualification.json")
    require(meta["workflow_conclusion"] == "success", "Workflow has not completed successfully")
    require(verify["overall_status"] == "PASS" and qualification["status"] == "PASS",
            "Complete independent qualification has not passed")
    app, tree = meta["source_sha"], meta["tree_sha"]
    require(verify["source_sha"] == qualification["source_sha"] == app
            and verify["tree_sha"] == qualification["source_tree"] == tree,
            "Executable/source/tree identity mismatch")
    require(verify["outer"]["sha256"] == meta["outer_sha256"]
            and verify["outer"]["bytes"] == meta["outer_bytes"], "Uploaded/downloaded archive mismatch")
    suites = []
    for source_stem, extracted_stem, expected in SUITES:
        suites.append({"suite": extracted_stem,
                       "source": assertion_receipt(source / (source_stem + ".log"), expected),
                       "extracted": assertion_receipt(source / ("extracted-" + extracted_stem + ".log"), expected)})
    gui = []
    for name, expected in GUI.items():
        path = source / (name + ".json")
        data = read(path)
        require(data["checks"] == expected and data["failures"] == []
                and data.get("status", "PASS") == "PASS", "Graphical assertion failure: " + name)
        gui.append({"file": path.name, "sha256": sha(path), "checks": expected})
    soak = read(source / "extracted-soak.json")
    require(soak["status"] == "PASS" and soak["checks"] == 20
            and soak["simulated_steady_frames"] == 36000, "Full soak is incomplete")
    bits = read(source / "extracted-source-binary64-exactness.json")
    require(bits["status"] == "PASS" and bits["checked_binary64_values"] == 11568
            and bits["mismatched_values"] == 0, "Exact scientific values changed")
    profiles = read(output / "performance-summary.json")
    require(profiles["profiles_checked"] == 56 and profiles["source_sha"] == app
            and profiles["tree_sha"] == tree, "Incomplete profile identity coverage")
    for row in profiles["profiles"]:
        require(sha(source / row["file"]) == row["sha256"], "Profile hash mismatch: " + row["file"])
    reviews = []
    reviewed = {}
    for name, count in (("source-synth", 17), ("matter-optics", 30), ("ecology", 18)):
        path = output / ("visual-review-" + name + ".json")
        review = read(path)
        require(review["status"] == "PASS_FOR_CAPTURE_REVIEW" and not review["blocking_visual_findings"],
                "Outstanding visual finding: " + name)
        require(review["qualified_application_sha"] == app and review["source_tree_sha"] == tree,
                "Visual review identifies a different executable: " + name)
        require(len(review["images"]) == count, "Incomplete assigned visual population: " + name)
        for image in review["images"]:
            filename = image["file"]
            require(filename not in reviewed, "Duplicated primary review image: " + filename)
            require(sha(source / filename) == image["sha256"], "Reviewed PNG hash mismatch: " + filename)
            reviewed[filename] = {"file": filename, "sha256": image["sha256"], "review": path.name}
        reviews.append({"file": path.name, "sha256": sha(path), "images": count})
    actual_pngs = {p.name for p in source.glob("*.png")}
    require(set(reviewed) == actual_pngs and len(reviewed) == 65, "Visual reviews do not cover all65 captures exactly once")
    coverage = {"schema": "xenovection.final-visual-coverage.v1", "status": "PASS",
                "source_sha": app, "tree_sha": tree, "images_checked": len(reviewed),
                "scope": "Actual specialist capture inspection with source/tree/image hash binding; physical owner acceptance remains pending.",
                "reviews": reviews, "images": [reviewed[name] for name in sorted(reviewed)]}
    (output / "visual-coverage.json").write_text(json.dumps(coverage, indent=2) + "\n")
    receipt = {"schema": "xenovection.mainline-convergence-final.v1", "mission": "MAINLINE-CONVERGENCE-001",
               "recorded_at_utc": datetime.now(timezone.utc).isoformat(), "status": "QUALIFIED_DRAFT_HOLD",
               "physical_gpu_qualified": False, "owner_visual_acceptance": "Pending owner evaluation",
               "source_sha": app, "tree_sha": tree, "artifact": meta,
               "inner_zip": verify["inner"], "embedded_build": verify["build"],
               "payload_files_verified": verify["payload_files_verified"],
               "workflow_gates_passed": len(qualification["steps"]),
               "source_assertions_passed": sum(row[2] for row in SUITES),
               "extracted_assertions_passed": sum(row[2] for row in SUITES),
               "graphical_assertions_passed": sum(GUI.values()),
               "structural_suites": suites, "graphical_suites": gui,
               "full_soak": soak, "exact_values": bits,
               "performance_profiles_verified": 56, "visual_captures_reviewed": 65,
               "independent_verification_receipt_sha256": sha(output / "independent-download-verification.json"),
               "visual_coverage_sha256": sha(output / "visual-coverage.json"),
               "remaining_authority": "PR18 stays Draft/HOLD; protected branches and main remain unchanged. No automatic merge, Ready promotion or physical owner acceptance."}
    (output / "mission-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"status": receipt["status"], "source_assertions": receipt["source_assertions_passed"],
                      "extracted_assertions": receipt["extracted_assertions_passed"],
                      "graphical_assertions": receipt["graphical_assertions_passed"], "reviewed_pngs": len(reviewed)}))


if __name__ == "__main__":
    main()
