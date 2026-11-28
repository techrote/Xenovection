# MAINLINE-CONVERGENCE-001: spatial ecology contract

The artificial-life solver remains planar. The spatial presentation consumes completed,
read-only snapshots and never changes a numerical position, velocity, field, random state,
or simulation clock. The qualified `ecology/world.gd` numerical implementation is unchanged.

## Shared clock and graph

The application owns the modulation bus and its 120 Hz scheduler. Ecology receives the
resolved target dictionary after every fourth graph tick and advances one 30 Hz world tick.
The world retains its 10 Hz field evolution and 5 Hz growth schedule. A paused ecology
ignores regular boundaries; a manual Step reaches exactly the next boundary and advances
one tick. Freezing visual clocks is independent of pausing ecology. Rendering cadence,
quality and camera pose do not select numerical parameter samples.

The original slow-growth/excitation convenience control now authors named routes in the
shared SYNTH patch when hosted. Standalone planar diagnostic mode retains its private bus
for compatibility. A hosted workspace never creates a second bus or silently adds hidden
oscillators. Old `xenovection.ecology.v1` configurations with `lfo=true` migrate into the
common patch through `convergence/ecology_patch.gd`.

## Immutable snapshot boundary

`ecology/snapshot.gd` publishes a bounded snapshot after completed ticks and explicit
interventions. Snapshots contain tick/seed, a domain transform, stable organism and lineage
namespaces, current and previous planar positions, velocity, energy, phase, excitation,
radius, allele/growth, bounded segments/tips/trails, resource/signal observations and full
bounded 32×32 fields. A separate presentation epoch distinguishes resets from ordinary
updates; a topology revision changes only when population or branch structure changes.

Every Dictionary and Array container is read-only. Packed numerical arrays are converted
to bounded frozen Arrays: merely returning a packed array from a frozen Dictionary would
still allow a consumer to mutate that snapshot through Godot's shared array semantics.
The focused qualification caught this defect before delivery. Numerical World state was
not modified by the original defective snapshot consumer, but immutable snapshot custody
was insufficient until this correction.

## Persistent spatial representation

`ecology/spatial_adapter.gd` owns one record per stable organism identity. Four material
instances, one sphere mesh and one cylinder mesh are shared across the representation.
One additional persistent, opaque unshaded material marks the numerical interaction
plane. Its muted cyan colour, normal depth testing and fixed opacity remain independent
of organism optical properties and material gain; it is an authoring guide. Resource
metrics distinguish the four family materials from this one guide material.
Each organism owns a persistent body instance and a bounded MultiMesh buffer for branches
or trails. Births allocate records, deaths release records, and new branches use reserved
capacity. Ordinary movement, interpolation, radius changes, optical adjustments and camera
movement do not reconstruct these meshes.

The four numerical families appear as branching filaments, moving trail structures,
curved membrane bodies and excitation pulses. Body displacement adds bounded visual depth
to the planar domain. Energy and excitation affect emission-like appearance; environmental
signal changes the three-band interference phase when optical enhancements are enabled.
The `eco.material` destination controls the same family brightness gain as the planar
view. These are artistic optical cues, not calibrated biological light transport.

The adapter uses the shared generated-matter optical bridge and therefore participates in
the application's illumination, palette, film-thickness, attenuation, Fresnel and thin-film
controls. Its analytical transmission does not read a screen/depth copy. Multi-hit
refraction and inter-organism collision geometry are not implemented.

## Input and lifecycle

Pointer interaction always intersects the explicit numerical domain plane. The inverse
mapping includes the adapter's transform and camera projection. Visual membrane curvature
or organism depth cannot change which planar coordinate a click addresses. The same
bounded intervention methods implement planar and spatial inspection, planting, resource
sources/sinks, excitation and inhibition.

The planar diagnostic Control remains alive when hidden. Returning to the shared spatial
instrument, changing camera or quality, and re-entering the planar workspace preserve the
World object, shared registry and numerical history. Configuration recall intentionally
resets numerical history to the authored seed and initial conditions; it does not restore
arbitrary runtime trajectories. Save operations use temporary-file replacement and retain
a backup of the preceding initial configuration.

Selection and family isolation are presentation state. Neither alters numerical evolution.
The frame around the spatial domain identifies the plane used for interactions. The first
generation representation is not a volumetric ecology solver.

## Qualification and measurements

`tests/test_ecology.gd` retains all 81 inherited assertions, including the 1,800-tick soak.
`tests/test_convergence_ecology.gd` adds immutable-snapshot, identity/resource, bounded-upload,
clock-boundary, numerical replay, inverse-pointer, pause/step, workspace-lifecycle and
configuration-recall contracts. It compares the same modulated simulation under different
presentation cadences and requires identical deterministic digests.

`tests/gui_ecology_probe.gd` preserves the 15 inherited real input checks while adapting
workspace detection to the persistent host. Three additional real Escape/re-entry checks
verify no scene replacement and no paused-history reset. Spatial input qualification uses
actual pointer events in the integrated application.

Runtime receipts separately expose solver p50/p95, snapshot generation p50/p95,
representation update p50/p95, persistent resource counts, topology builds/events,
instance-buffer uploads/bytes, body transform updates and material/instance uniform writes.
Hosted software Vulkan establishes execution and comparative cost. Physical TITAN RTX
throughput and owner visual acceptance remain separate evaluation gates.
