# Xenovection

**A native-GPU playground for procedural visual synthesis, dense spatial information and direct, game-like interaction.**

Xenovection is an **independent visual instrument and experimental art engine**, not an LLM model editor and not an ANN-specific visualiser. It must be impressive and useful with synthetic, recorded or arbitrary live data, or with no data connected. Its defining materials are ultra-fine filaments, oscillating fields, animated environment illumination, continuous colour LUTs, reflectance/refraction, mesh displacement, translucent membranes and volumetric phenomena.

**Primary design stance:** keep the extremely thin line-and-filigree representation intact. Add rich surfaces, materials and volumes as separate opt-in layers; do not substitute shiny opaque shapes for the successful fine-line experiment. Make the whole environment directly manipulable. Modulation is a first-class compositional instrument, not an afterthought.

The initial concrete renderer candidate is **Godot 4.7 / native Vulkan**, proven to launch on the owner's Windows machine for the synthetic FOUND-001 field study (screenshots supplied 23 November 2026). Investigate selective techniques from [XenoField](https://github.com/techrote/XenoField) (native WebGPU) and [PlasmaTerm](https://github.com/techrote/PlasmaTerm) (including its [web edition](https://techrote.github.io/plasmaterm/web/)); do not assume these codebases share a renderer. Browser/portable rendering is a possible parallel target, not a mandate to use Three.js.

## Start here

| Record | Contents |
| --- | --- |
| [Project charter](docs/00_PROJECT_CHARTER.md) | Mission, ownership, boundaries, product principles and terminology |
| [Visual language](docs/01_VISUAL_LANGUAGE.md) | Filament, field, surface, environmental and volumetric artistic grammar |
| [Renderer and performance](docs/02_RENDERER_AND_PERFORMANCE.md) | Proposed render graph, precision, AA, budgets, instrumentation and native-GPU strategy |
| [Modulation and synthesis](docs/03_MODULATION_AND_SYNTHESIS.md) | PlasmaTerm/SkySynth, parameter bus, LUTs, reactive fields and WebSocket boundary |
| [Data taps and scientific boundary](docs/04_DATA_TAPS_AND_SCIENTIFIC_BOUNDARY.md) | Exact provenance, optional adapters, no hidden LLM dependency, read-only telemetry |
| [Visual references and evidence](docs/05_ARTISTIC_REFERENCE_AND_EVIDENCE.md) | Owner image inventory, UI settings and observation versus verified mechanism |
| [Foundry metaphor and scientific mappings](docs/06_FOUNDRY_MODEL.md) | Mechanical mental model as inspiration, not literal neural anatomy |
| [FOUND prototype record](docs/07_FOUND_PROTOTYPES.md) | FOUND-001 delivered/Windows seen, known parser issue, FOUND-002A/B/C |
| [Interaction design](docs/08_INTERACTION_AND_AUTHORING.md) | Free flight, gesture modulation, selection, drill-down and edit boundaries |
| [Roadmap](docs/09_ROADMAP.md) | Work packages, acceptance, conservative CI and non-goals |
| [Sources and reuse](docs/10_SOURCES_AND_REUSE.md) | Repositories, licensing, technical references and limitations |
| [Architecture decisions](docs/11_ARCHITECTURE_DECISIONS.md) | Accepted boundaries and unresolved design choices |
| [Implementation brief](docs/12_IMPLEMENTATION_BRIEF.md) | Source-exact engineering handoff and acceptance requirements |

## Explicit separation

- **Xenovection** owns appearance, procedural synthesis, rendering, camera/interaction, compositing, display-space and spatial selection.
- **[RustySpork Neurotzacken](https://github.com/techrote/rustyspork-neurotzacken)** owns weights, model loading, activation probes, numerical interventions, checkpoint edits, pruning, reblitteration, evaluation and results. A future source adapter may expose taps and accept *verified* selections, but Xenovection cannot directly mutate a model.
- **[CyberSand](https://github.com/techrote/cybersand)** may optionally reuse independent filaments, atmospheric backgrounds or overlays; no code is to be inserted into CyberSand as a side effect of this programme.
- **XenoField and PlasmaTerm** are references/donors, not dependencies to vendor wholesale without interface and licence review.

## State as of 23 November 2026

Founding research and design documentation. FOUND-001 exists as an earlier standalone Godot 4.7 ZIP, and the owner provided running Windows screenshots. The repo initially contained no code. This documentation records desired features and implementation experiments, **not claims that the future renderer, streaming protocol, surgery adapter, GPU benchmarks or FOUND-002 exist**. No CI workflows, model downloads or cross-repo changes are required for this specification.

## Tracking

- [Draft/HOLD founding PR #1](https://github.com/techrote/Xenovection/pull/1) — this specification; review before merging.
- [Programme / custody #2](https://github.com/techrote/Xenovection/issues/2) and [original Godot source recovery #3](https://github.com/techrote/Xenovection/issues/3).
- [FOUND-002A kinetic filaments #4](https://github.com/techrote/Xenovection/issues/4), [FOUND-002B reflective/weather lab #5](https://github.com/techrote/Xenovection/issues/5), [FOUND-002C hybrid composition #6](https://github.com/techrote/Xenovection/issues/6).
- [Modulation bus #7](https://github.com/techrote/Xenovection/issues/7) and [optional data taps #8](https://github.com/techrote/Xenovection/issues/8).

**Custody note:** The historical fixed Godot 4.7 FOUND-001 ZIP and the user's screenshot originals were available in the founding conversation but are not yet committed as binaries here. Detailed identifying hashes and image names appear in the FOUND record and evidence ledger. This repository's founding PR is intentionally **documentation-only**; do not conflate the code artifact with completed in-repo implementation.
