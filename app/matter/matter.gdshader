shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled, skip_vertex_transform;

// Persistent generated strips: mode 0 = integrated curves, mode 1 = shared
// parameter-domain strip topology. At condensation=1 adjacent film strips meet.
uniform int mode = 1;
uniform float row_count = 96.0;
uniform float seed_phase = 0.0;
uniform float flow_time = 0.0;
uniform float shape_time = 0.0;
uniform float normal_time = 0.0;
uniform float optical_time = 0.0;
uniform float colour_time = 0.0;
uniform float condensation = 0.7;
uniform float shell = 0.0;
uniform float thickness = 0.42;
uniform float roughness = 0.26;
uniform float absorption = 0.2;
uniform float opacity = 0.45;
uniform float pore_size = 0.22;
uniform float growth = 1.0;
uniform float strength = 1.0;
uniform float deformation = 0.45;
uniform float blend_field = 0.5;
uniform int field_kind = 0;
uniform int secondary_kind = 2;
uniform vec3 field_origin = vec3(0.0);
uniform float line_width = 0.65;
uniform float hue = 0.0;
uniform float trails = 0.35;
varying vec2 domain;
varying float field_value;
varying float strip_side;

vec3 generator(int kind, vec3 p, float t) {
	float rr = dot(p,p);
	vec3 radial = p / (0.45 + rr);
	if (kind == 0) { return vec3(-p.y,p.x,0.18*sin(p.z+t))/(0.55+rr*0.25); }
	if (kind == 1) { return -radial + vec3(0.0,0.15*sin(p.x+t),0.0); }
	if (kind == 2) { return vec3(sin(p.y*1.7+t),sin(p.z*1.3-t),sin(p.x*1.5+0.3*t)); }
	if (kind == 3) { return vec3(-p.z,0.65,p.x)/(0.8+rr*0.17); }
	if (kind == 4) { return (3.0*p*p.y-vec3(0.0,1.0,0.0)*rr)/pow(0.5+rr,2.5); }
	if (kind == 5) {
		vec3 q = p*5.0+vec3(0.0,0.0,24.0);
		return vec3(10.0*(q.y-q.x),q.x*(28.0-q.z)-q.y,q.x*q.y-(8.0/3.0)*q.z)*0.018;
	}
	return radial;
}
vec3 disturbance(vec3 p, float t) {
	vec3 moving = field_origin+vec3(sin(t*0.23),cos(t*0.31),sin(t*0.17))*0.36;
	vec3 a = p-moving;
	vec3 b = p+field_origin+vec3(1.1,-0.6,0.5);
	float mask = exp(-dot(b,b)*0.055);
	vec3 f = (generator(field_kind,a,t)*(1.0-blend_field)+generator(secondary_kind,b,t)*blend_field*mask)*strength;
	return f * min(1.0,4.0/max(length(f),0.00001));
}

vec3 film(vec2 uv) {
	float u = uv.x;
	float v = uv.y;
	float x = (u - 0.5) * 6.4;
	float y = (v - 0.5) * 4.6;
	float z = 0.58 * sin(u * TAU * 1.3 + v * 4.0 + shape_time * 0.45 + seed_phase)
		+ 0.32 * sin(v * TAU * 1.8 - u * 3.5 - shape_time * 0.3);
	vec3 flat = vec3(x,y,z);
	float phi = (u - 0.5) * 5.5;
	float theta = (v - 0.5) * 2.5;
	vec3 curved = (2.4 + z * 0.35) * vec3(sin(phi)*cos(theta), sin(theta), cos(phi)*cos(theta));
	vec3 p = mix(flat, curved, shell);
	p += disturbance(p, shape_time * 0.35 + seed_phase) * deformation;
	return p;
}

