// Shared OPTICAL-003 equations. Inputs are bounded by OpticalLayer; these
// functions own neither geometry nor clocks, and do not sample screen copies.
// Three broad RGB bands are an artistic approximation, not a CIE solver.
vec3 xeno_film_response(float thickness_um, float cosine_film, float phase,
		float ior_value, float dispersion, float bandwidth) {
	vec3 lambda = vec3(0.650, 0.530, 0.450);
	vec3 effective_n = vec3(ior_value) + dispersion * vec3(-0.035, 0.0, 0.045);
	vec3 optical_phase = 12.56637061436 * effective_n * thickness_um * cosine_film;
	vec3 response = 0.5 + 0.5 * cos(optical_phase / lambda + vec3(phase));
	if (bandwidth > 0.001) {
		vec3 spread = vec3(0.038, 0.035, 0.026) * bandwidth;
		vec3 lo = 0.5 + 0.5 * cos(optical_phase / (lambda - spread) + vec3(phase));
		vec3 hi = 0.5 + 0.5 * cos(optical_phase / (lambda + spread) + vec3(phase));
		response = (response * 2.0 + lo + hi) * 0.25;
	}
	return clamp(response, vec3(0.0), vec3(1.0));
}

vec3 xeno_optical_illumination(vec3 direction, vec3 p, float direction_value,
		float clock_value, float intensity, float balance) {
	float a = direction_value + clock_value * 0.18;
	float b = -direction_value * 0.7 - clock_value * 0.29 + 1.1;
	vec3 l0 = normalize(vec3(cos(a), 0.65, sin(a)));
	vec3 l1 = normalize(vec3(cos(b), -0.27, sin(b)));
	float first = pow(max(dot(direction, l0), 0.0), 10.0);
	float second = pow(max(dot(direction, l1), 0.0), 23.0);
	float projected = 0.65 + 0.35 * sin(p.x * 3.1 + p.y * 2.4 + clock_value * 0.63);
	vec3 c0 = mix(vec3(0.88, 0.92, 1.0), vec3(0.20, 0.82, 1.0), balance);
	vec3 c1 = mix(vec3(1.0, 0.94, 0.85), vec3(1.0, 0.27, 0.16), balance);
	return intensity * (first * c0 + second * c1 * projected);
}
