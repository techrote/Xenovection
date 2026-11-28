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
uniform float optical_mix : hint_range(0.0, 1.0) = 0.0;
uniform float optical_thickness : hint_range(0.02, 2.0) = 0.35;
uniform float absorption : hint_range(0.0, 6.0) = 0.7;
uniform float transmission : hint_range(0.0, 1.0) = 0.78;
uniform float ior : hint_range(1.0, 2.4) = 1.45;
uniform float interference_phase : hint_range(-6.283, 6.283) = 0.0;
uniform float interference_strength : hint_range(0.0, 1.0) = 0.7;
uniform float spectral_bandwidth : hint_range(0.0, 1.0) = 0.45;
uniform float dispersion_strength : hint_range(0.0, 1.0) = 0.25;
uniform float reflection_intensity : hint_range(0.0, 2.0) = 0.85;
uniform float optical_field : hint_range(0.0, 1.0) = 0.4;
uniform float illumination_direction : hint_range(-3.14159, 3.14159) = 0.0;
uniform float illumination_intensity : hint_range(0.0, 3.0) = 0.65;
uniform float illumination_balance : hint_range(0.0, 1.0) = 0.5;
uniform float refraction_strength : hint_range(0.0, 1.0) = 0.0;
uniform float atmospheric_density : hint_range(0.0, 1.0) = 0.0;
uniform float optical_diagnostic : hint_range(0.0, 3.0) = 0.0;
#ifdef XENO_REFRACTIVE
uniform sampler2D optical_screen : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D optical_depth : hint_depth_texture, repeat_disable, filter_nearest;
#endif
varying vec3 world_position;
varying vec3 local_position;

