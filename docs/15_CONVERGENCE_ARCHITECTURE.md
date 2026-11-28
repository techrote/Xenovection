# MAINLINE-CONVERGENCE-001 — common instrument contracts

This candidate combines the four protected feature implementations under one application. The original source renderer, procedural matter laboratory, optical renderer, modular graph and ecology solver retain separate responsibilities. `app/main.gd` owns their lifecycle and connects the bounded interfaces below.

The integration remains Draft/HOLD. Numerical and graphical execution receipts do not constitute owner acceptance of TITAN RTX performance or appearance. Exact application, tree, workflow and evaluator identities belong in the mission's release receipt.

## One modulation registry and one sampling timeline

`ModulationBus` is the sole application-level target/source/route registry. Its identity survives scene and workspace transitions. `reset_registry()` clears authored scene registrations without replacing the object held by the persistent ecology workspace.

The registry holds at most 256 targets, 64 bus sources and 128 bus routes. The authored SYNTH graph keeps its qualified, narrower budget of 48 sources and 96 routes. An installed graph disables the stock artistic routes; it does not accidentally stack two route populations. Stopping it restores the stock population.

`convergence/instrument_clock.gd` advances at 120 Hz. Each completed substep advances the independent visual clocks, publishes the SYNTH source values, then resolves the shared bus exactly once. Every fourth completed substep passes a detached resolved-value map to ecology. The world advances at 30 Hz; its inherited field and growth schedules remain 10 Hz and 5 Hz.

Changing render frame rate does not select a different modulation sample for a given ecology tick. The focused contract suite compares a modulated world at 60 and 240 render updates per second and checks identical graph state and numerical digests after the same completed ticks. Catch-up remains bounded to 0.25 seconds per update; dropped time is explicitly reported. This is a responsiveness bound, not a claim that an overloaded renderer can always keep up with wall time.

The graph's clocks remain independently reversible or pausable. Stateful delay histories are not reversed. Pausing visual transport freezes its signals while the ecology lifecycle remains independently controllable through Life's Pause/Step controls. A manual ecology step reaches exactly the next four-substep boundary. A zero-delta authoring update resolves current values without advancing graph, particle or organism history. Scientific mode excludes ecology execution and decorative presentation.

An ecology observation cannot participate in an instantaneous graph/solver feedback cycle. Snapshots are produced only after completed world ticks; any future graph observation inputs must use a later sampling boundary. Current energy, excitation and growth observations drive the spatial representation through read-only snapshots.

## Typed targets, availability and diagnostics

The common graph exposes scientific presentation, `matter.region0..2.*`, `optical.*` and `eco.*` targets. It retains scalar, vector and colour typing and explicit one-tick graph feedback. The Synth route editor supports domain filtering and text search; an empty search explicitly lists all active continuous destinations.

Generated-region mode, seed, count, primary/secondary field, integration step and pathline choice are base-only controls. They cannot be routed into continuous modulation. Field strength, field blend/origin, transforms, condensation and material parameters remain live controls. Changing them does not request topology reconstruction.

Inactive domains retain their stable registrations, while the authoring catalogue excludes them from new routes by default. Existing routes into inactive domains remain authored and visibly retain their original destination. The bus reports unavailable destinations and leaves their bases unchanged. Reactivation resumes normal application. Missing targets, inactive targets and clamped values have distinct diagnostics.

The familiar ecology slow-growth/excitation toggle now edits an ordinary common patch: one `ecology_lfo` sine source at 0.08 Hz and explicit growth/excitation routes. There is no private hosted ecology bus. Migration is idempotent, respects graph capacity and refuses identity collisions. Disabling the toggle removes its routes and removes the source only when no other authored component uses it.

## Stable composition identities and migration

The seven accepted baseline compositions keep their original order and legacy receipt IDs. All six FOUND and all six OPTICAL studies survive. Picker numbers are presentation order; persistence uses `preset_id`.

