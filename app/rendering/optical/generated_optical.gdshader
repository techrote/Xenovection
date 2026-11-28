shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

#include "res://rendering/optical/generated_optical_contract.gdshaderinc"

uniform vec4 family_tint : source_color = vec4(0.35, 0.8, 0.9, 0.7);
uniform float ecology_material_gain : hint_range(0.15, 1.4) = 1.0;
instance uniform float organism_energy = 0.0;
instance uniform float organism_excitation = 0.0;
instance uniform float organism_phase = 0.0;
instance uniform float organism_signal = 0.0;
varying vec4 organism_state;
varying vec3 generated_world_position;
varying vec3 generated_local_position;

void vertex() {
	// Core MeshInstances use instance uniforms; MultiMesh branches/trails use
	// INSTANCE_CUSTOM r/g/b/a. All families can share persistent material objects.
	organism_state = clamp(max(vec4(organism_energy, organism_excitation, organism_phase, organism_signal),
		INSTANCE_CUSTOM), vec4(0.0), vec4(1.0));
	generated_local_position = VERTEX;
	generated_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - generated_world_position);
	float facing = abs(dot(n, v));
	float pulse = 0.5 + 0.5 * sin(organism_state.z * TAU);
	vec3 colour = family_tint.rgb * (0.26 + 0.45 * facing + organism_state.x * 0.32);
	colour += vec3(0.28, 0.48, 0.55) * organism_state.y * (0.4 + 0.6 * pulse);
	float coverage = family_tint.a * (0.68 + 0.32 * pow(1.0 - facing, 2.0));
	vec4 optical = xeno_generated_optics(colour, coverage, generated_local_position,
		generated_world_position, n, v, organism_state.w * TAU);
	// Observed energy and excitation remain visible even at full optical mix;
	// placing these only in the legacy colour would erase them at assignment 1.
	float emission = organism_state.y * (0.4 + 0.6 * pulse);
	ALBEDO = (optical.rgb * (0.70 + organism_state.x * 0.60)
		+ family_tint.rgb * emission * 0.45) * clamp(ecology_material_gain,0.15,1.4);
	ALPHA = optical.a;
}
