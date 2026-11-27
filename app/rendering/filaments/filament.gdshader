shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

// Persistent, instanced source edges. Geometry is animated exclusively here.
// The local Y axis maps [0, 1] to the exact source endpoints. X/Z are unit
// perpendicular vectors. INSTANCE_CUSTOM = stable seed, source weight,
// selection flag, decorative fibre phase. Decorative instances are a separate
// draw and have no independent source-edge identity.
uniform float clock_filament = 0.0;
uniform float clock_palette = 0.0;
uniform float phase_speed : hint_range(-8.0, 8.0) = 0.7;
uniform float phase_frequency : hint_range(0.0, 16.0) = 2.4;
uniform float wave_amplitude : hint_range(0.0, 2.0) = 0.11;
uniform float wave_frequency : hint_range(0.0, 8.0) = 1.5;
uniform float braid_radius : hint_range(0.0, 1.0) = 0.065;
uniform float braid_turns : hint_range(0.0, 8.0) = 2.0;
uniform float turbulence : hint_range(0.0, 1.0) = 0.025;
uniform float resonance : hint_range(0.0, 1.0) = 0.04;
uniform float line_width_px : hint_range(0.05, 6.0) = 0.52;
uniform float opacity : hint_range(0.0, 1.0) = 0.16;
uniform float intensity : hint_range(0.0, 4.0) = 0.9;
uniform float palette_amount : hint_range(0.0, 1.0) = 0.18;
uniform float palette_phase = 0.0;
uniform float coverage : hint_range(0.0, 1.0) = 1.0;
uniform float adaptive_coverage : hint_range(0.0, 1.0) = 1.0;
uniform float selection_fade : hint_range(0.0, 1.0) = 0.28;
uniform bool has_selection = false;
uniform bool scientific = false;
uniform bool decorative = false;
uniform bool counterflow = true;
uniform vec4 positive_colour : source_color = vec4(0.08, 0.72, 0.87, 1.0);
uniform vec4 negative_colour : source_color = vec4(0.95, 0.23, 0.19, 1.0);

varying float edge_seed;
varying float edge_weight;
varying float edge_selected;
varying float flow_direction;
varying float pixel_half_extent;
varying float projected_coverage;

// Both position and its derivative are evaluated analytically. Keeping the
// envelope exactly zero at t=0/1 prevents detached whiskers at source nodes.
void path_at(float t, float seed, float fibre, float direction,
             out vec3 point, out vec3 tangent) {
    point = vec3(0.0, t, 0.0);
    tangent = vec3(0.0, 1.0, 0.0);
    if (!scientific) {
        float envelope = 4.0 * t * (1.0 - t);
        float envelope_d = 4.0 - 8.0 * t;
        vec2 offset = vec2(0.0);
        vec2 derivative = vec2(0.0);
        float phase = clock_filament * phase_speed * direction;
        if (wave_amplitude > 0.00001) {
            float a = TAU * wave_frequency * t - phase + seed * TAU;
            float b = TAU * wave_frequency * 0.73 * t + phase * 0.69 + seed * 9.1;
            offset += wave_amplitude * vec2(sin(a), 0.55 * sin(b));
            derivative += wave_amplitude * TAU * wave_frequency * vec2(cos(a), 0.4015 * cos(b));
        }
        if (decorative && braid_radius > 0.00001) {
            float a = TAU * (braid_turns * t + fibre) + phase * 0.7 + seed * TAU;
            offset += braid_radius * vec2(cos(a), sin(a));
            derivative += braid_radius * TAU * braid_turns * vec2(-sin(a), cos(a));
        }
        if (resonance > 0.00001) {
            float carrier = sin(clock_filament * 1.27 + seed * TAU);
            offset += resonance * carrier * vec2(sin(PI * 3.0 * t), 0.6 * sin(PI * 2.0 * t));
            derivative += resonance * carrier * PI * vec2(3.0 * cos(PI * 3.0 * t), 1.2 * cos(PI * 2.0 * t));
        }
        if (turbulence > 0.00001) {
            // Bounded deterministic harmonic field, not random per-frame noise.
            float a = TAU * 3.3 * t + clock_filament * 0.41 + seed * 17.0;
            float b = TAU * 5.1 * t - clock_filament * 0.29 + seed * 23.0;
            offset += turbulence * vec2(sin(a) * cos(b), cos(a) * sin(b));
            derivative += turbulence * TAU * vec2(3.3 * cos(a) * cos(b) - 5.1 * sin(a) * sin(b),
                -3.3 * sin(a) * sin(b) + 5.1 * cos(a) * cos(b));
        }
        point.xz = envelope * offset;
        tangent.xz = envelope_d * offset + envelope * derivative;
    }
}

