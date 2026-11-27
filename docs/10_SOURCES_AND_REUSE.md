# Upstream source index, precise claims and reuse policy

This record is deliberately cautious: studying a shader and copying its code are different operations. Xenovection needs many of the *ideas*, not a wholesale transplant of unrelated runtimes.

## Home and related repositories

- [Xenovection](https://github.com/techrote/Xenovection) — primary graphics and spatial project, newly initialised.
- [RustySpork Neurotzacken](https://github.com/techrote/rustyspork-neurotzacken) — separate headless LLM weights, pruning, reblitteration and evaluation research; previously hosted speculative FRANKENFIELD UI design notes.
- [XenoField](https://github.com/techrote/XenoField), [web demo](https://techrote.github.io/xenofield/) — native WebGPU experimental FX/reference renderer, source of SkySynth, FFT surfaces, scene auxiliary, volumes, temporal feedback and WEATHER ENGINE observations.
- [PlasmaTerm](https://github.com/techrote/PlasmaTerm), [published browser edition](https://techrote.github.io/plasmaterm/web/) — original sine-wave plasma synthesis, smooth LUTs, control panel.
- [CyberSand](https://github.com/techrote/cybersand) — potential future consumer of generic backgrounds/overlays; not to be modified from this programme.

## Actual XenoField modules to inspect

- docs/V4.4a-ARCHITECTURE.md — render graph and ownership, SceneAux depth/normals, XenoVolume clocks, temporal isolation and quality budgets.
- docs/V4.4b-PROCEDURAL-CLOUDS.md — cached world volume, cinematic cellular/membrane extreme preset, independent Ray/Light/Density.
- src/render/renderer.js — device, HDR, scene and render budget ownership.
- src/render/kinetic/scene-aux.js — metric depth and normals.
- src/render/kinetic/xenovolume.js and volume-shaders.js — cache and raymarch.
- src/render/kinetic/procedural-cloud.js and procedural-cloud-shaders.js — source-like procedural cloud instrument.
- src/render/kinetic/temporal.js — independent histories.
- src/render/kinetic/compositor.js and effects-shaders.js — masks, bloom, displacement/composite, LUT and feedback.
- src/core/kinetic-parameters.js / kinetic-presets.js — bounded parameters and reproducible presets.
- src/environment/pattern.js and src/render/shaders.js — environment synthesis / shader algorithms.
- src/mesh/mesh-tools.js — relevant when evaluating arbitrary mesh conditioning/displacement.

**Critical:** the very specific WATER/WEATHER ENGINE path and surface-deformation implementation still require targeted source inspection before claiming how displacement is computed. Screenshots alone cannot prove that topological tearing occurs.

## Actual PlasmaTerm architecture examined

- Main README + docs/external-control.md: main Windows-Terminal release uses watched INI config; explicitly not a high-rate socket protocol.
- plasma.py native: four-wave sine field, hue LUT, live config.
- techrote.github.io/plasmaterm/plasma.py and web/plasma-worker.js / plasma-browser.js: newer browser UI with transient energy fields, wave functions, target masks, offset and worker.postMessage.
- The owner reports an additional WebSocket-based offset controller. **Do not pretend a verified endpoint or message schema was found in the published main code.** Locate the actual producer/server or treat compatibility as unverified.

## External visualiser / weight tool landscape

Previous research considered TokenPrint (Three.js/React Three Fiber 3D visualiser), LLM-Viz, Vespasian, Oumi Weights Lab, weightprog, Steer2Edit, SAELens, NNsight, mergekit, Weights Viz and other tensor editing/diff tools.

The outcome of that review was **not** that Xenovection should fork a browser graph visualiser. They may be scientific or file-interface donors later. The defining research opportunity is GPU-native artistic directness, procedural fields and microtexture, not merely drawing neural topology with spheres, boxes, splines and dashboards. RustySpork may independently select numerical backend tools.

## Licensing / reuse checks

- PlasmaTerm's published root LICENSE is **GNU AGPL-3.0**. Reusing source or derivatives may bring copyleft/compliance requirements. Mere reference to mathematical ideas is different from copying program code; evaluate concrete files before porting.
- The inspected XenoField main-tree listing had **no root LICENSE file**. Its THIRD_PARTY_NOTICES.md identifies MIT upstream procedural-cloud contributors. **Do not assume all XenoField source is MIT or automatically sublicensable merely because some borrowed algorithms carry MIT notices.** Confirm the owner's rights, original authorship and third-party restrictions before copying any code into Xenovection.
- Godot 4 engine licences and any native plugins, shader assets, generated textures and example media need their own notices as appropriate.
- The standalone FOUND-001 archive was generated for this research; preserve its source provenance and independently inspect any included external assets/dependencies.
- Do not paste user screenshot images or screenshots from external sites into the repo unless their usage/provenance is confirmed; keep an image manifest.

## Engineering rules of reuse

Prefer:
1. Reproducing tiny mathematical field functions with correct attribution and source comparison.
2. Adapting isolated, well-documented shader techniques after rights/dependency review.
3. Keeping XenoField's asset/rendering graph separate from Godot's scene lifecycle.
4. Benchmarking equivalent visual effects on the actual hardware before promising an optimisation.

Avoid:
- vendoring a 2MB+ standalone XenoField HTML wholesale;
- embedding a Python/ANSI PlasmaTerm renderer to produce textures each frame;
- requiring full model inference just to run the art engine;
- running both model inference and unbounded volumetric effects on the same constrained GPU;
- copying CI scaffolding from other repositories.
