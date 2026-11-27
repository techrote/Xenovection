# Execution plan, research priorities and acceptance gates

**Status 23 November 2026:** design and FOUND-001 external source, no running Xenovection app inside the new repo. This is a deliberately ambitious artistic programme, but process overhead must remain subordinate to visible results.

## Phase P0 — custody and independent repo foundations
- Preserve charter, image ledger, diagram vs truth boundaries, source links and this plan.
- Import the existing **fixed** FOUND-001 Godot 4.7 archive to a clearly marked experimental path (e.g. experiments/found-001/), including exact data and Python numerical test. Do not silently regenerate or alter specimen.
- Preserve source ZIP and specimen hashes in the record; author/owner review of original ZIP before claiming source-exact port.
- Small starter README/run instructions; no generic CI/workflow scaffolding unless a specific test proves it necessary.

Exit: can open the checked-in project on Windows Godot 4.7, view original composition and reproduce the numerical test.

## Phase P1 — FOUND-002A: protect and animate the filigree
- Make node spheres radically smaller; remove whisker/stubs.
- Distinguish exact primary edges from decorative secondary fibres and temporal traces.
- Motion studies: phase-travel, transverse travel, counterflow, torsion/braid, regional resonance; additive separate controls for rate and amplitude.
- Small/no-FX, medium/multiwave and dense/showcase presets.
- Video evidence: substantial apparent motion without producing a generic glowing fog.

Exit: owner visually accepts thin lines and movement; no-FX still maps exact connection IDs; no catastrophic CPU geometry regeneration/temporal smear.

## Phase P2 — FOUND-002B: SkySynth spectral reflective knot and WEATHER ENGINE deformation
- Recreate or port the deterministic PlasmaTerm-inspired wave field into native shader uniforms, with cyclic LUT and phase drift.
- Provide static geometry + changing environment control, and geometry displacement/normal-only/reflection-only A/Bs.
- Use selected bounded knot, ribbon/membrane, and arbitrary mesh demo objects.
- Compare XenoField preset 6 ECONOMY INTERACTIVE and user-provided WEATHER ENGINE normal/max visuals (source-faithful when feasible).
- Controls for X/Y frequency, diagonal, radial, speed, pan/rotation/warp, contrast, HDR radiance, palette, roughness, normal strength and displacement; separate clocks.

Exit: visual evidence shows genuine animated optical changes and optional stable deformation on user target machine; resources/time measured per pass.

## Phase P3 — FOUND-002C: compositional hybrid
- Combine hairline base, braided secondary fibres, selected reflective knot/membrane and optionally low-cost background.
- Provide level-of-detail and independent effect toggles; never force all connections into shiny tubes.
- Direct reveal/materialise/isolate of region with stable IDs.
- Compare no-FX vs art vs hybrid and frame-time regression.

Exit: high-fidelity close-up + wide shot, readable selection, controlled memory/latency, one-click no-FX reset.

## Phase P4 — Modulation bus and optical orchestration
- Universal source/target matrix with multiple additive, multiply and mask routes, smoothing, limits and phase.
- LFO/loop noise/wander, manual gestures, envelopes; deterministic automation recorder and presets.
- Verify actual PlasmaTerm/WebSocket modulator contract or implement a **new** documented localhost protocol without claiming compatibility.
- Independent slow environment and faster local field clocks, bounded latency, graceful disconnect.

Exit: one scalar external offset visibly and measurably drives separate sky, filament and volume/material targets; renderer never receives full rendered frames.

## Phase P5 — Volumes, complex spatial data and runtime adapters
- Introduce optional cached volume (density/light/structure/emission) and selective reflection/transparency with performance budget.
- Real but non-LLM data source first: e.g. synthetic graph/time-series or simple simulation; validate selection mapping.
- Optional RustySpork read-only activation/perturbation taps with provenance and replay.
- Data import architecture supports more domains than transformers; source-exact selection and scientific mode.

Exit: source adapter receives measurement without GPU stalls; exact selection reference checked against source; no model loading inside viewer.

## Phase P6 — Reusable output and ecosystem
- Export standalone visual scenes/presets, transparent overlays and controlled render/textures.
- Explore CyberSand consumer module as a later independent project; never add it to CyberSand by default.
- Explore browser/native WebGPU variation separately if justified by creative requirements/performance, not merely because a web framework exists.

## Ground rules for every milestone

| Gate | Minimal evidence |
| --- | --- |
| Real effect | screenshot/short video of actual executable, not an AI mock-up |
| Directness | user interaction works without long pauses |
| Provenance | effect labelled data-measured, derived or artistic |
| Runtime | exact Godot version, OS/GPU, no parse/runtime errors |
| Performance | FPS and p95 frame time on same hardware at same resolution, plus rough resource use |
| Isolation | per-effect toggle and a neutral baseline; disable doesn't cost a full effect pass |
| Recoverability | save preset/source SHA and undo artistic changes |

## Avoid needless CI
No expansive test-of-test architecture, no forced release matrix, no massive model downloads, no Linux-only graphic acceptance pretending to prove Windows NVIDIA results. Use a handful of deterministic CPU maths tests plus local render smoke checks as justified, and make owner-local visual evidence the primary acceptance.

## Decision gates (not automatic stage promotion)
- Engine: Godot first, reconsider standalone Vulkan/WebGPU only after comparative profiling.
- Source code reuse from PlasmaTerm/XenoField: verify licensing and legal provenance first.
- Exact real-model data mapping: requires verified adapter contract; absent by default.
- Model modification: owned by RustySpork, never Xenovection.
- No mergers or cross-project code import without explicit owner instruction.