void vertex() {
	strip_side = UV.y * 2.0 - 1.0;
	vec3 p;
	if (mode == 0) {
		p = VERTEX;
		vec3 local_field = disturbance(p, flow_time * 0.6 + seed_phase);
		field_value = length(local_field);
		p += local_field * deformation * 0.5;
		domain = UV;
		vec3 tangent = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
		vec2 perpendicular = vec2(-tangent.y, tangent.x);
		perpendicular /= max(length(perpendicular), 0.0001);
		vec3 view_p = (MODELVIEW_MATRIX * vec4(p,1.0)).xyz;
		float world_per_pixel = max(-view_p.z, 0.025) * 2.0 / max(PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y, 1.0);
		view_p.xy += perpendicular * strip_side * max(0.65, line_width * 0.5) * world_per_pixel;
		VERTEX = view_p;
	} else {
		// All strip edges converge to the same parameter coordinates at m=1.
		// At m=0 they are distinct, curved hairline ribbons; not an opacity swap.
		float width_fraction = mix(0.08, 1.0, condensation);
		vec2 uv = vec2(VERTEX.x, VERTEX.y + strip_side * width_fraction / (2.0 * row_count));
		domain = uv;
		p = film(uv);
		field_value = length(disturbance(p, shape_time * 0.35 + seed_phase));
		VERTEX = (MODELVIEW_MATRIX * vec4(p,1.0)).xyz;
	}
	NORMAL = vec3(0.0,0.0,1.0);
}

void fragment() {
	float edge = 1.0 - smoothstep(0.55,1.0,abs(strip_side));
	float time_phase = flow_time * 0.24;
	float lum = 0.65 + 0.35 * sin(TAU * (domain.x * 4.0 - time_phase) + seed_phase);
	vec3 tint = 0.55 + 0.38 * cos(TAU * (vec3(0.01,0.29,0.59) + hue + colour_time * 0.014 + field_value * 0.09));
	if (mode == 0) {
		float bead = pow(max(0.0, sin(TAU * (domain.x * 2.0 - time_phase) + seed_phase)), 14.0);
		ALBEDO = mix(tint * (0.6 + lum), vec3(0.75,0.93,1.0), bead * trails);
		ALPHA = opacity * edge * min(1.0, line_width) * (0.72 + bead * trails * 0.28);
	} else {
		vec2 cells = domain * vec2(24.0,30.0);
		vec2 cell = floor(cells);
		vec2 local = fract(cells) - 0.5;
		float weather = sin(cell.x * 0.71 + cell.y * 0.43 + shape_time * 0.53 + seed_phase);
		float radius = clamp(pore_size + weather * 0.055 + field_value * 0.035, 0.0, 0.47);
		float hole = mix(smoothstep(radius - 0.025, radius + 0.025, length(local)),1.0,1.0-smoothstep(0.0,0.035,pore_size));
		float lace = 1.0 - smoothstep(0.025,0.075,min(abs(local.x),abs(local.y)));
		float boundary = 0.5 + 0.47 * sin(domain.x * 5.3 + domain.y * 4.5 + seed_phase + shape_time * 0.15);
		float grown = smoothstep(boundary - 0.04, boundary + 0.04, growth);
		vec3 raw_n = cross(dFdx(VERTEX), dFdy(VERTEX));
		vec3 n = raw_n / max(length(raw_n),0.000001);
		n = normalize(n + vec3(sin(domain.y*42.0+normal_time)*0.12,cos(domain.x*39.0-normal_time)*0.12,0.001));
		float incidence = clamp(abs(dot(n, normalize(-VERTEX))),0.0,1.0);
		float fresnel = pow(1.0-incidence, 3.0);
		// Three broad RGB phase samples; artistically motivated thin-film
		// approximation, not spectral transport or actual screen refraction.
		float phase = (thickness * 14.0 + 0.6 * field_value) * sqrt(0.6 + incidence*0.4);
		vec3 spectral = 0.52 + 0.42 * cos(phase * vec3(1.0,1.25,1.58) + hue*TAU + optical_time*0.12);
		float reflected = mix(pow(0.5+0.5*sin(n.x*8.0+n.y*5.0+optical_time*0.27),4.0),0.55,roughness);
		float transmitted = exp(-absorption * thickness / max(incidence,0.18));
		ALBEDO = mix(tint * (0.65 + lum * 0.35), spectral * (0.55 + reflected*0.55 + fresnel*0.8) * transmitted, condensation);
		ALBEDO += lace * spectral * 0.16 * condensation;
		ALPHA = opacity * mix(edge, hole * grown * (0.65 + 0.35*fresnel), condensation);
	}
}
