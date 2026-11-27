# FOUND-002 development evidence

These are measured receipts, with their scope kept separate from the exact Windows
evaluator qualification. The latter travels with the corresponding
[Windows Actions artifact](https://github.com/techrote/Xenovection/actions/workflows/evaluator.yml):
`qualification.json`, engine logs, actual screenshots, frame profiles, package
receipt and source/build identity. Headless execution is not visual qualification.

## Serial density and pass-cost measurements

`linux-vulkan-density/recipe.json` identifies source
`ce694fce2d98530e09a069007d81d34c80f950a1`, every launch argument, run order and
resolution verification. All ten cases used actual animated frame time, 45 warmup
frames and 150 measured frames, serially, with no fixed-FPS override. The device was
Linux Mesa **llvmpipe software Vulkan**, four rendering threads, Godot 4.7.2
Forward+, at **1280 × 800 actual rendered pixels**, with the HUD hidden. The
1440 × 900 viewport field in those early receipts describes logical canvas units.
The later application reports actual image-readback dimensions separately.

| Case | Primary edges | Total strands | Wall p50 / p95, ms | Application update p50, ms | 3D draws |
| --- | ---: | ---: | ---: | ---: | ---: |
| Primary only, density 24 | 2,880 | 2,880 | 76.042 / 85.435 | 0.398 | 2 |
| Primary only, density 48 | 11,520 | 11,520 | 209.843 / 244.219 | 0.427 | 2 |
| Primary only, density 96 | 46,080 | 46,080 | 767.463 / 879.890 | 0.410 | 2 |
| Primary only, density 128 | 81,920 | 81,920 | 1349.647 / 1434.523 | 0.441 | 2 |
| Scientific | 11,520 | 11,520 | 101.519 / 122.281 | 0.278 | 2 |
| Hybrid | 11,520 | 23,040 | 379.347 / 416.524 | 0.460 | 5 |
| Hybrid, optical disabled | 11,520 | 23,040 | 357.384 / 402.041 | 0.416 | 3 |
| Hybrid, secondary fibres disabled | 11,520 | 11,520 | 215.788 / 245.688 | 0.443 | 4 |
| Hybrid, geometric waves disabled | 11,520 | 23,040 | 366.725 / 412.353 | 0.337 | 5 |
| All scene layers disabled | 11,520 retained | 0 | 18.779 / 23.345 | 0.364 | 0 |

This is useful evidence of work scaling, bounded CPU update cost and effective
pass gating. It is **not NVIDIA TITAN RTX performance**. Software-device timestamp
queries in these files are likewise not physical-GPU measurements. Engine memory
counters are allocation proxies, not process RSS or total driver VRAM. Later
source revisions add the spatial-flow specimen, refined membrane and qualification
corrections; these earlier numbers are not silently relabelled as their benchmark.

## Focused receipts

| Receipt | What it establishes | Scope |
| --- | --- | --- |
| `numeric-exactness.json` | All 48 inputs and 11,520 coefficients survive the Godot import bit-for-bit | Independent Python binary64 comparison with the recovered specimen |
| `gui-input.json` | 28 real graphical input/selection/source-binding checks pass | Development application on software Vulkan; includes resize, focus loss, box selection, proxy selection and returning to filaments |
| `headless-soak.json` | 20 state/update invariants pass; 36,000 fixed steps, 81,920 primaries and 327,680 secondary fibres | 600 seconds of simulated timeline, not 600 seconds of sustained GPU execution; zero steady-loop geometry rebuild/upload |
| `pass-gating.json` | Observed 3D draw calls fall from 5 for hybrid to 0 with all scene passes disabled | Rendering-server counters; UI canvas is counted separately |
| `background-composition.json` | The procedural background preserves fine source lines | 45,680 changed pixels when the source layer is enabled in the controlled comparison |
| `optical-cost-studies.json` | Isolated environment, normal, domain and displacement cost comparisons | Development shader variants, 180 samples, 1120 × 800, software Vulkan; not the final preset or hardware benchmark |
| `optical-motion.json` | Moving optical response with unchanged membership and mesh-build count | Earlier fixed-step study identified by shader hash; not real-time playback throughput |

The tests remain small scripts beside the implementation. The final Windows build
reruns numerical, core, integration and renderer checks from its exact source
revision, then executes the extracted application graphically. Its six scene
captures and short profiles identify the actual renderer and presentation fallback.
`Profile-This-PC.cmd` in the evaluator collects 600 frames on the owner's machine.

The reproducible `tools/capture_authoring_tour.gd` helper renders the integrated
application at fixed simulation steps. A capture receipt records its source files,
renderer, source IDs and transitions. Its 24 fps video rate is an encoding/playback
choice, never a measured hardware frame rate.