| Population | Stable IDs | Current picker positions |
| --- | --- | --- |
| Accepted source presentations | `source.hybrid`, `source.filaments`, `source.optical`, `source.membrane`, `source.scientific`, `source.stress`, `source.flow` | 01–07 |
| Procedural matter | `matter.nursery`, `matter.garden`, `matter.living`, `matter.films`, `matter.condensation`, `matter.ecosystem` | 08–13 |
| Optical studies | `optical.dichroic`, `optical.weather`, `optical.lens`, `optical.garden`, `optical.microfibres`, `optical.ecosystem` | 14–19 |
| Integrated compositions | `composition.spectral_vortex`, `composition.living_membrane`, `composition.excitable_garden`, `composition.condensation_instrument`, `composition.light_terrarium`, `composition.matter_orchestra` | 20–25 |

Legacy scene indices 0–6 map to the accepted source presentations. Both protected feature branches used legacy indices 7–12; the loader resolves those through their original schema evidence. Qualified FOUND saves contain the matter snapshot, including when inactive. Qualified OPTICAL saves lack that snapshot and contain the `optical.optical_mix` parameter. An ambiguous higher-numbered legacy scene is refused rather than silently loading the other branch's study.

Qualified SYNTH patches used the seven accepted baseline indices. They migrate to the corresponding stable IDs. Newly authored patches carry a stable `preset_id`; an unidentified higher-numbered patch is refused. Stable IDs continue to resolve when the catalogue is reordered, and duplicate identities fail validation.

## Versioned authored composition persistence

`xenovection.scene.v2` retains the complete inherited scene fields and adds stable composition identity, explicit ecology state and workspace state. Source identity, source revision and projection revision are still checked. Known built-in source descriptions allow a saved composition to reconstruct its exact accepted source before binding it; imported sources require their exact external snapshot.

The composition stores:

- Exact scientific-source identity, selection, source presentation and camera.
- Every registered authored parameter, renderer flags and independent clock settings.
- Three stable procedural-region slots and their baked topology configuration.
- Optical material, illumination, optional layer and refraction settings.
- The editable SYNTH graph and stable source/route IDs.
- Ecology's seed and authored initial configuration, including planted organisms and resource interventions.
- Independent ecology enable/pause state and spatial/planar presentation settings.
- The active authoring workspace.

Missing fields in older scenes receive explicit registration/default state. They do not inherit the material, ecology or generated-region state of an unrelated live composition. Invalid vectors, unknown source identities, invalid ecology configurations, unknown graph destinations and out-of-bounds settings are rejected before application state changes.

Saves use a temporary file and retain a readable `.bak` predecessor. Patch files retain their qualified atomic save/recovery path. The complete composition envelope is bounded to 4 MiB; the patch bound remains 256 KiB.

Persistence records authored configuration. Recall restarts graph delay buffers, particle trajectories and organism histories. It is not arbitrary simulation rewind or an exact mid-run world checkpoint. The separate planar ecology configuration file remains available for controlled numerical experiments.

## Authoring and history scopes

The application rail gives access to source presentation, optical controls, Matter, Life and Synth. F7 opens the Synth editor/performance rail. F5/F6 in the source/spatial instrument save and recall the full composition. The planar diagnostic workspace retains its own configuration save/recall controls, labelled accordingly.

Matter owns bounded region-edit history; the source-selection subsystem owns exact source-selection history; Synth owns patch-edit history. The active authoring tab determines the relevant undo scope. A patch undo restores graph authoring and reinitializes graph phase/history; it does not undo numerical ecology evolution. Ecology reset/seed and saved initial configurations are explicit operations.

In the Life tab, “Edit ecology in viewport” gives left-click ownership to the selected ecology tool and maps the pointer to the fixed numerical domain plane. Matter selection and source selection do not also consume that click. Camera navigation retains its own mouse buttons. Planar/spatial workspace changes release stale pointer capture and retain the same world state.

## Six integrated, editable starting compositions

| Composition | Common-graph and domain coupling |
| --- | --- |
| Spectral Vortex Nursery | Persistent vortex ribbons and particles; live field strength/origin/blend; optical illumination orbit, spectral phase and transmission. |
| Living Optical Membrane | Generated membrane weather and thickness with a seeded membrane population; growth, resource and alignment destinations share the same graph. |
| Excitable Filament Garden | Refractory excitation population, slender generated strips, sequenced excitation, envelope light and bounded diffusion control. |
| Condensation Instrument | XY-controlled geometric strand-to-film condensation and shell wrapping, envelope illumination, optical thickness and transmission. |
| Evolutionary Light Terrarium | Seeded branching, inheritance and resource competition with shared growth/mutation controls and an optical shell. |
| Hybrid Matter Orchestra | Three separately editable generated regions and a seeded cooperative population, routed through one bounded patch and optical environment. |

