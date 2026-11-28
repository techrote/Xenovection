# Converged optical materials

The procedural and ecological renderers now consume the qualified optical environment through a uniform-only material interface. They retain their own geometry, simulation, identity and resource lifetime. The scientific source renderer retains its original optical proxies, optional second shared-mesh film, and opt-in screen/depth-copy refraction variant.

## Assigning the shared environment

In the **Matter** inspector, select a region and raise **Shared optical response**. In **Optics**, enable **Optical layer** and raise **Optical matter mix**. The effective assignment is the product of these two bounded mixes. Optical mix zero preserves the independently qualified procedural appearance. Scientific mode hides generated geometry and refuses enhanced material evaluation.

Spatial ecology uses its four persistent family materials with the same optical context. Its render-only optical assignment defaults to one. The shared optical mix remains the common enable/mix control. The shared `eco.material` destination controls a bounded final radiance gain, including at full optical mix. Organism energy and excitation affect visual radiance; sampled environmental signal contributes a bounded phase offset to the same three-band film response. These observations never write into the ecology solver.

## Material compatibility

| Control or capability | Generated regions and particles | Spatial ecology |
| --- | --- | --- |
| Shared analytical environment, palette and independent sky/palette clocks | Supported | Supported |
| Bounded authored thickness, angle-dependent path, RGB attenuation, dielectric Fresnel and three-band interference | Supported | Supported |
| Spectral bandwidth/dispersion cues, rough reflection, material tint and reflection strength | Supported | Supported |
| Two independent illumination lobes, direction, intensity and colour balance | Supported | Supported |
| Correlated optical field and bounded local scattering cue | Supported | Supported |
| Optical diagnostics for path, transmission and Fresnel | Supported | Supported |
| Screen/depth-copy refraction | Not requested; analytical environment transmission only | Not requested; analytical environment transmission only |
| Second shared-mesh optical film | Author multiple existing matter region slots | Not implemented |
| Optical proxy displacement and normal-detail controls | Existing matter deformation and microstructure retain ownership | Snapshot transforms and persistent organism geometry retain ownership |

The common `refraction_strength` changes the analytical transmitted environment cue for generated materials. It does **not** enable a screen copy for them. The original OPTICAL proxy remains the only owner of its screen/depth samplers. A generated film cannot therefore refract another transparent film or claim multi-hit transport.

Matter's local thickness, absorption and roughness remain controls of its inherited appearance; the shared optical assignment blends toward the common optical material controls. This distinction permits exact zero-mix compatibility instead of silently changing the original scenes.

## Geometry and resource contracts

The qualified perspective-correct mode-0 ribbon extrusion and subpixel coverage are unchanged. Film normals used by the optical adapter come from the actual continuously deformed surface. Ribbons use an explicitly view-facing shading normal, since their source vertices coincide before pixel extrusion. Optical opacity multiplies existing coverage: it cannot fill a membrane aperture or widen a strand.

Each generated region retains one persistent strip mesh/material and one particle MultiMesh. A third, preallocated material supplies the optional optical particle appearance. Disabling that assignment removes the override and restores the original opaque unshaded particle material. No material or mesh is constructed by an ordinary optical parameter update.

Only `mode`, `seed`, `count`, `field`, `secondary`, `integration` and `pathline` are base-only topology controls. The shared route registry rejects continuous routes to these destinations. Strength, blend, field origin, deformation, condensation, transforms and material controls remain continuously writable. Explicit reintegration is still available for authoring a new baked field curve.

The spatial adapter shares two geometric meshes and four family materials. Organism IDs own their representation records; births and deaths allocate or release those records. Existing branch/trail capacity receives transform and custom-data uploads after completed snapshots. Local-axis cylinder scaling preserves both endpoints and the intended radius for every orientation.

## Evidence and practical limits

`tests/test_matter_optics.gd` exercises shared assignment, uniforms, separate clocks, no topology rebuilds, stable resources, legacy restoration, topology-route rejection and continuously writable fields. The inherited 30 matter assertions and 62 optical structural assertions remain executable. The inherited optical integration block resolves all six stable optical IDs and retains every original behavioural assertion.

`tests/gui_material_probe.gd` authors the assignment through real pointer, wheel and keyboard input. It records optical-enabled, mix-zero and authoring captures from the same paused scene, verifies unchanged mesh/material identities, checks source custody and measures a nonzero image difference. Headless structural execution does not qualify visual quality; the Windows graphical workflow is the renderer and extracted-package gate.

Per-region metrics separate geometry builds, estimated uploaded mesh bytes, estimated particle-buffer bytes, actual material-uniform writes, allocated resources and visible resources. Byte volumes describe CPU-side submitted arrays, not measured GPU bus traffic. These RGB optical approximations are expressive rendering controls, not calibrated spectral transport or a biological model.
