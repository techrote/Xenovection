# FOUND programme — accepted experiments and planned work

The original ZIP from the prior design dialogue was named **FRANKENFIELD-FOUND-001-Godot47-FIXED.zip**. It pre-dated the independent Xenovection repo. The historical name should remain attached to evidence. The original source archive was not yet committed here; do not claim it is available in this repository until imported.

## FOUND-001 — Coupled-Field Study

**Status:** source delivered; native Windows Godot 4.7 screenshots supplied by owner; numerical verifier rerun successfully on 23 November 2026; frame-rate/VRAM not yet qualified.

### Implementation facts from original fixed archive
- Godot 4.7 Forward+, native Vulkan intention; independent Godot main scene/script.
- 6 layer populations × 48 channels = 288 indexed nodes.
- 5 dense 48×48 matrices = 11,520 exact stored synthetic weights.
- Deterministic dataset in a JSON specimen, name Coupled Tanh Foundry.
- tanh MLP forward pass; each selected input channel injects ±0.125 perturbation; two forward passes produce finite difference deltas.
- Each displayed exact connection corresponds to W[layer][output][input], with omitted weak connections under |weight| < 0.024.
- Modes: 1 fixed signed-weight structure, 2 measured finite-difference response (default), 3 hybrid.
- Signed connection contribution uses W[layer][output][input] × delta_h[layer][input], **not** downstream delta sign.
- Screen positions, bends, normalised pulses, glow/shimmer, bristles and stars are artistic choices, **not** neural-space geometry.
- A verified exact initial input-channel picker and WASD/mouse-look free flight; no arbitrary tensor/edge selection or real weights.

### Visual observations/QA
Owner supplied three working screenshots and a close-up: dense red/cyan fine lines crossing in a nearly black void, mostly overlit cyan/coral node spheres, white selected input. Visual aesthetic positively accepted. Owner requests **smaller spheres** and **remove all whisker/stub protrusions**. Preserve thin-line capability and investigate higher travel/twist movement. Dense filament close-up is a valuable baseline for future layer compositing.

### Reproduced numerical checks
Running the archive's Python test on 23 November 2026 yielded:
- Specimen SHA-256: **745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c**
- Matrix shape: (5,48,48), 11,520 precise coefficients.
- 48 perturbation probes checked.
- Analytic/finite-difference maximum error: **4.787e-11**.
- Result: PASS deterministic shapes, finite values, finite differences and forward response.

The source ZIP SHA-256 observed in the working environment: **ebb3df3a271cdd2e3294d812392e4e5d03d666761d1f5ee8d5b5c90f3954d362**. Preserve this identifier when migrating the artifact.

### Historical parser correction
The first package failed to launch because GDScript keyword **signal** was used as a variable on main.gd line 292; changed to **signed_flow** at that assignment and later references. The FIXED archive shows the repaired script; owner screenshots follow the correction. No proof that every GDScript behaviour or GPU mode has undergone full acceptance.

### Controls in fixed source
- Left click first-layer node to select; bracket keys or arrow keys to cycle inputs.
- Right click to capture/release mouse; WASD, Q/E, Shift and mouse wheel for flying.
- 1/2/3 for modes; P reverses input delta sign; F looks at selected channel; F1 overlay toggle; Esc releases mouse.

### Packaging boundary
The original archive includes project.godot, main.tscn, main.gd, make_specimen.py, data/synthetic_foundry.json, tests/verify_specimen.py and README. It is an externally delivered source archive, not currently a Xenovection checked-in Godot app. Import from the **fixed** archive and preserve the original original specimen/test receipt; avoid inventing a reimplementation.

## FOUND-002A — Filament Kinetics

**Status: proposed; first build priority.**

Implement smaller nodes and no whiskers; deliberate thin-line AA/coverage; endpoint-preserving traveling wave displacement; braid/torsion; independent counterflow; luminous phase travel on static paths; coherent regional resonance; optional compact PlasmaTerm colour drift. Provide toggles and benchmark every effect against FOUND-001.

**Acceptance:** recognizable/traceable exact connections in no-FX mode; no accidental node whiskers; pauses/reverses reproducibly; no unwarranted geometry rebuild on every animation frame; owner screenshots/video and frame-time measurements.

## FOUND-002B — Reflective Surface Lab

**Status: proposed, parallel aesthetic study.**

Add one contained reflective knot/bundle or membrane from a selected subgraph. Demonstrate fixed mesh with animated environment lighting vs actual vertex displacement vs detailed normal animation vs domain warp. Reference XenoField preset **6 ECONOMY INTERACTIVE** and WEATHER ENGINE normal/max displacement examples, plus PlasmaTerm smooth LUTs.

**Acceptance:** independent A/B effect isolations, controlled finite displacement, visually compelling optics, no requirement to turn the whole network into fat cylinders, actual GPU timing and memory.

## FOUND-002C — Hybrid Reveal

**Status: proposed after 002A/B.**

A selected primary filament population transitions into bundle ribbons, dynamic membrane or knot proxy while all original connections remain available; retain exact selection IDs. Composition across thin lines, reflective surfaces, environment and volume with individually adjustable opacity/depth hierarchy.

**Acceptance:** source addresses survive visual morph and layer toggle; one-click return to exact no-FX view; no forced LLM dependency.

## FOUND-003 and beyond (not authorised implementation)

- Modular control-voltage/modulator bus; external localhost WebSocket offset transport after schema verification.
- XenoField-inspired optical/volumetric experiments; skybox as shared animated lighting source.
- Optional real-data adapter snapshots, measured activations, tensors, live probes and selection references.
- Optional render-only CyberSand backgrounds/overlays, with independent dependency and performance qualification.

Avoid prematurely committing to a large-engine rewrite or headless CI testing every artistic parameter. Experimental graphics should first be seen and measured on actual Windows hardware.
