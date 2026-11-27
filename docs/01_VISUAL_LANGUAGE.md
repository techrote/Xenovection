# Visual language — expressive data sculpture

**Purpose:** preserve all identified artistic directions as simultaneous options, not select a single visual aesthetic.

## Core visual populations

| Medium | Source geometry / domain | Modes and effects | Scientific convention |
| --- | --- | --- | --- |
| **Primary filaments** | Explicit graph/connection edges, authored curves or sampled lines | hairline curves, travel phase, travelling transverse waves, twist, highlighting | Must resolve to exact edge IDs where backed by data |
| **Secondary filigree** | Procedural microfibres attached to primary strands or surfaces | hairlike parallel paths, braids, knots, wavering tendrils, growth | Decorative; not false graph edges |
| **Atmospheric traces** | Screen-space, history or flow field | afterimages, ghosts, motion persistence, sparklets | Purely artistic |
| **Ribbons / bundles** | Bundled curves, selected subgraphs, spline surfaces | helices, translucent sheaths, adjustable width, twist | Group membership disclosed |
| **Membranes / sieves** | Authored or data-derived sheet surfaces | gaps, aperture arrays, permeable veils, folds, tear-looking motion | Surface geometry explicitly representational |
| **Reflective anatomical solids** | Selected circuit / feature / geometry proxy | polished metal, refractive crystal, layered normals, thin-film-like chroma | No claim of physical neural morphology |
| **Volumetric weather** | 3D scalar fields, source measurements or art density functions | fog, plasma, stratified emission, voids, cellular sheets | Legend identifies what is measured |
| **Environment / sky** | Analytical waves, LUT, HDR panorama | live SkySynth illumination, counterflow, colour-band drift | Artistic lighting is separate from measured signals |

### The compositional objective

A view may contain barely visible hairline connections in the foreground, a slowly braiding mid-depth bundle, a perforated reflective lattice around selected elements, far-field translucent plasma clouds, and a separately animated HDR sky. Layers should have distinct controls and budgets. Dense regions must be readable by deliberate isolation, clipping or focus—not by suppressing richness globally.

## Kinetic filament doctrine

The owner supplied a close-up of FOUND-001 at dense zoom: overlapping cyan/coral threads already form convincing woven translucent tissue. Do not replace them with conventional chunky geometry.

Movement families, all independent and mixable:
- **Phase travel:** luminous bands pass along fixed geometry; reversed direction, variable phase speed, multiple frequencies.
- **Transverse travel:** physically displace strands with sine/triangle/periodic or bounded wander wave along arc length; envelope pinned near connection endpoints.
- **Counterflow:** different strata travel or shimmer in opposite directions.
- **Braid/torsion:** parallel fibres orbit a common axis, phase-offset by strand ID; maintain endpoints and tractable selection.
- **Collective resonance:** standing waves or wavefronts across a bundle/region, locally phased, with controllable decay.
- **Fine-grained agitation:** bounded local field warp that does not erase fine lines.
- **Interference via density:** apparent texture and activity from changing fine-line overlaps, without huge opaque particles.

Not every luminous moving event corresponds to actual computational propagation. Keep signed and magnitude encodings optional, with neutral artistic movement possible.

### Line rendering specification

- Support perceptually hairline strokes and subpixel coverage, not just camera-facing tubes.
- GPU-friendly rendering: persistent connection buffers + stable IDs, analytic procedural displacement, instancing/indirect batches where useful, avoid full topology rebuild every frame.
- Thickness and brightness independently controllable by layer and camera distance.
- Prefer high-quality line AA and stable coverage; reject crawling, sparkle aliasing and temporal ghost trails that obscure meaning.
- When thickening for reflections, use a separate **ribbon/solid interpretation** of the same edge, rather than forcing all lines into cylinders.
- Keep an exact-data no-FX rendering path, and provide one-key comparison against full art.

## Procedural surface dynamics

The reflective knot in XenoField preset **6 ECONOMY INTERACTIVE** and the **WEATHER ENGINE** normal/max-displacement comparisons motivate a surface path with:
- animated environment-mapped lighting; highly detailed changing normal fields;
- surface wave displacement, twist, folding, shearing, crumpling, local oscillation and tear-*like* breakup;
- independent normal, base colour, roughness, emission, opacity and reflection modulation;
- optional transmissive/refractive sheaths and translucent layered panes;
- endpoint/feature retention constraints when a surface must remain attached to exact graph elements.

The screenshots indicate visually coherent results in stills, not a proven physically sound mesh-tearing algorithm. Strong vertex displacement can create self-intersections or clipping, sometimes attractive; never claim topology was actually remeshed without verification. Distinguish changed geometry from changed normals/reflections.

## Plasma/texture aesthetic

The animated wave source itself may be simple (horizontal, vertical, diagonal, radial waves), but fields become elaborate through mixing, warping, non-linear contrast, cyclic LUT and environment-mapped optical response. Preserve:
- phase and direction reversal, independent time signs and offsets;
- frequency X/Y, spatial panning and rotation, diagonal component, radial curvature, domain warp, field contrast;
- smooth cyclic LUTs with palette editing, shifts and controlled chromatic tension;
- emitter and skybox modes, reflection source, displacement source, mask, density and volumetric emission;
- animated procedural illumination at independent cadence from the scene and simulation.

The screenshot with a brightly lit reflective braided knot demonstrates a particularly powerful interaction: **the object can remain nearly stationary while its reflected world flows across it**.

## Visual scale transitions

- **Macro:** architectural blocks / populations / galaxy-like dense clouds.
- **Meso:** bundles, pathways, membranes, knots and spectral clusters.
- **Micro:** fine filigree, surface normal detail, individual connection segments.
- **Surgical / exact:** precise data indices and measurements (only where a data source supports them).

Use LOD and view-dependent effect strength rather than expecting all objects at all scales to be individually drawn. A visual attractor/semantic valley is an authored or derived mapping, not intrinsic Euclidean space.

## Contrast and taste

The references range from austere cyan-orange networks on black to saturated cyan/magenta/cream reflective surfaces and extremely hot yellow/orange/high-contrast environmental effects. Treat these as distinct presets. Preserve dark, uncluttered modes that reveal fine strands; offer rich, even violently saturated modes as opt-in aesthetics.

The user asked: **make the spheres much smaller and remove the stub/whisker geometry from all of them.** This is a direct accepted change request for the next FOUND-001 revision.
