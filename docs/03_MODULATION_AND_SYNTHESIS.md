# Procedural wave synthesis, modulation and animated illumination

## Product intuition

The owner demonstrated XenoField SkySynth (a PlasmaTerm-derived wave generator) driving animated sky/environment lighting; changing modulation parameters made the apparent reflective patterns move, twist, reverse, shear and morph with striking intensity. This is **much more than putting an animated texture on an object**. The environment is a moving optical input, and complex geometry/normals decode it into intricate moving highlights.

The system should feel like a playable modular synthesiser whose outputs happen to be textures, materials, motion and volumes.

## Proven implementation facts vs new requirements

- [PlasmaTerm main](https://github.com/techrote/PlasmaTerm) currently documents a config-watched native Windows Terminal renderer, with four deterministic spatial sine components and configurable palettes.
- [PlasmaTerm web](https://techrote.github.io/plasmaterm/web/) exposes independent transient energy modulation. Public source at [techrote.github.io](https://github.com/techrote/techrote.github.io/tree/main/plasmaterm) routes controls through worker.postMessage and BrowserRuntime.configure_energy, **not an independently verified WebSocket server**.
- User reports a separate WebSocket modulator/offset capability. **Do not invent a verified URL/port/JSON schema**. Protocol discovery/test needed before implementing compatibility.
- [XenoField V4.4b](https://github.com/techrote/XenoField) provides a stronger wave/SkySynth environment with visible controls including frequency X/Y, speed, LUT drift, radius, diagonal wave, domain warp, field contrast and HDR radiance, plus environment-map resolution, filtering and generator FPS.
- Smooth 256-entry cyclic LUTs are part of the practical visual vocabulary. Preserve the distinction between field index and palette transfer function.

## Simplified analytical base

For 2D coordinates x,y and time t, a representative PlasmaTerm field is an average of four sine waves:
1. sin(x * fx + t)
2. sin(y * fy - 1.2 * t)
3. sin(0.25 * (x+y) + 0.6 * t)
4. sin(r * radius - t), with r the distance to a chosen centre.

Rescale -1..+1 to 0..1; optionally apply domain warp, contrast, masks; quantise/lookup colour in a continuous cyclic LUT with time-varying phase. The actual XenoField shader may differ. Port from source, retaining exact baseline comparisons; this formula is **not** a claim of source-identical XenoField rendering.

An example modulation model for visual parameter p:
- base p0, transient offset o, gain g, depth D, oscillator waveform E(t).
- effective p(t) = clamp[p0 + g * (o + D * E(t))].
- independent multiple modulation routes can sum/multiply/replace with explicit order, smoothing, limits and phase.

The web energy module currently exposes targets freq-Y, freq-X, speed, hue shift and radius, with sine, smoothed triangle, loop noise and wander noise. Other sources / target parameters are design extensions, not currently confirmed native PlasmaTerm controls.

## Proposed universal signal bus

All signals are:
- named and typed (scalar, vector, colour, event, envelope or sampled field);
- source-tagged (manual, LFO, recorded automation, external WebSocket, numerical measurement);
- time-stamped, quality/confidence annotated when measured;
- range-normalised, bounded and smoothed;
- permitted to drive any compatible shader uniform, object transform, camera-independent material parameter or lighting/volume channel.

Routing examples:
- measured signed delta -> diverging colour or counterpropagating phase, with fixed legend;
- measured absolute change -> modulator amplitude / emission;
- selection brush -> local spatial envelope and highlight;
- manual gesture -> phase velocity / warp / torsion, not actual data edits;
- slow oscillator -> HDR sky movement; fast oscillator -> local filament shimmer;
- two independent LFOs -> opposing waves in same fibre bundle.

## Modulator UI

Retain a compact, real-time, patchable interface inspired by the owner-provided XenoField Modulator panel: preset, enable, target toggles, waveform selector, amplitude, Hz, width low/high, offset, state reset, base-unchanged indication.

Expand with:
- target list: frequency, pan X/Y, rotation, speed, palette phase, warp, contrast, radius, diagonal wave, geometry displacement, normal perturbation, roughness, emission, density, fog, reflection;
- additive/multiplicative modulation per route; independent temporal rates and activation masks;
- scalar history/waveform scope and optional field preview; saved patch presets;
- pause/resume, reverse, phase lock and deterministic seeded replay.
- separate scientific readouts vs artistic parameter values.

## WebSocket boundary

Use WebSockets only as an optional external control/telemetry transport. Local GPU shader evaluates waves every frame using cached uniform values. Do **not** stream rendered ANSI cells, entire skybox frames, or per-weight lines over a socket.

Proposed (not established) design for new transport:
- localhost-only by default; versioned handshake and explicit capabilities.
- messages tagged by stream ID, sequence and time; rate limited/coalesced; bounded queues and interpolation.
- controls are ephemeral offsets until a user deliberately commits a preset; no hidden persistent config mutation.
- disconnect: freeze or smoothly decay to preset, with visible status.
- independent clocks for GPU frame, shader time, environment-map refresh and incoming telemetry.
- no arbitrary code, shader, filesystem or model edit execution over the wire.

First native study should port the analytical field to a shader, prove smooth LUT cycling and independent reflected-environment response, and *then* add transport. Performance must be validated with XenoField and Godot side-by-side captures, not inferred from screenshots.