void vertex() {
	vec3 p = VERTEX;
	local_position = p;
	if (displacement > 0.0001) {
		float envelope = 1.0;
		if (surface_mode == 1) {
			float pin = sin(UV.x * 3.14159265359);
			envelope = pin * pin;
		} else if (surface_mode == 2) {
			float pin = sin(UV.x * 3.14159265359) * sin(UV.y * 3.14159265359);
			envelope = pin * pin;
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

// Three representative wavelength bands; optional bandwidth broadening samples
// a second pair of wavelengths per band. This is not an XYZ/CIE spectral solver.
vec3 film_response(float thickness_um, float cosine_film, float phase) {
	vec3 lambda = vec3(0.650, 0.530, 0.450);
	vec3 effective_n = vec3(ior) + dispersion_strength * vec3(-0.035, 0.0, 0.045);
	vec3 optical_phase = 12.56637061436 * effective_n * thickness_um * cosine_film;
	vec3 response = 0.5 + 0.5 * cos(optical_phase / lambda + vec3(phase));
	if (spectral_bandwidth > 0.001) {
		vec3 spread = vec3(0.038, 0.035, 0.026) * spectral_bandwidth;
		vec3 lo = 0.5 + 0.5 * cos(optical_phase / (lambda - spread) + vec3(phase));
		vec3 hi = 0.5 + 0.5 * cos(optical_phase / (lambda + spread) + vec3(phase));
		response = (response * 2.0 + lo + hi) * 0.25;
	}
	return clamp(response, vec3(0.0), vec3(1.0));
}

vec3 optical_illumination(vec3 direction, vec3 p) {
	float a = illumination_direction + sky_clock * 0.18;
	float b = -illumination_direction * 0.7 - sky_clock * 0.29 + 1.1;
	vec3 l0 = normalize(vec3(cos(a), 0.65, sin(a)));
	vec3 l1 = normalize(vec3(cos(b), -0.27, sin(b)));
	float first = pow(max(dot(direction, l0), 0.0), 10.0);
	float second = pow(max(dot(direction, l1), 0.0), 23.0);
	float projected = 0.65 + 0.35 * sin(p.x * 3.1 + p.y * 2.4 + sky_clock * 0.63);
	vec3 c0 = mix(vec3(0.88, 0.92, 1.0), vec3(0.20, 0.82, 1.0), illumination_balance);
	vec3 c1 = mix(vec3(1.0, 0.94, 0.85), vec3(1.0, 0.27, 0.16), illumination_balance);
	return illumination_intensity * (first * c0 + second * c1 * projected);
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
		vec3 warped = reflection + domain_warp * 0.23 * vec3(
			sin(p.y * 3.1 + sky_clock * 0.17),
			cos(p.z * 2.7 - sky_clock * 0.19),
			sin(p.x * 2.3 + sky_clock * 0.13));
		// At extreme allowed warp, the offset can cancel the unit reflection.
		// Preserve the unwarped direction instead of normalizing a zero vector.
		float warped_length_squared = dot(warped, warped);
		if (warped_length_squared > 0.00000001) {
			reflection = warped * inversesqrt(warped_length_squared);
		}
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
	// The exact legacy material remains the zero-mix branch.
	float legacy_alpha = mix(surface_opacity, 1.0, pow(1.0 - facing, 2.0));
	ALPHA = legacy_alpha;
	if (optical_mix > 0.0001) {
		vec3 p = local_position / max(displacement_scale, 0.05);
		// Same wave family/clock as geometric weather, coupled but not a mesh
		// thickness measurement. World offset distinguishes the second sheet.
		float field = 0.5 + 0.5 * sin(dot(p, vec3(1.7, 2.3, 0.9))
			+ displacement_clock * 0.81 + world_position.z * 0.43);
		float thickness = clamp(optical_thickness * mix(1.0, 0.35 + 1.3 * field, optical_field), 0.02, 3.3);
		float eta = 1.0 / max(ior, 1.0001);
		float cosine_film = sqrt(max(0.0001, 1.0 - eta * eta * (1.0 - facing * facing)));
		float optical_path = min(8.0, thickness / max(cosine_film, 0.12));
		float r0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
		float dielectric = r0 + (1.0 - r0) * pow(1.0 - facing, 5.0);
		vec3 extinction = max(vec3(0.04), vec3(1.12) - material_tint.rgb);
		vec3 transmit = exp(-extinction * absorption * optical_path * mix(1.0, 0.65 + field * 0.7, optical_field));
		vec3 film = film_response(thickness, cosine_film, interference_phase + palette_clock * 0.32 + optical_field * field * 1.7);
		vec3 film_colour = mix(vec3(1.0), vec3(0.35) + film * 0.9, interference_strength);
		vec3 radiance = reflected + optical_illumination(reflection, p);
		vec3 refracted = refract(-v, n, eta);
		// Bounded analytically generated transmission for offscreen or invalid
		// samples. A screen copy contains opaque content only, not other films.
		vec3 transmitted_light = spectral_environment(normalize(refracted)) * (0.09 + 0.13 * refraction_strength);
#ifdef XENO_REFRACTIVE
		vec2 offset = NORMAL.xy * refraction_strength * min(optical_path, 2.5) * (ior - 1.0) * 0.045;
		vec2 uv = SCREEN_UV + offset;
		float margin = 0.002;
		if (all(greaterThan(uv, vec2(margin))) && all(lessThan(uv, vec2(1.0 - margin)))) {
			float scene_depth = texture(optical_depth, uv).r;
			// Forward+ reverse Z: smaller depth is farther away. Reject
			// opaque foreground crossing and screen-edge extrapolation.
			if (scene_depth < FRAGCOORD.z - 0.00002) {
				vec2 red_uv = uv + offset * dispersion_strength * 0.16;
				vec2 blue_uv = uv - offset * dispersion_strength * 0.16;
				vec3 sample_colour = texture(optical_screen, uv).rgb;
				if (all(greaterThan(red_uv, vec2(margin))) && all(lessThan(red_uv, vec2(1.0 - margin)))
					&& all(greaterThan(blue_uv, vec2(margin))) && all(lessThan(blue_uv, vec2(1.0 - margin)))
					&& texture(optical_depth, red_uv).r < FRAGCOORD.z - 0.00002
					&& texture(optical_depth, blue_uv).r < FRAGCOORD.z - 0.00002) {
					sample_colour.r = texture(optical_screen, red_uv).r;
					sample_colour.b = texture(optical_screen, blue_uv).b;
				}
				transmitted_light = mix(transmitted_light, sample_colour, refraction_strength);
			}
		}
#endif
		float trans_weight = transmission * (1.0 - dielectric);
		float surviving = dot(transmit, vec3(0.2126, 0.7152, 0.0722)) * trans_weight;
		float optical_alpha = clamp(1.0 - surviving * (1.0 - 0.35 * surface_opacity), 0.03, 1.0);
		vec3 reflected_light = radiance * film_colour * dielectric * reflection_intensity;
		// Thin local scattering cue; no integration of a participating volume.
		float mist = atmospheric_density * (0.3 + 0.7 * field) * (1.0 - exp(-optical_path * 0.65));
		vec3 scattered = (vec3(0.14, 0.22, 0.27) + radiance * 0.055) * mist;
		vec3 optical_rgb = reflected_light + transmitted_light * transmit * trans_weight + scattered;
		optical_rgb += material_tint.rgb * (1.0 - transmission) * (0.025 + key * 0.08);
		optical_rgb = clamp(optical_rgb / max(optical_alpha, 0.08), vec3(0.0), vec3(8.0));
		ALBEDO = mix(ALBEDO, optical_rgb, optical_mix);
		ALPHA = mix(legacy_alpha, optical_alpha, optical_mix);
		if (optical_diagnostic > 0.5) {
			if (optical_diagnostic < 1.5) {
				ALBEDO = vec3(clamp(optical_path / 4.0, 0.0, 1.0));
			} else if (optical_diagnostic < 2.5) {
				ALBEDO = transmit * trans_weight;
			} else {
				ALBEDO = vec3(dielectric);
			}
			ALPHA = 0.94;
		}
	}
#endif
}
