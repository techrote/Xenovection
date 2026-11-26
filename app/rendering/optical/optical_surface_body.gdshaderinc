#include "res://rendering/optical/spectral_field.gdshaderinc"

uniform float normal_clock = 0.0;
uniform float displacement_clock = 0.0;
uniform float normal_strength = 0.24;
uniform float displacement = 0.12;
uniform float displacement_scale = 1.0;
uniform float domain_warp = 0.12;
uniform float roughness : hint_range(0.02, 1.0) = 0.19;
uniform float metallic : hint_range(0.0, 1.0) = 0.92;
uniform float surface_opacity : hint_range(0.1, 1.0) = 1.0;
uniform vec4 material_tint : source_color = vec4(0.32, 0.59, 0.64, 1.0);
uniform int surface_mode = 0; // 0 knot, 1 endpoint-pinned ribbons, 2 edge-pinned membrane.
varying vec3 world_position;
varying vec3 local_position;

void vertex() {
	vec3 p = VERTEX;
	local_position = p;
	if (displacement > 0.0001) {
		float envelope = 1.0;
		if (surface_mode == 1) {
			envelope = pow(sin(UV.x * 3.14159265359), 2.0);
		} else if (surface_mode == 2) {
			envelope = pow(sin(UV.x * 3.14159265359) * sin(UV.y * 3.14159265359), 2.0);
		}
		vec3 k0 = vec3(1.7, 2.3, 0.9) / max(displacement_scale, 0.05);
		vec3 k1 = vec3(-2.9, 1.4, 2.1) / max(displacement_scale, 0.05);
		float a = dot(p, k0) + displacement_clock * 0.81;
		float b = dot(p, k1) - displacement_clock * 0.53;
		float height = 0.62 * sin(a) + 0.38 * sin(b);
		vec3 gradient = 0.62 * cos(a) * k0 + 0.38 * cos(b) * k1;
		float amount = displacement * displacement_scale * 0.34 * envelope;
		p += NORMAL * amount * height;
		// Bounded differential-normal approximation; connectivity is unchanged.
		NORMAL = normalize(NORMAL - amount * (gradient - NORMAL * dot(gradient, NORMAL)));
	}
	VERTEX = p;
	world_position = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_position);
	if (dot(n, v) < 0.0) n = -n;
	if (normal_strength > 0.0001) {
		vec3 p = local_position / max(displacement_scale, 0.05);
		vec3 ripple = vec3(
			sin(p.y * 31.0 + sin(p.z * 11.0) + normal_clock * 0.71),
			sin(p.z * 27.0 + sin(p.x * 13.0) - normal_clock * 0.83),
			sin(p.x * 29.0 + sin(p.y * 17.0) + normal_clock * 0.61));
		ripple = (MODEL_MATRIX * vec4(ripple, 0.0)).xyz;
		n = normalize(n + (ripple - n * dot(ripple, n)) * normal_strength * 0.24);
	}
	vec3 reflection = reflect(-v, n);
	if (domain_warp > 0.0001) {
		vec3 p = local_position / max(displacement_scale, 0.05);
		// Warp only the reflected sampling domain: no vertex or topology changes.
		reflection = normalize(reflection + domain_warp * 0.23 * vec3(
			sin(p.y * 3.1 + sky_clock * 0.17),
			cos(p.z * 2.7 - sky_clock * 0.19),
			sin(p.x * 2.3 + sky_clock * 0.13)));
	}
	vec3 reflected = spectral_environment(reflection);
	if (roughness > 0.08) {
		// Three directional samples approximate a rough reflection lobe.
		// This is analytical environment lighting, not ray-traced reflection.
		vec3 tangent = normalize(cross(reflection, abs(reflection.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		float spread = roughness * roughness * 0.48;
		reflected = (reflected * 2.0 + spectral_environment(normalize(reflection + tangent * spread))
			+ spectral_environment(normalize(reflection - tangent * spread))) * 0.25;
	}
	float facing = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = 0.12 + 0.88 * pow(1.0 - facing, 4.0);
	vec3 conductor = mix(vec3(0.68), material_tint.rgb * 0.55 + vec3(0.56), metallic);
	float key = pow(max(dot(n, normalize(vec3(-0.45, 0.75, 0.4))), 0.0), 3.0);
	vec3 body = material_tint.rgb * (0.025 + key * 0.08) * (1.0 - metallic * 0.75);
	ALBEDO = body + reflected * conductor * mix(fresnel, 0.70 + 0.30 * fresnel, metallic);
#ifdef XENO_TRANSLUCENT
	// Artistic thin-sheet transmission: alpha blending, not screen refraction.
	ALPHA = mix(surface_opacity, 1.0, pow(1.0 - facing, 2.0));
#endif
}
