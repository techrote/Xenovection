# Proposed rendering architecture and performance policy

**Not yet implemented in Xenovection.** This defines modular responsibilities, not a claim of existing shaders.

## Engine decision

FOUND-001 was authored for Godot 4.7 Forward+ native Vulkan, delivered as source and seen running in user Windows screenshots. That is the sensible first executable vehicle. Build a narrow render experiment there first; measure on target Windows GPU before deciding to migrate to a custom Vulkan engine or WebGPU.

XenoField V4.4a/b is a **native WebGPU** procedural shader system. Borrow algorithms and isolation boundaries; do not try to embed its WGSL render graph into Godot unchanged. Three.js graph demos are explicitly not the design baseline for this project.

## Renderer layers (independently toggleable)

1. **Primary geometric truth / base filaments** — depth, topology, exact selected edge metadata, indexed positions.
2. **Kinetic displacement** — stable-id wave transforms and per-strand phase/arc-length controls, applied on GPU where practical.
3. **Secondary filigree / small-scale texture** — procedural fibres and edge microdetail, explicitly decorative.
4. **Ribbons, membranes and solids** — alternative thick/sheet/selected representations, not replacements for base lines.
5. **Optical materials** — reflection from SkySynth environment, roughness/normal microstructure, refraction approximations, emission.
6. **Volumetric field** — cached density/light/structure/emission, low-resolution raymarch + depth-aware composition.
7. **Temporal/compositor** — stable scene accumulation and separate optional artistic feedback, colour/LUT, positive/dark bloom, lens distortion.
8. **Inspection and selection overlays** — exact object IDs, source provenance, masks, labels and no-FX view; must remain readable.

Render graph design must prevent sampling the same image as producer and consumer in one cyclic pass. Keep source textures owned by well-defined stages. Modular lifecycle includes allocate-on-enable, release-on-disable, device loss, resize and camera-cut invalidation.

## Direct XenoField references (verify ports)

See [XenoField V4.4a architecture](https://github.com/techrote/XenoField/blob/main/docs/V4.4a-ARCHITECTURE.md) and [V4.4b procedural clouds](https://github.com/techrote/XenoField/blob/main/docs/V4.4b-PROCEDURAL-CLOUDS.md):

- SceneAux: metric ray-depth and normals/energy for masks and depth-aware compositing.
- XenoVolume: bounded 3D caches with R density, G cached light, B structure, A emission; due-rate density/light clocks; generation interpolation and low-resolution raymarch.
- Temporal: distinct conservative scene, volume and **artistic** feedback histories; motion/camera reprojection and rejection.
- Compositor: depth, masks, signed/positive/dark bloom, colour/LUT and visual feedback.
- SkySynth: animated environment and reflective source. Environment generation rate can differ from frame rate.
- Cloud instrument: procedural cache that can make perforated cellular membranes (see VIDEO · CELL MEMBRANES preset), not merely cloudy fog.
- Quality estimator: target dimensions, texture bytes, MSAA/SSAA area, temporal and filter costs; GPU timing identities.

These are examples of known systems in the reference project, not guarantees of portable accuracy or performance.

## Mesh distortion and optical fidelity

Provide separate independent controls for:
- geometric position displacement;
- local normal/detail perturbation;
- UV/domain warp of the environment/material sample;
- surface material response;
- background/environment wave animation.

This allows diagnosing what looks like physical flow but may really be changing highlights. Vertex motion on arbitrary topology needs limits, bias toward finite displacement, near-plane and self-intersection inspection. Tearing-*like* appearance can be purely displacement/UV masking. Actual topology tearing requires explicitly new connectivity and a different validation gate.

For reflective filaments, sample an animated environment rather than ray-tracing each strand; add selective expensive reflections only if measured cost justifies them. Subpixel hairlines may benefit more from careful luminous coverage and anti-aliasing than material shading.

## Performance doctrine

- Target interaction responsiveness **before** unbounded visual fidelity. Practical aspirational frame-rate modes: quality-stable 60 FPS and optional 120 FPS when supported; these are goals, not reported measurements.
- Separate scene-frame rate from field synthesis cadence, environment rebuild cadence, volume density/light cadence, data-tap update cadence and screenshots/export.
- Time the passes independently. Provide visible active/idle stages, FPS/frame-time percentiles, GPU resource estimate, render resolution, counts/LOD and memory-budget headroom.
- Use lazy geometry/tile streaming and bounded pool sizes; keep the camera/UI responsive while data adapters parse.
- Never allocate billions of weights as graphics objects. Build measured multiresolution summaries and exact selection lookup where needed.
- For large-model use, assume concurrent inference can consume virtually all GPU memory; support disabling material/volume paths, graphics memory budget and sequential capture if necessary.
- Have three quality tiers: diagnostic no-FX (exact lines and IDs), interactive mixed quality (selected passes), showcase (highest art but explicitly non-acceptance for frame-rate).
- Validate all screen-space line thicknesses against different resolutions and zooms; AA and transparent blending order are primary correctness/perceptual concerns for dense filigree.
- Use reproducible scene presets, fixed random seeds and capture timestamps to compare performance fairly.

## Test priority

1. Same scene: tiny nodes without whiskers; establish clarity and frame time.
2. Oscillating/stationary filament A/B with fixed IDs and endpoints; verify no full-mesh CPU regeneration.
3. Add separate reflective ribbon/knot; toggle environment vs material vs geometry effects.
4. Add analytical PlasmaTerm field as GPU uniform shader, compare fixed/animated lighting.
5. Add bounded volume and temporal histories only after establishing a clean performance baseline.
6. Capture screenshots, short video and actual measured frame-time/p95, GPU/VRAM for every interesting preset.

Do not build an elaborate CI infrastructure. Small syntax/unit checks are appropriate; render acceptance belongs to owner Windows GPU testing and visual evidence.
