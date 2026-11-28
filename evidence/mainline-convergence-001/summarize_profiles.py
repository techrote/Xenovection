#!/usr/bin/env python3
"""Summarize every downloaded performance receipt without pooling percentiles."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--tree-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    rows = []
    for path in sorted(args.evidence.glob("*.json")):
        raw = path.read_bytes()
        data = json.loads(raw)
        if data.get("schema") != "xenovection.performance.v1":
            continue
        build = data["build"]
        if build["source_sha"] != args.source_sha or build["tree_sha"] != args.tree_sha:
            raise SystemExit("Profile identity mismatch: " + path.name)
        row = {"file": path.name, "sha256": hashlib.sha256(raw).hexdigest()}
        for key in (
            "composition_id", "preset", "samples", "total_frames", "duration_seconds",
            "viewport", "render_target_pixels", "wall_frame", "application_update",
            "render_cpu", "render_gpu", "gpu_timing_available", "platform",
            "startup_usec", "scene_prepare_usec", "scene_transitions", "workspace_transitions",
            "synthesis", "ecology", "spatial_ecology", "matter", "engine_static_bytes",
            "engine_video_bytes", "source_unchanged", "instrument_clock", "modulation_diagnostics",
        ):
            if key in data:
                row[key] = data[key]
        rows.append(row)
    if len(rows) != 56:
        raise SystemExit(f"Expected all 56 performance profiles; found {len(rows)}")
    report = {
        "schema": "xenovection.convergence-performance-summary.v1",
        "source_sha": args.source_sha,
        "tree_sha": args.tree_sha,
        "profiles_checked": len(rows),
        "scope": "Windows Vulkan Forward+ hosted llvmpipe. These are software-device execution measurements, not physical TITAN RTX throughput.",
        "aggregation": "Each row retains its own sampling interval and percentiles. Percentiles are not pooled across different scenes or runs.",
        "measurement_limits": [
            "Graph timer excludes the surrounding scheduler and bus resolver.",
            "Solver timer excludes snapshot generation; spatial update timer excludes snapshot allocation/deallocation.",
            "Startup begins at application-controller construction, not operating-system process launch.",
            "Transition timing measures synchronous CPU preparation, not time to first visible frame.",
            "Upload bytes are submitted-array estimates, not measured PCIe traffic.",
            "Engine memory counters are not process RSS or total driver VRAM; zero static bytes means unavailable on this runner.",
            "Software device timings do not qualify a physical GPU.",
            "Inherited enabled/disabled optical runs are not phase-matched pixel comparisons.",
        ],
        "profiles": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": "PASS", "profiles_checked": len(rows), "output": str(args.output)}))


if __name__ == "__main__":
    main()
