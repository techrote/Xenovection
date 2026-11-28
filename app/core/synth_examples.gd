extends RefCounted
const Graph = preload("res://core/synth_graph.gd")

static func node(id: String, kind: String, settings: Dictionary = {}) -> Dictionary:
	var n := Graph.source_defaults(id, kind)
	n.merge(settings, true)
	return n

static func route(id: String, source: String, target: String, depth: float, offset: float = 0.0, operation: String = "add") -> Dictionary:
	return {"id": id, "source": source, "target": target, "amplitude": depth, "offset": offset, "operation": operation, "mask": 1.0, "enabled": true}

static func instrument(title: String, preset: int, bpm: float, sources: Array, routes: Array, performance: Array) -> Dictionary:
	var p := Graph.blank(preset)
	p.bpm = bpm
	p.sources = sources + [node("macro_a", "manual"), node("macro_b", "manual"), node("xy_x", "manual"), node("xy_y", "manual"), node("strike", "envelope", {"rate": 1.6, "param": 0.12})]
	p.routes = routes + performance
	p.xy = ["xy_x", "xy_y"]
	return {"title": title, "patch": p}

static func all() -> Array:
	return [
		instrument("Vortex Conductor", 6, 94, [
			node("current", "sine", {"rate": 0.21}), node("eddy", "triangle", {"clock": "normal", "rate": 0.13, "phase": 0.25}),
			node("interaction", "multiply", {"a": "current", "b": "eddy"}), node("drift", "slew", {"a": "interaction", "param": 0.3})
		], [
			route("phase-current", "current", "filament.phase_speed", 0.85),
			route("braid-eddy", "eddy", "filament.braid_radius", 0.014, 0.014),
			route("eddy-resonance", "drift", "filament.resonance", 0.023, 0.02),
			route("vortex-colour", "interaction", "filament.palette_phase", 0.25)
		], [
			route("macro-energy", "macro_a", "filament.intensity", 0.6),
			route("macro-density", "macro_b", "filament.coverage", 0.35, -0.2),
			route("xy-flow", "xy_x", "filament.phase_frequency", 1.0),
			route("xy-deform", "xy_y", "filament.wave_amplitude", 0.065, 0.03),
			route("strike-glow", "strike", "filament.opacity", 0.3)
		]),
		instrument("Weather Instrument", 3, 72, [
			node("tide", "sine", {"clock": "displacement", "rate": 0.12}),
			node("weather", "walk", {"clock": "normal", "rate": 0.7, "param": 0.28, "seed": 7382}),
			node("clouds", "mix", {"a": "weather", "b": "tide", "param": 0.4}),
			node("smooth", "slew", {"a": "clouds", "clock": "normal", "param": 0.5})
		], [
			route("tide-displacement", "tide", "optical.displacement", 0.09),
			route("normal-weather", "smooth", "optical.normal_strength", 0.27, 0.14),
			route("cloud-warp", "clouds", "optical.sky_warp", 0.4, 0.2),
			route("tide-roughness", "tide", "optical.roughness", 0.11)
		], [
			route("macro-light", "macro_a", "optical.sky_intensity", 0.9),
			route("macro-film", "macro_b", "optical.surface_opacity", 0.25),
			route("xy-warp", "xy_x", "optical.domain_warp", 0.3, 0.12),
			route("xy-radial", "xy_y", "optical.sky_radius", 1.5, 1.2),
			route("strike-flash", "strike", "optical.sky_intensity", 1.8)
		]),
		instrument("Filament Sequencer", 1, 126, [
			node("steps", "sequencer", {"clock": "beat", "rate": 2.0, "steps": [0, 0.8, -0.4, 1.0, 0.2, -0.6, 0.6, -1.0]}),
			node("gate", "pulse", {"clock": "beat", "rate": 1.0, "param": 0.35}),
			node("strobe", "multiply", {"a": "steps", "b": "gate"}),
			node("glide", "slew", {"a": "steps", "param": 0.08})
		], [
			route("seq-phase", "glide", "filament.phase_speed", 1.5),
			route("seq-opacity", "strobe", "filament.opacity", 0.09, 0.04),
			route("seq-braid", "glide", "filament.braid_radius", 0.06),
			route("seq-colour", "steps", "filament.palette_phase", 0.48)
		], [
			route("macro-torsion", "macro_a", "filament.braid_turns", 1.8),
			route("macro-width", "macro_b", "filament.line_width_px", 0.18),
			route("xy-frequency", "xy_x", "filament.wave_frequency", 1.0),
			route("xy-resonance", "xy_y", "filament.resonance", 0.05, 0.04),
			route("strike-pulse", "strike", "filament.intensity", 1.5)
		]),
		instrument("Spectral Layers", 2, 86, [
			node("red", "sine", {"clock": "palette", "rate": 0.12}),
			node("green", "triangle", {"clock": "sky", "rate": 0.17, "phase": 0.3}),
			node("blue", "saw", {"clock": "normal", "rate": 0.09}),
			node("colour", "colour", {"a": "red", "b": "green", "c": "blue"}),
			node("field", "vector2", {"a": "red", "b": "green"})
		], [
			route("tint-mix", "colour", "optical.material_tint", 0.22),
			route("frequency-mix", "field", "optical.sky_frequency", 0.8),
			route("colour-drift", "blue", "optical.palette_phase", 0.7),
			route("contrast-mix", "green", "optical.sky_contrast", 0.55)
		], [
			route("macro-reflection", "macro_a", "optical.metallic", 0.3),
			route("macro-diffusion", "macro_b", "optical.roughness", 0.15),
			route("xy-rotate", "xy_x", "optical.sky_rotation", 1.5),
			route("xy-warp", "xy_y", "optical.sky_warp", 0.5, 0.25),
			route("strike-spectral", "strike", "optical.sky_intensity", 1.2)
		]),
		instrument("Autonomous Organism", 0, 63, [
			node("wander", "walk", {"clock": "sky", "rate": 0.17, "seed": 38117, "param": 0.3}),
			node("noise", "noise", {"clock": "normal", "rate": 0.8, "seed": 916}),
			node("held", "hold", {"a": "noise", "clock": "beat", "rate": 0.2}),
			node("old", "delay", {"a": "feedback"}),
			node("gain", "remap", {"a": "old", "param": 0.72}),
			node("input", "remap", {"a": "wander", "param": 0.28}),
			node("feedback", "add", {"a": "gain", "b": "input"}),
			node("glide", "slew", {"a": "held", "param": 1.1})
		], [
			route("organism-flow", "feedback", "filament.phase_speed", 0.6),
			route("organism-braid", "glide", "filament.braid_radius", 0.045),
			route("organism-normal", "feedback", "optical.normal_strength", 0.18),
			route("organism-optics", "glide", "optical.sky_warp", 0.3)
		], [
			route("macro-growth", "macro_a", "optical.displacement", 0.1),
			route("macro-breath", "macro_b", "filament.opacity", 0.08),
			route("xy-phase", "xy_x", "filament.palette_phase", 0.8),
			route("xy-material", "xy_y", "optical.roughness", 0.18),
			route("strike-bloom", "strike", "filament.wave_amplitude", 0.23)
		]),
		instrument("XY Morphosis", 3, 108, [
			node("joint", "multiply", {"a": "xy_x", "b": "xy_y"}),
			node("motion", "slew", {"a": "joint", "param": 0.12}),
			node("pan", "vector2", {"a": "xy_x", "b": "xy_y"}),
			node("grid", "quantize", {"a": "xy_x", "param": 0.25})
		], [
			route("xy-pan", "pan", "optical.sky_pan", 1.6),
			route("xy-interference", "motion", "optical.sky_warp", 0.7, 0.3),
			route("xy-step", "grid", "optical.palette_phase", 1.0),
			route("xy-normal", "xy_y", "optical.normal_strength", 0.32, 0.12),
			route("xy-depth", "xy_x", "optical.displacement", 0.12)
		], [
			route("macro-film", "macro_a", "optical.surface_opacity", 0.22),
			route("macro-flow", "macro_b", "filament.phase_speed", 1.2),
			route("xy-filaments", "xy_y", "filament.wave_amplitude", 0.14, 0.06),
			route("strike-light", "strike", "optical.sky_intensity", 1.6)
		])
	]
