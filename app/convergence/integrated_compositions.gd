extends RefCounted
## Ordinary authored scene/patch data. Every route and material below is editable
## through the same controls as a user-created composition; there is no playback
## sequence, hidden simulation rule or showcase-only renderer.
const Catalogue = preload("res://convergence/composition_catalogue.gd")
const Graph = preload("res://core/synth_graph.gd")
const Examples = preload("res://core/synth_examples.gd")
const World = preload("res://ecology/world.gd")


static func _base(presets: Array, source_id: String, id: String, title: String, description: String) -> Dictionary:
	var index := Catalogue.index_of(presets, source_id)
	var p: Dictionary = presets[index].duplicate(true)
	p.id = "integrated_" + id
	p.stable_id = "composition." + id
	p.title = title
	p.description = description
	p.category = "composition"
	p.optical.merge({"enabled": true, "sky_visible": false, "optical_mix": 1.0,
		"optical_thickness": 0.32, "transmission": 0.76, "interference_strength": 0.7,
		"absorption": 0.5, "illumination_intensity": 1.0, "illumination_balance": 0.5,
		"illumination_direction": 0.0, "dispersion_strength": 0.4, "optical_field": 0.45}, true)
	for region in p.matter:
		region.optical_mix = 1.0
	p.modulation = true
	return p


static func _patch(index: int, id: String, routes: Array, bpm: float = 96.0) -> Dictionary:
	var p := Graph.blank(index)
	p.preset_id = id
	p.bpm = bpm
	p.xy = ["xy_x", "xy_y"]
	p.sources = [
		Examples.node("tide", "sine", {"clock": "displacement", "rate": 0.12}),
		Examples.node("light", "triangle", {"clock": "sky", "rate": 0.08, "phase": 0.25}),
		Examples.node("colour", "sine", {"clock": "palette", "rate": 0.06}),
		Examples.node("sequence", "sequencer", {"clock": "beat", "rate": 0.5, "steps": [0.0, 0.35, 0.8, -0.25, 0.6, -0.5, 0.2, 1.0]}),
		Examples.node("macro_a", "manual"), Examples.node("macro_b", "manual"),
		Examples.node("xy_x", "manual"), Examples.node("xy_y", "manual"),
		Examples.node("strike", "envelope", {"rate": 1.2, "param": 0.08})]
	p.routes = routes + [
		Examples.route("light-orbit", "light", "optical.illumination_direction", 1.6),
		Examples.route("light-energy", "macro_a", "optical.illumination_intensity", 0.85),
		Examples.route("spectral-phase", "colour", "optical.interference_phase", 1.25),
		Examples.route("transmission-performance", "macro_b", "optical.transmission", 0.2),
		Examples.route("strike-light", "strike", "optical.illumination_intensity", 0.9)]
	return p


static func _ecology(p: Dictionary, preset: int, seed_value: int) -> void:
	p.ecology_config = World.initial_config(preset, seed_value)
	p.ecology_enabled = true
	p.ecology_representation = "spatial"


