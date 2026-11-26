// Original analytical field; no PlasmaTerm/XenoField source is incorporated.
// Both the visible environment and the reflected environment use this function.
// Sampling a direction analytically avoids a dynamic cubemap update/filter pass.
uniform sampler2D palette_lut : source_color, filter_linear, repeat_enable;
uniform vec2 sky_frequency = vec2(1.6, 2.1);
uniform float sky_clock = 0.0;
uniform float palette_clock = 0.0;
uniform float palette_phase = 0.0;
uniform float sky_speed = 0.55;
uniform float sky_diagonal = 0.65;
uniform float sky_radius = 1.7;
uniform float sky_warp = 0.38;
uniform float sky_contrast = 1.7;
uniform float sky_intensity = 2.3;
uniform float sky_rotation = 0.0;
uniform vec2 sky_pan = vec2(0.0);

vec3 spectral_environment(vec3 ray_direction) {
	vec3 d = normalize(ray_direction);
	float cr = cos(sky_rotation);
	float sr = sin(sky_rotation);
	d.xz = mat2(vec2(cr, -sr), vec2(sr, cr)) * d.xz;
	// A directional Cartesian domain has no panorama seam or pole singularity.
	vec2 p = vec2(d.x * 3.4 + d.z * 0.7, d.y * 3.2 + d.z * 1.1) + sky_pan;
	float t = sky_clock * sky_speed;
	if (sky_warp > 0.0001) {
		p += sky_warp * vec2(sin(p.y * 1.7 + t * 0.21), cos(p.x * 1.1 - t * 0.17));
	}
	float field = 0.37 * sin(p.x * sky_frequency.x + t)
		+ 0.28 * sin(p.y * sky_frequency.y - t * 1.23)
		+ 0.20 * sin((p.x + p.y) * sky_diagonal + t * 0.67)
		+ 0.15 * sin(length(p) * sky_radius - t * 0.86);
	float transfer = clamp(0.5 + field * 0.46 * sky_contrast, 0.0, 1.0);
	vec3 pigment = texture(palette_lut, vec2(fract(transfer + palette_phase + palette_clock * 0.025), 0.5)).rgb;
	float bands = 0.22 + 0.78 * pow(0.5 + 0.5 * sin(field * 9.0 + t * 0.15), 2.0);
	// Thin broad-spectrum softboxes give readable metal highlights among the colour.
	float softbox = pow(max(0.0, dot(d, normalize(vec3(-0.3, 0.8, 0.5)))), 44.0);
	return sky_intensity * (pigment * bands + vec3(0.6, 0.75, 0.82) * softbox * 0.5);
}
