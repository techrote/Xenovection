# ECOSYSTEM-001 — Artificial visual life

Issue #14. Draft/HOLD, no merge. Accepted FOUND-002 main a2ef77814e857b1a9e08680e3d1ab43e1eba3de0 is tree-identical to qualified application 3034d0c80b8f089bbd379b964cee73d1c2f6519b. FOUND-003 #11 matter-contracts failed in run 46099284880; SYNTH-002 #12 synth-contracts failed in run 46099460641. Do not import either failed state. OPTICAL-003 is independent.

## Controls and experiments

Use Life > Open Ecosystem or Launch-Ecosystem.cmd. Choose a scene, set seed and Reset. Interactions enables sequential resource uptake, signal deposition, local steering/alignment, phase and excitation coupling, plus cooperative resource injection in Garden. Disable it and reset the same seed for an independent control with ambient resources not depleted; individual organisms still develop and move. Inspect shared resource or signal field; choose Plant, source, sink, excite or inhibit and click canvas. Use pause/step for fixed increments. Select an organism to see stable ID, parent, lineage, generation, age, energy, trait and branches; isolate its family visually without changing simulation. Save/recall writes authored base parameters, seed, preset, plant placements, resources and LFO selection (not transient histories). Export produces a bounded 240-sample observation trace and measured engine/frame counters. Returning to the source instrument reloads the original scene; no source changes.

| Preset | Population at reset | Mechanism and intervention |
| --- | ---: | --- |
| Mycelial Atlas | 12 | Seeded, nutrient/trace-directed filament tips add real persistent edges; branch/decay; plant or adjust growth |
| Vortex Colony | 84 | Moving organisms with short trails; shared signal curl, resource gradient, alignment, attraction/avoidance; compare coupling off |
| Membrane Reef | 26 | Resource-dependent growing/contracting boundaries and repelling centers, translucent ring artwork; place sinks |
| Symbiotic Garden | 42 | Filaments + mobile organisms; mobile population adds resource near neighbors while competitors consume it |
| Excitable Sea | 144 | Fixed excitable lattice, local coupling via excited neighbors and diffusing signal, refractory period; excite/inhibit and vary diffusion |
| Evolutionary Terrarium | 36 | Mixed morphology; energy-dependent reproduction, bounded trait mutation, lineage IDs, age/starvation deaths; vary resources/mutation |

## Architecture / budgets

World is RefCounted pure state independent of the source/renderer. Normalized planar domain, reflecting mobile bounds, 32×32 grids, resource/signal diffusion stencil with clamped edges and coefficient <=0.24; explicit open-system source, sink, relaxation, uptake, and decay. No conservation claim. Fixed 30 Hz simulation, field updates at 10 Hz, branch/radius updates at 5 Hz, rendering independent of sim cadence. Four-step catch-up ceiling, excess ticks counted and discarded; deterministic exact step mode is separate. Resource supply and field deposition saturate to [0,1]. Spatial buckets sample up to 32 candidates per organism per tick; fixed enumeration is deterministic but dense cells can bias sampling. Observation arrays and state are bounded. 192 organisms, 80 edges per filament, 12 active tips, 28 trail points per mobile organism, 32 added plants, 16 sources/sinks, 240 observation samples. Max generated filament edges 15,360; all families cannot hit all geometry limits simultaneously. Canvas redraw maps persistent simulation geometry to screen; detail stride applies only to trails and membrane outlines. Not a native GPU persistent-geometry or 3D simulation implementation. No new optical shaders.

Traits are scalar inherited values affecting growth and uptake; no biological/genetic realism. Lineages remain stable within one run; reset restarts IDs deterministically. Reproduction requires resources, energy and age, capped offspring and mutation; no automatic replacement on extinction. No reverse time or snapshot restoration. Resource field is not a conservation model. Branching is local stochastic field-following, not a validated DLA or space-colonization implementation. Membrane pores are procedural ring marks, not perforated surfaces, no refraction. Excitable sea is a discrete abstract phase/excitation system, not a numerical fluid or biological model. Cooperative exchange is resource injection from neighbors, not a closed metabolism. No claimed phase transition until measured experiment evidence exists.

## Modulation and convergence

Typed scalar targets via accepted ModulationBus: eco.growth, eco.interaction, eco.diffusion, eco.resource, eco.alignment, eco.excitation, eco.mutation, eco.material. Workspace owns a separate bus and uses fixed-step effective values; optional slow LFO drives growth/excitation. Full SYNTH-002 patch UI integration and FOUND-003 region/matter adapters deferred until both exact-head qualification gates pass. Preserve source identity and accepted original archive. OPTICAL-003 owns optical materials; current ecology colors and transparency are artistic canvas appearance only.

## Qualification protocol

Run Godot 4.7.2 headless `--path app --script ../tests/test_ecology.gd`. Contract script prints six paired 180-step experiments, topology and boundedness checks, exact seeded state replay, local perturbation/diffusion comparison, JSON round trip, modulation, inherited traits, population cap, extinction/reset and a 1,800-tick evolution soak. Wall time counters excluded from digests. Same-engine replay is tested, not cross-platform bit equality.

Dedicated Windows workflow checks out exact PR head, invokes inherited regression and package harness, extracts the owner ZIP and renders six ecology scenes at 360 deterministic steps and a Vortex interaction-disabled control. Capture/receipt checks validate head, schema, counts, image dimensions, driver and software device. Fixed-step batch profiles are not live performance measures. Use Profile-Ecosystem.cmd for 600 live Vortex Colony frames; repeat ordinary/dense scenes on TITAN RTX separately. 60/30 FPS are provisional, not achieved until measured. Graphical input probe exercises actual Life entry, pause/step, canvas placement/inspection, resource source, excitation, quality independence and config save/recall. Execution and visual acceptance, multi-hour soak, physical GPU evidence, adaptive geometry upload and independent optical integration remain pending. CI evidence must be inspected at exact head before owner delivery.

First exact-head run 46125690727 failed before Godot launch due to malformed PowerShell generated by source insertion; harness corrected in subsequent candidate. No local Godot executable or GPU in authoring environment. CI configuration does not equal PASS. Do not merge.
