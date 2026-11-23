# Founding architecture decisions (ADRs)

## ADR-001 — Two separate repos
**Accepted, 23 Nov 2026.** Xenovection is independent from rustyspork-neurotzacken. RustySpork handles weights and experiments; Xenovection handles spatial visualization, direct interaction and artistic systems. Coupling via versioned data taps and exact selection references only. No shared CI or runtime dependency. Never migrate the surgery engine into the renderer.

## ADR-002 — Visual engine not neural-specific
**Accepted.** General multidimensional relational/procedural visual synthesis is the mission. Neural networks are one source adapter, not the core schema. Empty-scene operation and synthetic scenes are first-class.

## ADR-003 — Protect hairline filigree
**Accepted.** Preserve thin lines, denser microfiligree, connectivity clarity and independent kinetic phase/deformation. Reflective bundles, membranes and opaque structures are additive optional layers, not replacement topology. Lower node sphere diameter/remove whiskers in next experiment.

## ADR-004 — Native GPU research path
**Provisional.** The running synthetic FOUND-001 project targets Godot 4.7 Forward+ Vulkan on Windows. Native WebGPU XenoField is a conceptual/technical donor. A custom renderer is a future profiler-driven choice. Three.js/React Three Fiber visualiser forks are not the primary route due to user aesthetic/performance goals.

## ADR-005 — Modular synthesis/optics
**Accepted direction, implementation pending.** Analytical plasma and smooth cyclic LUT can drive both geometry/material properties and an environment map; modulation offsets and multiple LFOs must remain independent of cached base presets. Optics and geometry have separate clocks/controls. SkySynth environment reflections are potentially more valuable than direct texture application.

## ADR-006 — Scientific provenance
**Accepted.** Exact data-truth path, measured/interpolated/fictional layers, selection IDs and immutable source reference. A luminous 'pressure wave' is decorative unless driven by measured delta/probe data with exact trace receipt. Don't treat spatial proximity as intrinsic causality.

## ADR-007 — No automatic editing or cross-repo writes
**Accepted.** Direct manipulating a visual proxy never changes model weights or CyberSand simulations. The owning source validates proposed operations; all cross-project integrations require specific user direction.

## ADR-008 — Sparse process overhead
**Accepted.** New art repo should not accumulate expensive generic CI, build tests testing tests or new acceptance infrastructure unrelated to visible artefacts. Use narrowly scoped numerical/syntax checks and Windows GPU validation. Prefer visual progression and reproducible presets to automation churn.

## Open decisions

- Direct source-accurate PlasmaTerm modulator WebSocket contract? Not yet located in published main/web code.
- Preferred final render backend after Godot prototype profiling?
- Exact shader/material port scope from XenoField and licensing implications?
- First use of measured real non-LLM data source?
- Filament AA strategy and microtexture LOD boundaries?
- Distribution of native executables and a possible WebGPU/browser edition?
