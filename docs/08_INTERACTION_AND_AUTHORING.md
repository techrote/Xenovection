# Direct spatial interaction and procedural authoring

**Goal:** videogame-level immediacy and affordances, not a conventional dashboard around a 3D graph.

## Navigation
- First-person free flight (WASD, mouse-look, Q/E elevation), orbit, pan, accelerated/fine movement, wheel depth/radius, look-at selection, bookmark/teleport, minimap or hierarchy jump.
- Camera presets by data source, projection/mapping mode and layer; visible camera-cut transitions invalidate temporal history.
- Mouse capture must be explicitly enterable/exitable; UI interaction never accidentally moves scene camera.
- Provide comfortable motion reduction/disable options for rapid panning, twisting and vertigo-inducing fields; visual effects must not hijack camera orientation without intentional input.

## Selection modes
- Point/node/edge picking; hover/tooltip, lasso, rectangle, brush, volume box/sphere, slice/plane, depth filtering and set operators.
- Each selected primitive is either an exact source-addressed object, an aggregate requiring refinement, or a purely visual decorative feature. Communicate which.
- Selection carries source ID, version, semantic scope, mapping transform, exact item IDs or documented aggregate coverage and a reversible history entry.
- Allow choosing whether selecting a decorative braid picks its primary underlying edge or selects only the artwork property. Never silently create source edits.
- Free-camera navigation must remain independent of gizmo/brush pointer ownership.

## Object manipulation
- Click to isolate, focus, mute, pin, extract group, reveal data controls, convert from hairline to reflective ribbon/surface and back.
- Move/rotate/scale artistic proxies with axis/plane constraints; place world-space plasma/volume emitter AABBs; edit projection, intensity and falloff spatially.
- Paint modulation influence envelopes or area masks while playback continues, with bounded brush radius and undo.
- Tools should have tactile, real-time preview, not blocking calculation while the mouse is held.

## Instrument model
- Compact dock/panels for oscillator patch cables/targets; precise numeric entry plus sliders; continuous LUT editor; favourites and presets.
- A high-quality dark canvas and minimal HUD by default; panels optional for art modes, but measured data scale/legend always inspectable.
- Global synth performance HUD: FPS/p95, render scale, cache cadence, active passes, approximate GPU bytes.
- View modes: exact structural, pure art synthesis, hybrid, selection-only, diff/compare and provenance/debug.

## Temporal and authorship tools
- Independent master timeline, per-layer clocks, pause, reverse, playback speed, phase locking and deterministic seeded replay.
- Layer stack resembles a compositor or synthesiser: reorder where legal, additive/multiply/screen/alpha blend, masks by depth/normal/source-ID, avoid invalid cyclic effects.
- Save named complete scenes: geometry sources, data mappings, controls, modulator graph, LUT bank, camera, quality envelope and measured-data provenance.
- Undo/redo for art operations must be separate from any model/experimental patch undo performed in source system.
- Reusable output targets: full-screen live background, transparent overlay, texture/material channel, remote visual sink and captured clip.
- Procedural field presets should be shareable independent of neural data.

## Art versus science gestures

A user twisting a selected knot is **visually morphing an artwork** unless an external numerical operation request is explicitly formulated and verified. Even when connected to RustySpork, operations follow:
(1) visualize exact source-addressable selection;
(2) optional propose/dry-run in source tool;
(3) source-tool validation/permission;
(4) source-tool commit result and provenance;
(5) viewer refresh with confirmed state.
No implied equivalence between scene deformation and changing model parameters.

## First interaction slice

Retain FOUND-001 navigation. Resize nodes/remove whiskers. Add a one-key no-FX toggle; add a local filament resonance brush with visual-only action. Verify camera captures and brush interactions do not interfere. Only then add rich authoring UI.