static func all(presets: Array) -> Array:
	var result: Array = []
	var p := _base(presets, "nursery", "spectral_vortex", "Spectral Vortex Nursery",
		"Persistent vortex ribbons · shared spectral light · XY field performance")
	p.optical.optical_thickness = 0.24
	p.synth_patch = _patch(presets.size(), p.stable_id, [
		Examples.route("field-current", "tide", "matter.region0.strength", 0.45),
		Examples.route("field-origin", "xy_x", "matter.region0.origin_x", 1.5),
		Examples.route("particle-trails", "xy_y", "matter.region0.trails", 0.3, 0.2),
		Examples.route("region-orbit", "light", "matter.region1.rotation", 0.35),
		Examples.route("field-blend", "sequence", "matter.region1.mix", 0.15),
		Examples.route("ribbon-colour", "colour", "matter.region0.hue", 0.12)], 94.0)
	result.append(p)

	p = _base(presets, "living", "living_membrane", "Living Optical Membrane",
		"Planar membrane ecology in spatial optical matter · deterministic growth")
	p.matter[0].opacity = 0.32
	p.matter[0].z = -0.65
	p.matter[1].visible = 0
	p.optical.optical_thickness = 0.46
	p.distance = 13.0
	_ecology(p, 2, 12032)
	p.synth_patch = _patch(presets.size() + result.size(), p.stable_id, [
		Examples.route("membrane-weather", "tide", "matter.region0.deformation", 0.23),
		Examples.route("membrane-form", "xy_y", "matter.region0.condensation", 0.18, -0.1),
		Examples.route("membrane-thickness", "xy_x", "optical.optical_thickness", 0.18),
		Examples.route("living-growth", "tide", "eco.growth", 0.22),
		Examples.route("living-resource", "macro_b", "eco.resource", 0.35),
		Examples.route("living-alignment", "light", "eco.alignment", 0.18)], 72.0)
	result.append(p)

	p = _base(presets, "condensation", "excitable_garden", "Excitable Filament Garden",
		"Refractory population pulses · slender optical strips · independent rhythms")
	p.matter[0].condensation = 0.1
	p.matter[0].shell = 0.25
	p.matter[0].opacity = 0.28
	p.matter[0].scale = 1.35
	p.matter[0].z = -0.9
	p.optical.optical_thickness = 0.18
	p.distance = 14.0
	_ecology(p, 4, 44081)
	p.synth_patch = _patch(presets.size() + result.size(), p.stable_id, [
		Examples.route("garden-excitation", "sequence", "eco.excitation", 0.25),
		Examples.route("garden-strike", "strike", "eco.excitation", 0.35),
		Examples.route("garden-diffusion", "xy_x", "eco.diffusion", 0.035),
		Examples.route("garden-light", "tide", "matter.region0.hue", 0.18),
		Examples.route("garden-shell", "xy_y", "matter.region0.shell", 0.22)], 122.0)
	result.append(p)

	p = _base(presets, "condensation", "condensation_instrument", "Condensation Instrument",
		"XY strands-to-film performance · envelope illumination · reusable patch")
	p.matter[0].condensation = 0.45
	p.matter[0].shell = 0.4
	p.synth_patch = _patch(presets.size() + result.size(), p.stable_id, [
		Examples.route("condense-x", "xy_x", "matter.region0.condensation", 0.45),
		Examples.route("shell-y", "xy_y", "matter.region0.shell", 0.4),
		Examples.route("film-sequence", "sequence", "matter.region0.thickness", 0.18),
		Examples.route("film-weather", "tide", "matter.region0.deformation", 0.25),
		Examples.route("film-transmission", "xy_x", "optical.transmission", -0.2),
		Examples.route("film-optical-path", "xy_y", "optical.optical_thickness", 0.2)], 108.0)
	result.append(p)

	p = _base(presets, "ecosystem", "light_terrarium", "Evolutionary Light Terrarium",
		"Seeded branching and resource competition · shared light and growth controls")
	p.matter[0].visible = 0
	p.matter[1].x = 0
	p.matter[1].z = -1.4
	p.matter[1].scale = 1.2
	p.matter[1].opacity = 0.25
	p.matter[2].visible = 0
	p.distance = 15.5
	p.optical.optical_thickness = 0.57
	_ecology(p, 5, 51571)
	p.synth_patch = _patch(presets.size() + result.size(), p.stable_id, [
		Examples.route("terrarium-resource", "tide", "eco.resource", 0.22),
		Examples.route("terrarium-growth", "xy_y", "eco.growth", 0.35),
		Examples.route("terrarium-mutation", "xy_x", "eco.mutation", 0.035),
		Examples.route("terrarium-shell", "light", "matter.region1.shell", 0.15),
		Examples.route("terrarium-material", "colour", "eco.material", 0.25)], 66.0)
	result.append(p)

	p = _base(presets, "ecosystem", "matter_orchestra", "Hybrid Matter Orchestra",
		"Three generated regions and a living population on one bounded signal graph")
	p.matter[0].x = -3.1
	p.matter[1].x = 3.1
	p.matter[1].opacity = 0.32
	p.matter[2].z = -2.4
	p.matter[2].opacity = 0.25
	p.distance = 19.0
	_ecology(p, 3, 30373)
	p.synth_patch = _patch(presets.size() + result.size(), p.stable_id, [
		Examples.route("orchestra-current", "tide", "matter.region0.strength", 0.35),
		Examples.route("orchestra-pan", "xy_x", "matter.region0.x", 0.7),
		Examples.route("orchestra-film", "xy_y", "matter.region1.condensation", 0.12, -0.07),
		Examples.route("orchestra-shell", "light", "matter.region2.shell", 0.2),
		Examples.route("orchestra-growth", "sequence", "eco.growth", 0.2),
		Examples.route("orchestra-alignment", "tide", "eco.alignment", 0.18),
		Examples.route("orchestra-resource", "macro_b", "eco.resource", 0.3),
		Examples.route("orchestra-path", "xy_y", "optical.optical_thickness", 0.15)], 102.0)
	result.append(p)
	return result
