#!/usr/bin/env python3
"""Compare every Godot-imported historical input/weight to Python binary64 bits."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    raw = (repo / "app/data/synthetic_foundry.json").read_bytes()
    raw_sha = hashlib.sha256(raw).hexdigest()
    expected_sha = "745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c"
    if raw_sha != expected_sha:
        raise ValueError(f"Historical specimen hash mismatch: {raw_sha}")
    specimen = json.loads(raw)
    values = specimen["input"] + [
        value for matrix in specimen["weights"] for row in matrix for value in row
    ]
    expected = struct.pack(f"<{len(values)}d", *values)
    with tempfile.TemporaryDirectory(prefix="xenovection-numeric-") as directory:
        output = Path(directory) / "godot-f64.bin"
        command = [
            args.godot,
            "--headless",
            "--path",
            str(repo / "app"),
            "--script",
            str(repo / "tests/export_source_bits.gd"),
            "--",
            f"--output={output}",
        ]
        run = subprocess.run(command, check=True, capture_output=True, text=True, timeout=60)
        actual = output.read_bytes()
    mismatches = [
        index
        for index in range(len(values))
        if actual[index * 8 : (index + 1) * 8]
        != expected[index * 8 : (index + 1) * 8]
    ]
    passed = not mismatches and len(actual) == len(expected)
    receipt = {
        "suite": "independent-source-binary64-exactness",
        "status": "PASS" if passed else "FAIL",
        "specimen_sha256": raw_sha,
        "input_values": len(specimen["input"]),
        "edge_weights": len(values) - len(specimen["input"]),
        "checked_binary64_values": len(values),
        "byte_count": len(actual),
        "mismatched_values": len(mismatches),
        "first_mismatched_indices": mismatches[:16],
        "expected_binary_sha256": hashlib.sha256(expected).hexdigest(),
        "godot_binary_sha256": hashlib.sha256(actual).hexdigest(),
        "reference": "Python json.loads of the unmodified historical archive specimen, packed as IEEE-754 binary64 little endian",
        "godot_output": run.stdout.strip(),
    }
    text = json.dumps(receipt, indent=2) + "\n"
    print(text, end="")
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(text, encoding="utf-8")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
