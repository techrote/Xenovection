# FOUND-001 preserved source

The exact historical archive was recovered on 26 November 2026. The archive
and every extracted file under `source/` are byte-for-byte copies. Later
Xenovection work is in `app/`; it does not alter this baseline.

| Item | SHA-256 |
| --- | --- |
| `FRANKENFIELD-FOUND-001-Godot47-FIXED.zip` | `ebb3df3a271cdd2e3294d812392e4e5d03d666761d1f5ee8d5b5c90f3954d362` |
| `source/data/synthetic_foundry.json` | `745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c` |

Both match the independent historical record in [issue #3](https://github.com/techrote/Xenovection/issues/3).
The original `signal` → `signed_flow` repair is present.

Rerun: `python3 source/tests/verify_specimen.py` — 48 probes, 11,520 stored
coefficients, maximum analytic/finite-difference error **4.787e-11**, PASS.
Godot **4.7.2.stable.official.ed1daf0bf**, Linux, imports and starts the original
scene in headless mode. This is startup evidence, not graphical qualification.

The historical Windows screenshots are recorded in the founding evidence
ledger. The successor has its own qualification and must not inherit an
unmeasured performance claim from this baseline.
