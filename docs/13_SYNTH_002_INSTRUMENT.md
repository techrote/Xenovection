# SYNTH-002 — modular visual instrument

Draft/HOLD. Accepted baseline a2ef77814e857b1a9e08680e3d1ab43e1eba3de0.
Source topology and renderer remain owned by FOUND. No service or model dependency.

## Play and patch

F7 opens Synth. Recall example loads its original FOUND-002 scene and authored graph.
Perform provides the XY pad, editable axis assignments, one slider per manual source,
envelope triggers and transport. Move the XY pad with left drag; axes range -1..1.
Macros are manual sources routed to any number of destinations. Patch has a source
form and searchable destination form. Blank creates a graph for the current scene.
New component/route creates a proposed ID; Apply validates the whole graph before
install. Remove dependent routes/inputs before deleting a referenced source.
Signed depth is polarity and amplitude, offset shifts the range; route gain is
0..1, bypass disables the route, solo isolates a route within the active patch.
Add applies base + signal × depth + offset (times gain), multiply applies base ×
(1 + modulation); the accepted bus clamps to destination bounds after each route.
Patch route order is serialized insertion order. Active patch replaces stock LFO
routes; Stop or a baseline preset restores the original routing. Scientific mode
suspends patch effects. Existing selection, orbit, fly and provenance remain independent.

| Module | Inputs and parameters |
|---|---|
| Manual | value, normally -1..1 in performance |
| Sine/triangle/saw/pulse | rate cycles/sec (cycles/beat on beat clock), phase cycles, pulse duty via shape |
| Noise | deterministic seeded step at cycle boundary |
| Walk | bounded seeded increments, shape = step size |
| Hold | A sampled at cycle change |
| Envelope | trigger from Perform, rate = duration, shape = attack fraction |
| Sequencer | 1–32 comma-separated steps, rate steps/sec or steps/beat |
| Add/multiply/mix | A and B; shape is mix weight |
| Remap | A × shape + value |
| Quantize | A snapped to absolute shape increment |
| Slew | A, shape = time constant |
| Delay | A from previous global fixed tick, value = initial state |
| Vector2/vector3/colour | A/B/(C) scalar inputs; colour is RGB delta with alpha 0 |

Transport uses 120 Hz fixed steps, with a maximum 30 steps per render frame and
250 ms admitted frame delta; larger stalls report dropped time. Five independent
visual clock rates/pause flags are inherited from the accepted bus; beat follows
filament clock rate/pause and BPM. Analytic modules support signed rates; stateful
modules evolve forward using absolute clock speed and cannot reverse their history.
Delay is a global fixed-tick unit, not a per-clock history buffer. Graph edits
restart graph phase and history. Trigger envelopes manually. No arbitrary scripts
or external adapters. Per-clock phase is not a sample-accurate audio clock.

## Examples

Vortex Conductor (Vortex Atlas), Weather Instrument (Weather Membrane),
Filament Sequencer (Counterflow Loom), Spectral Layers (Spectral Knot),
Autonomous Organism (Convergence), XY Morphosis (Weather Membrane).
All have macro_a/macro_b, XY assignments and a triggerable strike envelope.
They are authored component/routing populations, editable after recall.

## Persistence and contract

Patch schema xenovection.patch.v1: preset index (existing indices append-only),
bpm, clocks (rates/pause, not runtime time), sources, routes, xy. 48 sources, 96
routes, 32 steps per sequencer, 256 KiB file maximum, 32 undo snapshots. IDs
are stable within an authored patch. Save slot user://xenovection-patch.json;
export/import use the file chooser. Atomic rename and prior .bak allow recovery.
Malformed, out-of-range, cyclic, missing or incompatible inputs/targets refused.
Patch recall resets the preset and graph to an initial state; F5/F6 embeds the
authored patch in the backward-compatible scene v1, preserves scene bases,
camera and selection, and resets graph runtime (no snapshot of delay history).
Morph loads a compatible saved slot with a 0.8s signal transition only for same
scene and identical route definitions with matching signal types; other recalls
make a declared cut. Manual gestures and triggers are not undo-history events.

FOUND-003 target registration v1: existing register_target(stable_id, base, min,
max, optional metadata). Metadata policy continuous (default), base_only or
discrete. Optional field_descriptor dictionary is renderer-owned descriptive
metadata (e.g. space/region/field ID); no implied spatial evaluation by graph.
Graph consumes continuous scalar/vector2/vector3/colour targets; scalar broadcasts
as in accepted bus, non-scalar must match type. Register only inexpensive writable
uniforms as continuous; mark topology choices base_only. Existing bus.routes
and targets are the only destination interface; no competing renderer.
Dynamic destination removal safely gates affected routes; reauthor/reload after
registration returns. Local spatial masks, field handles, new geometry, material
phenomena are FOUND-003 scope. Current route gain is global, not a spatial mask.

## Evidence and limitations

tests/test_synth.gd exercises fixed step, typed routes, delay feedback, invalid data,
clock behavior, persistence, UI authoring/undo/redo, all examples, no reconstruction,
and 60 simulated seconds of dense graph. tests/gui_synth_probe.gd sends actual
pointer/key events to commit authoring controls and XY drag. The Windows harness
runs accepted baseline tests and extracted package profiles/captures for all six
patches, including a 600-frame XY profile. Profile reports graph p50/p95 in
microseconds (bounded last 1024 sampled prepare calls) separately from wall frame
and renderer/resource evidence. Simulated and wall durations must be distinguished.
Hosted software Vulkan is not physical TITAN RTX performance.
No claim of completed qualification until actual CI evidence is available.
Deferred: independently writable environment light nodes, local spatial masks,
field-specific target binding after companion merge, curve/keyframe editing,
sample-accurate event streams, arbitrary cross-topology morphs, and physical GPU
acceptance. Current sequencer is stepped, envelopes are attack/release, no ADSR.
