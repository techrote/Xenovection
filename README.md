# Xenovection

**A native-GPU playground for procedural visual synthesis, dense spatial information and direct, game-like interaction.**

Xenovection is an **independent visual instrument and experimental art engine**, not an LLM model editor and not an ANN-specific visualiser. It must be impressive and useful with synthetic, recorded or arbitrary live data, or with no data connected. Its founding visual vocabulary includes ultra-fine filaments, oscillating fields, animated environment illumination, continuous colour LUTs, reflectance/refraction, mesh displacement, translucent membranes and volumetric phenomena. The implemented subset is identified below.

**Primary design stance:** keep the extremely thin line-and-filigree representation intact. Add rich surfaces, materials and volumes as separate opt-in layers; do not substitute shiny opaque shapes for the successful fine-line experiment. Make the whole environment directly manipulable. Modulation is a first-class compositional instrument, not an afterthought.

The implementation uses **Godot 4.7.2 / native Vulkan Forward+**. The founding architecture remains below; the integrated application is in [`app/`](app/). XenoField and PlasmaTerm informed the visual direction, while the current shaders and runtime are independent implementations.

## Run FOUND-002

The Windows evaluator is built by [Windows evaluator CI](https://github.com/techrote/Xenovection/actions/workflows/evaluator.yml). Download the artifact for the source revision you want, extract its inner `Xenovection-FOUND-002-Windows-<revision>.zip`, then run **Launch-Xenovection.cmd**. The engine and local content are included. Each package carries `BUILD.json`, payload hashes and a 600-frame owner profiling launcher. See [`START-HERE.txt`](packaging/START-HERE.txt) for the short tour and controls.

To run from source with Godot **4.7.2**:

```sh
godot --path app --editor --import
godot --path app --rendering-method forward_plus --rendering-driver vulkan
```

**Draft/HOLD.** Hosted software Vulkan qualification and the owner's TITAN RTX qualification are separate. A headless test does not establish visual correctness or physical-GPU performance.

| Preset | What to explore |
| --- | --- |
| 1 · Convergence | Exact fine connections surrounding a materialised source region |
| 2 · Counterflow loom | Reversible luminous phase, pinned waves, torsion and opposing secondary fibres |
| 3 · Spectral knot | Moving analytical environment reflected by a selected optical proxy |
| 4 · Weather membrane | Independent normal, reflection-domain and geometric deformation; optional translucency |
| 5 · Scientific / no FX | Straight primary connections, exact IDs and coefficients, decorative passes disabled |
| 6 · Dense interference | 46,080 source edges; the Source tab also offers an 81,920-edge stress specimen |
| 7 · Vortex atlas | 4,608 spatial samples and 6,144 exact streamline/coupling edges from an analytical synthetic field |

Orbit with **MMB**, pan with **Shift+MMB**, zoom with the wheel, or hold **RMB** to fly with **WASD/QE**. Click a source item or drag a through-depth region, then choose **Knot / Ribbon / Membrane / Filaments**. **F** focuses selection, **I** isolates, **G** toggles scientific mode, **Space** pauses, **V** reverses, **R** resets. **F5/F6** save/recall a source-bound scene; **F10** writes measured frame statistics. The Clocks tab separates filament, sky, normal, displacement and palette time.

### Runtime boundaries

Persistent MultiMesh buffers hold exact primary edges separately from decorative fibres. Shader animation does not rebuild strands on the CPU each frame. Analytical optical illumination avoids per-frame cubemap rebuilds. Optical meshes rebuild only when their composition changes. Bounded source snapshots, selection history, replay and performance buffers keep transient visual state separate from immutable source values.

The recovered synthetic specimen has **288 nodes, 11,520 coefficients and 48 inputs**. All 11,568 stored numeric values are checked bit-for-bit against the original JSON. A proxy keeps its complete exact source membership, even when its visible ribbon sample is bounded. The inspector and exports distinguish source values, derived quantities and artistic effects. No model loading, weight surgery or undocumented external transport is implemented.

The optical material uses an analytical reflected-direction field and a roughness approximation. Translucency uses alpha blending. Refraction, ray tracing and volumes remain future experiments; the founding vision below is broader than this first implementation.

### Compact qualification

```sh
python experiments/found-001/source/tests/verify_specimen.py
godot --headless --path app --script ../tests/test_core.gd
godot --headless --path app --script ../tests/test_integration.gd
python tests/verify_source_exact.py --godot godot
```

The historical numerical verifier requires NumPy. The renderer folders contain focused invariant checks; `tests/gui_input_probe.gd` exercises real graphical input. `tools/package_evaluator.py` exports an exact clean source revision using matching official Windows templates. `tools/windows_evaluator.ps1` verifies the archive and runs the extracted Windows executable under explicitly identified software Vulkan; test graphics libraries stay outside the owner package.

[Development measurements and receipts](evidence/found-002/README.md) identify the tested revisions, density sweep, disabled-pass costs, exact numerical comparison and adversarial interaction checks. The final Actions artifact separately records the packaged Windows source SHA, native graphical captures and software-renderer qualification.

## Founding architecture

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

## Founding state, 23 November 2026

The repository began with research and design documentation. FOUND-001 was a standalone Godot ZIP with owner-provided Windows screenshots. Those documents preserve the founding intent; current implementation and qualification are identified separately above.

## Tracking

- [Draft/HOLD PR #1](https://github.com/techrote/Xenovection/pull/1) — founding architecture and the coherent FOUND-002 implementation lineage; owner acceptance precedes merge.
- [Programme / custody #2](https://github.com/techrote/Xenovection/issues/2) and [original Godot source recovery #3](https://github.com/techrote/Xenovection/issues/3).
- [FOUND-002A kinetic filaments #4](https://github.com/techrote/Xenovection/issues/4), [FOUND-002B reflective/weather lab #5](https://github.com/techrote/Xenovection/issues/5), [FOUND-002C hybrid composition #6](https://github.com/techrote/Xenovection/issues/6).
- [Modulation bus #7](https://github.com/techrote/Xenovection/issues/7) and [optional data taps #8](https://github.com/techrote/Xenovection/issues/8).

**Custody:** the exact historical fixed ZIP has been recovered and preserved unmodified under [`experiments/found-001/`](experiments/found-001/). Its archive and specimen hashes match issue #3. The [custody receipt](experiments/found-001/CUSTODY.md) distinguishes this baseline from the successor implementation.

## FOUND-003 procedural laboratory (Draft/HOLD)

Six additional procedural presets, generated-region editing and a geometric strand-to-film domain are described in [the FOUND-003 controls and limitations](docs/13_FOUND_003_MATTER.md). The candidate package name is `Xenovection-FOUND-003-Windows-<revision>.zip`. Qualification and owner physical acceptance are pending; original FOUND-002 evidence above retains its exact scope.
