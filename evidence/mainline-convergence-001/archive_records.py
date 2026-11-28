#!/usr/bin/env python3
"""Retain exact non-image Windows receipts in a compact, deterministic archive."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    record_path = args.destination / "qualification-records.zip"
    members = []
    images = []
    with zipfile.ZipFile(record_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(args.evidence.rglob("*")):
            if not path.is_file():
                continue
            name = path.relative_to(args.evidence).as_posix()
            raw = path.read_bytes()
            row = {"file": name, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}
            if path.suffix.lower() == ".png":
                images.append(row)
                continue
            if path.suffix.lower() not in (".json", ".log", ".bin"):
                continue
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 28, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, raw)
            members.append(row)
    data = record_path.read_bytes()
    qualification = json.loads((args.evidence / "qualification.json").read_text())
    index = {
        "schema": "xenovection.archival-evidence-index.v1",
        "source_sha": qualification["source_sha"],
        "tree_sha": qualification["source_tree"],
        "qualification_status": qualification["status"],
        "archive": {"file": record_path.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()},
        "scope": "Exact downloaded JSON receipts, logs and binary64 streams. All original PNGs remain in the separately identified Actions artifact; selected images are also retained beside this archive.",
        "members": members,
        "images": images,
    }
    with zipfile.ZipFile(record_path) as archive:
        for row in members:
            raw = archive.read(row["file"])
            assert len(raw) == row["bytes"] and hashlib.sha256(raw).hexdigest() == row["sha256"]
    (args.destination / "evidence-index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(json.dumps({"status": "PASS", "records": len(members), "pngs_indexed": len(images), "archive": index["archive"]}))


if __name__ == "__main__":
    main()
