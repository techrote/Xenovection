# FRANKENFIELD — FOUND-001 / Coupled-Field Study (parser fix 1)

**Native Godot 4.7 experimental visualization. No Three.js, no WebGL, no browser assets, no model downloads.**

This is a **self-contained, early, synthetic mathematical/raster experiment**, not a weight surgery application, not a transformer model and not a scientifically correct 3D embedding of semantic space. It is intended to test whether dense filamentary native rendering can coexist with exact data provenance, model-space selection, navigation and quantitatively measured perturbation.

## Run on Windows

1. Extract the folder.
2. Launch Godot 4.7 or a compatible Godot 4.7.x editor.
3. **Import** the `project.godot` file using the Project Manager; then press **F6** with `main.tscn` open or press **F5** to run the whole project.
4. The 6-layer, 48-channel synthetic network is loaded immediately from the bundled JSON. No external datasets are fetched.

Alternatively, using a Windows Godot console binary:

```powershell
& "C:\Godot_v4.7-stable_win64_console.exe" --path "C:\path\to\frankenfield_fieldstudy_001" --editor
```

## Controls

| Input | Action |
| --- | --- |
| Left click a node in the **first layer** | Select that exact input channel |
| Right click | Capture/release mouse for first-person view |
| WASD | Move camera forward/back/left/right |
| Mouse while captured | Look around |
| Q/E | Descend/ascend |
| Shift | Faster camera movement |
| Mouse wheel | Move forward/back |
| `[` / `]` or Left / Right arrow | Change source channel |
| `1` | Fixed weight structure, coloured by weight sign |
| `2` | Measured finite-difference perturbation response (default) |
| `3` | Hybrid structural and perturbation overlay |
| `P` | Reverse the input perturbation's sign |
| `F` | Point camera at selected input channel |
| F1 | Hide/show overlay |
| Esc | Release mouse |

## What is genuinely represented

The specimen has exact index coordinates `h[layer][channel]` and `W[layer][output_channel][input_channel]` and applies:

```text
h[0] = x
h[l+1] = tanh(W[l] @ h[l])
perturb[0][selected_input] += +0.125 or -0.125
Δh[l] = h_perturbed[l] - h_baseline[l]
Δz_edge(l, i -> j) = W[l][j][i] * Δh[l][i]
```

- Every rendered node maps to an exact `(layer, channel)` coordinate.
- Every filament connects an exact existing `(layer, input)` -> `(layer+1, output)` pair, with the actual signed numerical coefficient `W[layer][output][input]` (except omitted weak links with `|w| < 0.024`).
- In mode 2 or 3, a filament's hue reflects the sign of its **preactivation difference contribution**, `W[j,i] × Δh[i]`—**not** the sign of the final neuron's output delta.
- Node changes reflect `h_perturbed - h_baseline`; the overlay reports layerwise maximum absolute finite differences and independent analytic derivatives.
- The overlay uses **per-layer-normalized** pulse intensities. Relative brightness between two different layers does **not** measure absolute signal power.
- Norms, angle, filament bend, bristles, decorative stars, shimmer, screen-space motion, bloom and Euclidean distances are **artistic inventions**. They do not show learned semantic proximity, information-transfer speed, or real neural morphology.
- Selection is restricted to first-layer coordinates; exact connection picking and real parameter editing are subsequent experiments.

## Verify the mathematics independently

Python 3 and NumPy are sufficient for the offline numerical verification:

```bash
python tests/verify_specimen.py
```

This checks all 48 possible input-channel probes, analytic Jacobian propagation against central finite differences, and nonzero actual responses in every layer. The specimen generator is `make_specimen.py`; rerunning it with the installed NumPy version will deterministically regenerate the model (exact JSON byte sequence depends on rounding and serialization versions).

## Current boundaries

- Godot **Forward+ / native Vulkan** is the intended renderer; this experiment is not tested as a production-grade GPU engine or 120-FPS benchmark.
- **No actual LLM checkpoint is loaded.** A tanh MLP has no tokens, attention, KV caches, residual stream, MoE experts or training semantics.
- Runtime shader appearance, frame rate and UI have **not been validated on the owner's Windows GPU**. The project is a source package requiring owner-local testing, not a qualified Windows executable.
- The visualization is deliberately proof-of-concept quality. Native-Vulkan compute instancing, render graph engineering, semantic/data LOD and large-model out-of-core formats are future work.
- The source model is bounded to 5 weight matrices × 48 × 48 = 11,520 scalar weights. No real model weights are downloaded or modified.
- Nothing has been committed to `techrote/rustyspork-neurotzacken`. Treat the project as an isolated evaluator; promote the experiment only after it runs and is accepted.

## Engineering tests next

Check startup/viewport compile, inspect the initial scene visually, verify that selecting channels changes the measured response and not the stored weights, and report average/minimum frame rate and VRAM footprint in native Forward+ mode. Fix runtime issues before any claims about performance or aesthetic quality.

## Repair note (2026-11-23)

Fixed an invalid GDScript variable name (`signal`, which is a reserved keyword) in `main.gd` at the filament rebuild code and renamed all references to `signed_flow`. The project mathematics and specimen are unchanged. Runtime testing still depends on a Godot 4.7 installation.
