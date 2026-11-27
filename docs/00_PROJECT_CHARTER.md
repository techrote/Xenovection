# Xenovection — project charter and ownership

**Decision date:** 23 November 2026. **Status:** founding design record. Former provisional visual-workstation name: *FRANKENFIELD*. The actual standalone repository/project is **Xenovection**. FRANKENFIELD may remain a named artistic mode or historical design programme, but must not be mistaken for the repository name.

## Vision

Invent a high-performance, aesthetically ambitious, interactively navigable visual language for multidimensional, relational, time-varying and semantic data. An operator should be able to enter complex structures as though exploring a game world, fly through them, pick and manipulate elements directly, and experience a living system rather than a matrix viewer or node/edge dashboard.

The founding examples were selected from hundreds of Stable Diffusion images by the owner: glowing intricate filament networks, spiderweb/fibre topology, coloured energetic volumetrics, and extraordinarily dense microtexture. A later **working** Godot field-study demonstrated a dense fine-line network that the owner described as visually compelling. The subsequent XenoField screenshots showed SkySynth/PlasmaTerm animated HDR environments driving unexpectedly rich surface response, reflective knots, WEATHER ENGINE displacement, torn-looking membranes and animated optical complexity. See visual evidence register.

### Not an LLM editor

The original motivation was visualising neural weights, but that is explicitly **not** the owning scope. RustySpork handles mechanistic numerical work. Xenovection independently invents spatial representations, real-time procedural effects and interactive synthesis. It should support numerical tensors, graphs, physics/simulation streams, arbitrary time series, hand-authored art and empty-scene synthesis alike.

## Design axioms

1. **Filigree is a protected first-class medium.** Fine lines, microfibres and transparent interwoven connections must remain viable at scale even after reflective solids, raster FX, volume and surface systems arrive.
2. **Compositional rather than exclusive.** A dataset can simultaneously appear as strands, ribbon bundles, surfaces, spectral structures, environments and volumes; each interpretation can be disabled without loss of the underlying data.
3. **Art and measurement are separable.** Scientific data has exact source references, aggregation methods, coordinate systems, timestamps and confidence. Decorative waves, glows, and inferred geometry are identified as such. Never suggest physical neural anatomy where there is none.
4. **Controls feel like instruments.** Direct pointer and keyboard navigation, grabbing, pulling, painting, sweeping through, lassoing, orbiting, teleporting, isolating and patching modular visual systems.
5. **Modulation is universal.** Every relevant generator, transform, layer, colour transfer function and material parameter may receive bounded time-varying signals; multiple sources may sum or combine, just like a modular synthesiser.
6. **GPU expenditure is intentional.** Quality is measured on real target hardware; preserve interactive frame pacing; isolate expensive reflective, translucent and volumetric passes behind explicit budgets.
7. **Native-first without dogma.** Start with the functioning Godot 4.7 Vulkan testbed. Study native WebGPU XenoField where appropriate. A custom Vulkan renderer may be justified later by evidence. Do not select a Three.js graph visualiser as the primary technical foundation.
8. **No coupled build bureaucracy.** Keep CI minimal and targeted, with Windows GPU owner tests as the acceptance gate for subjective visual effects. No massive generic test matrix.
9. **Negative results remain useful.** Record ugliness, temporal instability, performance collapse and rejected metaphors as research evidence.

## Repository responsibilities

### Xenovection owns
- Render graph, GPU buffers and shaders, scene topology and LOD, materials, HDR environment, thin-line and ribbon renderers.
- Wave synthesis, deterministic procedural fields, modulation matrix, continuous LUTs, optical and temporal effects, editable visuals and presets.
- Spatial camera, direct manipulation tools, picking and exact selection addresses within its own datasets.
- Read-only data adapters, source registry, telemetry viewer, replay and provenance-aware visual mappings.
- Screenshot/video reproducibility, visual performance evidence, interactive and aesthetic evaluation.

### RustySpork owns
- Checkpoint and tensor loading/decoding, GGUF/safetensors formats, model runtime/inference, feature probes and activations.
- Surgical algorithms, reblitteration, ablation, prunes/grafts, quantisation, masks validation, patch manifests, model evaluation.
- Authoritative state changes and scientific causal claims.

### XenoField / PlasmaTerm / CyberSand relationship
- XenoField: excellent donor for wave-displaced materials, environment synthesis, SceneAux/depth, volumes, multi-clock caches, feedback, masks and lighting; **not** an automatic dependency.
- PlasmaTerm/its published web fork: wave functions, smooth cyclic 256-colour LUTs, independent modulation controls; the exposed browser worker interface is not a verified direct WebSocket API.
- CyberSand: an eventual **consumer** of standalone visual modules (e.g. background/overlay). Never introduce neural tooling there.

## Product areas

1. **Synthetic field lab** — can run without any external data; explore beauty and controllability.
2. **Spatial atlas** — hierarchical views with explicit mapping of data items and aggregates.
3. **Kinetic filament ecology** — traceable connections with ornamental fibres and motion.
4. **Surface/weather laboratory** — wave displacement, folds, tearing-like distortion, reflective and transparent anatomy.
5. **Environment/modulation instrument** — oscillator banks, phase, palettes and procedural illumination.
6. **Taps and replay** — optional live data effects with measured versus invented channels separated.

## Naming and design record discipline

Use **Xenovection** for new repo, executable and UI. Keep **FOUND-001 / Coupled-Field Study** as the already tested prototype's historical name. FOUND-002A/B/C remain planned experiments. Preserve the *steel marbles / sieves / magical pipes / pressure waves* foundry analogy as a creative cognitive aid, not the model for a literal structural diagram.

Do not declare a feature complete because its design appears in these documents. Each implementation requires its own measured, reviewable evidence.
