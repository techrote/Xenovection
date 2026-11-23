# Handoff brief for implementation agents

## Mission summary
Build **Xenovection**, a genuinely ambitious, performance-aware, GPU-native visual synthesis and direct spatial exploration environment. Use the original Godot 4.7 FOUND-001 synthetic network as the first executable baseline; preserve its mathematical provenance and admired hairline look. Do not begin by reconstructing yet another 3D graph dashboard or by importing LLM weights.

## Do this next
1. Import the exact **fixed** FOUND-001 source archive to experiments/found-001, preserving test file, JSON specimen and SHA receipt. Retain functional Godot 4.7 launch and numerical test. If unavailable to implementation environment, explicitly state that and avoid inventing source from memory.
2. Ensure the original native scene runs on Windows; do not introduce old GDScript reserved keyword signal as a variable.
3. Implement tiny node rendering and remove the protruding whiskers/stubs; keep the original fine-line geometry. Make no-FX baseline visually inspectable.
4. Implement GPU-side independent filament phase travel and controlled geometry waves; include braiding/counterflow and pause/reverse with deterministic seeds. Don't rebuild all vertices on CPU merely to animate.
5. Add separate proof-of-concept reflective surface/knot with animated PlasmaTerm-like environment, cyclic LUT and opt-in wave-displacement, normal and sampling-domain warp. Split mechanisms into independently toggleable controls.
6. Integrate hybrid composition and direct selection only after these individual experiments are measured.
7. Record 1-2 screenshots per mode, a short motion capture, actual Windows GPU timing/VRAM and negative results. Source-backed performance claims only.

## Must keep separated
- RustySpork: tensor/model/weight editing; headless numerical experiments.
- XenoField: independent original WebGPU project; no wholesale vendoring or cross-repo edits.
- PlasmaTerm: independent source and browser version; study/port with AGPL and other licences checked.
- CyberSand: no changes from this mission, potential later consumer.

## Quality priorities
Visually striking *thin lines* at arbitrary zoom, independent kinetic motion, reflective microgeometry, responsive animated fields, volumetric depth as optional budgeted enhancement. Smooth interactive controls, independent signal routing, easy presets, precise UI, no giant node spheres or whiskers.

## Validation
Original FOUND-001 numerical verifier must pass (48 input probes; analytic vs finite differences). Run Godot parser/startup check where available, then Windows GPU owner acceptance. Shader timing and frame stability measured for effect toggles. Avoid fake proof from static renders or source-only assertions.

## Development process
Short focused Draft PR(s), no merges without owner direction, no sprawling CI. Keep docs as foundational requirements but allow artistic experimentation with measured outcomes to change implementation choices. State explicitly what's implemented versus proposed.
