#include "res://rendering/optical/spectral_field.gdshaderinc"
#include "res://rendering/optical/spectral_math.gdshaderinc"

// Read-only material adapter for generated geometry. A common environment and
// optical clocks are sampled without acquiring topology or simulation ownership.
// This adapter intentionally has no screen/depth samplers. Refraction here is
// analytical environment transmission; the qualified source proxy retains its
// separate, opt-in screen/depth-copy variant.
uniform float xeno_optical_mix = 0.0;
uniform float xeno_thickness = 0.35;
uniform float xeno_absorption = 0.7;
uniform float xeno_transmission = 0.78;
uniform float xeno_ior = 1.45;
uniform float xeno_phase = 0.0;
uniform float xeno_interference = 0.7;
uniform float xeno_bandwidth = 0.45;
uniform float xeno_dispersion = 0.25;
uniform float xeno_reflection = 0.85;
uniform float xeno_roughness = 0.19;
uniform float xeno_field = 0.4;
uniform float xeno_illumination_direction = 0.0;
uniform float xeno_illumination_intensity = 0.65;
uniform float xeno_illumination_balance = 0.5;
uniform float xeno_refraction = 0.0;
uniform float xeno_atmosphere = 0.0;
uniform float xeno_diagnostic = 0.0;
uniform float xeno_displacement_clock = 0.0;
uniform vec4 xeno_tint : source_color = vec4(0.32, 0.59, 0.64, 1.0);

vec4 xeno_generated_optics(vec3 legacy_rgb, float legacy_alpha,
		vec3 local_p, vec3 world_p, vec3 world_n, vec3 world_v, float spectral_shift) {
	if (xeno_optical_mix <= 0.0001) {
		return vec4(legacy_rgb, legacy_alpha);
	}
	vec3 n = normalize(world_n);
	vec3 v = normalize(world_v);
	if (dot(n, v) < 0.0) { n = -n; }
	float facing = clamp(dot(n, v), 0.0, 1.0);
	vec3 reflection = reflect(-v, n);
	float field = 0.5 + 0.5 * sin(dot(local_p, vec3(1.7, 2.3, 0.9))
		+ xeno_displacement_clock * 0.81 + world_p.z * 0.43);
	float film_thickness = clamp(xeno_thickness * mix(1.0, 0.35 + 1.3 * field, xeno_field), 0.02, 3.3);
	float eta = 1.0 / max(xeno_ior, 1.0001);
	float cosine_film = sqrt(max(0.0001, 1.0 - eta * eta * (1.0 - facing * facing)));
	float optical_path = min(8.0, film_thickness / max(cosine_film, 0.12));
	float r0 = pow((xeno_ior - 1.0) / (xeno_ior + 1.0), 2.0);
	float dielectric = r0 + (1.0 - r0) * pow(1.0 - facing, 5.0);
	vec3 extinction = max(vec3(0.04), vec3(1.12) - xeno_tint.rgb);
	vec3 transmit = exp(-extinction * xeno_absorption * optical_path * mix(1.0, 0.65 + field * 0.7, xeno_field));
	vec3 response = xeno_film_response(film_thickness, cosine_film,
		xeno_phase + spectral_shift + palette_clock * 0.32 + xeno_field * field * 1.7,
		xeno_ior, xeno_dispersion, xeno_bandwidth);
	vec3 film_colour = mix(vec3(1.0), vec3(0.35) + response * 0.9, xeno_interference);
	vec3 reflected = spectral_environment(reflection);
	if (xeno_roughness > 0.08) {
		vec3 tangent = normalize(cross(reflection, abs(reflection.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		float spread = xeno_roughness * xeno_roughness * 0.48;
		reflected = (reflected * 2.0 + spectral_environment(normalize(reflection + tangent * spread))
			+ spectral_environment(normalize(reflection - tangent * spread))) * 0.25;
	}
	vec3 radiance = reflected + xeno_optical_illumination(reflection,
		local_p, xeno_illumination_direction, sky_clock, xeno_illumination_intensity, xeno_illumination_balance);
	vec3 refracted = refract(-v, n, eta);
	vec3 transmitted_light = spectral_environment(normalize(refracted)) * (0.09 + 0.13 * xeno_refraction);
	float trans_weight = xeno_transmission * (1.0 - dielectric);
	float surviving = dot(transmit, vec3(0.2126, 0.7152, 0.0722)) * trans_weight;
	float optical_alpha = clamp(1.0 - surviving * (1.0 - 0.35 * legacy_alpha), 0.03, 1.0);
	vec3 reflected_light = radiance * film_colour * dielectric * xeno_reflection;
	float mist = xeno_atmosphere * (0.3 + 0.7 * field) * (1.0 - exp(-optical_path * 0.65));
	vec3 scattered = (vec3(0.14, 0.22, 0.27) + radiance * 0.055) * mist;
	float key = pow(max(dot(n, normalize(vec3(-0.45, 0.75, 0.4))), 0.0), 3.0);
	vec3 optical_rgb = reflected_light + transmitted_light * transmit * trans_weight + scattered;
	optical_rgb += xeno_tint.rgb * (1.0 - xeno_transmission) * (0.025 + key * 0.08);
	optical_rgb = clamp(optical_rgb / max(optical_alpha, 0.08), vec3(0.0), vec3(8.0));
	if (xeno_diagnostic > 0.5) {
		if (xeno_diagnostic < 1.5) {
			optical_rgb = vec3(clamp(optical_path / 4.0, 0.0, 1.0));
		} else if (xeno_diagnostic < 2.5) {
			optical_rgb = transmit * trans_weight;
		} else {
			optical_rgb = vec3(dielectric);
		}
	}
	// Preserve real strip/particle coverage and membrane holes. Optical response
	// may attenuate authored coverage, never fill a geometrical hole or widen a line.
	return vec4(mix(legacy_rgb, optical_rgb, xeno_optical_mix),
		legacy_alpha * mix(1.0, optical_alpha, xeno_optical_mix));
}