void vertex() {
    edge_seed = INSTANCE_CUSTOM.r;
    edge_weight = INSTANCE_CUSTOM.g;
    edge_selected = INSTANCE_CUSTOM.b;
    flow_direction = (counterflow && edge_seed < 0.5) ? -1.0 : 1.0;
    // Decorative populations counter-rotate while remaining attached to the
    // same primary edge; their source mapping never becomes a second edge.
    if (decorative && INSTANCE_CUSTOM.a > 0.5) {
        flow_direction *= -1.0;
    }
    vec3 point;
    vec3 tangent;
    path_at(UV.x, edge_seed, INSTANCE_CUSTOM.a, flow_direction, point, tangent);
    vec4 view_point = MODELVIEW_MATRIX * vec4(point, 1.0);
    vec4 view_tangent = MODELVIEW_MATRIX * vec4(tangent, 0.0);
    vec4 clip = PROJECTION_MATRIX * view_point;
    vec4 clip_tangent = PROJECTION_MATRIX * view_tangent;
    // Project the analytic tangent with the quotient derivative. No divide by
    // signed near-plane w; ordinary GPU clipping still handles crossing strands.
    vec2 pixel_tangent = (clip_tangent.xy * clip.w - clip.xy * clip_tangent.w) * VIEWPORT_SIZE;
    float tangent_length = length(pixel_tangent);
    vec2 normal_pixels = tangent_length > 0.000001 ? vec2(-pixel_tangent.y, pixel_tangent.x) / tangent_length : vec2(1.0, 0.0);
    float width = line_width_px * (decorative ? 0.72 : 1.0);
    width *= mix(1.0, 1.7, edge_selected);
    // A one-pixel coverage skirt allows genuine subpixel widths. The skirt is
    // geometry only; the fragment coverage integrates the requested hairline.
    pixel_half_extent = width * 0.5 + 0.75;
    clip.xy += normal_pixels * (UV.y * 2.0 - 1.0) * pixel_half_extent * 2.0 / VIEWPORT_SIZE * clip.w;
    POSITION = clip;
    VERTEX = point;
    // Keep secondary layers from overwhelming the distant overview. Primary
    // exact edges are never culled by this artistic coverage rule.
    float projected_length = tangent_length * 0.5 / max(clip.w * clip.w, 0.0025);
    float density_gain = mix(0.20, 1.0, smoothstep(100.0, 800.0, projected_length));
    projected_coverage = mix(1.0, density_gain, adaptive_coverage);
    projected_coverage = mix(projected_coverage, max(projected_coverage, 0.75), edge_selected);
    if (decorative) {
        projected_coverage *= smoothstep(4.0, 70.0, projected_length);
    }
}

void fragment() {
    float width = line_width_px * (decorative ? 0.72 : 1.0) * mix(1.0, 1.7, edge_selected);
    float distance_px = abs(UV.y * 2.0 - 1.0) * pixel_half_extent;
    float aa = clamp(width * 0.5 + 0.5 - distance_px, 0.0, min(width, 1.0));
    vec3 colour = edge_weight >= 0.0 ? positive_colour.rgb : negative_colour.rgb;
    float brightness = 1.0;
    if (!scientific) {
        float travel = UV.x * phase_frequency - clock_filament * phase_speed * flow_direction * 0.16 + edge_seed;
        float band = pow(0.5 + 0.5 * cos(TAU * travel), 9.0);
        brightness = 0.48 + 1.1 * band;
        float palette_t = edge_seed + UV.x * 0.19 + palette_phase + clock_palette * 0.025;
        vec3 lut = 0.5 + 0.5 * cos(TAU * (palette_t + vec3(0.0, 0.32, 0.67)));
        colour = mix(colour, lut, palette_amount);
    }
    float selection = has_selection ? mix(selection_fade, 1.4, edge_selected) : 1.0;
    colour = mix(colour, vec3(0.78, 0.94, 1.0), edge_selected * 0.45);
    float weight_visibility = mix(0.62, 1.0, clamp(abs(edge_weight) * 3.0, 0.0, 1.0));
    ALBEDO = colour * intensity * brightness;
    ALPHA = clamp(aa * opacity * selection * weight_visibility * projected_coverage * coverage * (decorative ? 0.62 : 1.0), 0.0, 1.0);
}