These entries are ordinary scene dictionaries and ordinary patches, using the same controls and validation as user-authored state. They do not contain scripted showcase playback or a separate simulation implementation. Their graphs can be edited, saved, stopped or replaced through Synth.

## Rendering and numerical boundaries

The ecology solver remains planar. Its three-dimensional presentation consumes bounded, detached snapshots keyed by stable organism identity. Birth/death and topology revisions are distinct from ordinary movement. Camera pose, quality and presentation interpolation cannot write the numerical world. The retained planar view provides an independent diagnostic representation of that same world.

Procedural matter retains its own topology and the recovered perspective-correct ribbon extrusion. Optical controls reach persistent generated-matter materials through the common material bridge. Legacy mix zero retains the prior material path. The generated optical bridge shares the artistic thin-film/attenuation/illumination model; it does not add calibrated spectral transport or make every generated surface a screen-copy refractor.

The original OPTICAL source proxy retains its explicit opt-in screen/depth-copy pass. A generated object does not enable that expensive pass globally. Shared generated geometry, stable region resources and identity-owned ecology buffers persist during ordinary modulation and camera movement.

## Executable evidence

The standalone evaluator starts through a small bootstrap. Normal startup loads the unchanged main scene. An explicit `--qualification-script=<filename.gd>` user argument selects only a fixed allowlist of exact unchanged qualification scripts, requires their packaged `SOURCE.json` manifest and runs the selected script on the application's existing `SceneTree`. The bootstrap removes itself before deferred test initialization; tests can load the main scene normally. This explicit dispatch is necessary because the first Windows release executable ignored the editor-style `--script` option and entered the normal application. Qualification checks the `XENOVECTION_QUALIFICATION_SCRIPT_STARTED` marker as well as exit status and engine diagnostics, so an ordinary application launch cannot satisfy an extracted-script gate. A focused execution using the official Linux release template demonstrated dispatch and all 71 core assertions; this release-dispatch proof is separate from the required Windows Vulkan Forward+ graphical campaign.

The inherited core and feature suites remain required. `tests/test_compositions.gd` covers identity, migration, atomic saves, graph bounds, target availability and deterministic fixed-boundary ecology sampling. `tests/test_convergence.gd` exercises all six compositions in the actual application, including persistent resource reuse, mixed-domain recall, refusal atomicity, legacy feature migration and scientific isolation.

The retained source/Matter graphical probe preserves its incompatible-source refusal with an explicit legacy v1 scene fixture. It also restores the actual F5-created v2 file and adds real F6 verification that a known builtin source is reconstructed with exact source, projection and selection identities. The existing changed-projection refusal and same-source label checks remain. This migration distinguishes the preserved legacy contract from the new, verified builtin-source recall capability; it does not remove the original adverse case.

The first extracted spatial-ecology graphical run exposed a probe assumption about popup initial focus: sending HOME followed by a fixed count of DOWN events did not select the requested items. The spatial and integrated authoring probes now follow the actual focused item with bounded UP/DOWN input and use the same default-window keyboard routing already demonstrated by the Windows material-authoring probe. Real pointer opening, key-driven selection and final selected-index checks remain; the spatial receipt also records popup visibility, window identity and the observed focus sequence. The correction changes test interaction mechanics, not authored options or numerical behavior.

The integrated probe also follows the passed material/spatial pointer sequence: one mouse motion, then press and release. It does not inject another motion into a newly opened popup before releasing the button. Popup and form traces preserve control rectangles, selection, visibility, focused items and validation messages; the first menu-opening failure receives an immediate capture before later actions. A focused headless input reproduction passed all 87 authoring/persistence assertions before the three final graphical-capture assertions. That diagnostic reproduction does not replace the complete Windows graphical probe.

`tests/test_convergence_ecology.gd` and `tests/test_matter_optics.gd` cover the snapshot/representation and material boundaries independently. Graphical input probes remain required for source/Matter, Synth, ecology and integrated authoring. A successful headless receipt does not replace Windows Vulkan Forward+ execution, extracted-package qualification or visual inspection.
