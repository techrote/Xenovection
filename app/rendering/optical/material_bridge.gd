extends RefCounted
## Uniform-only bridge: consumers retain geometry, identity, lifetime and clocks.
## The returned count is actual uniform writes, useful for resource profiling.

const UNIFORMS := {
	"optical_thickness": "xeno_thickness", "absorption": "xeno_absorption",
	"transmission": "xeno_transmission", "ior": "xeno_ior",
	"interference_phase": "xeno_phase", "interference_strength": "xeno_interference",
	"spectral_bandwidth": "xeno_bandwidth", "dispersion_strength": "xeno_dispersion",
	"reflection_intensity": "xeno_reflection", "roughness": "xeno_roughness", "optical_field": "xeno_field",
	"illumination_direction": "xeno_illumination_direction", "illumination_intensity": "xeno_illumination_intensity",
	"illumination_balance": "xeno_illumination_balance", "refraction_strength": "xeno_refraction",
	"atmospheric_density": "xeno_atmosphere", "optical_diagnostic": "xeno_diagnostic",
	"material_tint": "xeno_tint",
	"sky_frequency": "sky_frequency", "sky_speed": "sky_speed", "sky_diagonal": "sky_diagonal",
	"sky_radius": "sky_radius", "sky_warp": "sky_warp", "sky_contrast": "sky_contrast",
	"sky_intensity": "sky_intensity", "sky_rotation": "sky_rotation", "sky_pan": "sky_pan",
	"palette_phase": "palette_phase",
}

static func apply_context(material: ShaderMaterial, context: Dictionary, clocks: Dictionary,
		assignment_mix: float, cache: Dictionary = {}) -> int:
	if material == null:
		return 0
	var parameters: Dictionary = context.get("parameters", {})
	var mix_value := clampf(assignment_mix, 0.0, 1.0) * float(parameters.get("optical_mix", 0.0))
	if not bool(parameters.get("enabled", false)) or bool(parameters.get("scientific", false)):
		mix_value = 0.0
	var writes := set_uniform(material, "xeno_optical_mix", mix_value, cache)
	if mix_value <= 0.0001:
		return writes
	for key: String in UNIFORMS:
		if parameters.has(key):
			writes += set_uniform(material, str(UNIFORMS[key]), parameters[key], cache)
	if context.get("palette_lut") is Texture2D:
		writes += set_uniform(material, "palette_lut", context.palette_lut, cache)
	writes += set_uniform(material, "sky_clock", float(clocks.get("sky", 0.0)), cache)
	writes += set_uniform(material, "palette_clock", float(clocks.get("palette", 0.0)), cache)
	writes += set_uniform(material, "xeno_displacement_clock", float(clocks.get("displacement", 0.0)), cache)
	return writes

static func set_uniform(material: ShaderMaterial, name: String, value: Variant, cache: Dictionary) -> int:
	if cache.has(name) and cache[name] == value:
		return 0
	material.set_shader_parameter(name, value)
	cache[name] = value
	return 1
