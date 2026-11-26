shader_type spatial;
render_mode unshaded, shadows_disabled;

// A tiny, closed sphere is the only node marker. There are no node stubs,
// bristles, tangent arrows or per-node procedural extensions.
uniform vec4 positive_colour : source_color = vec4(0.10, 0.67, 0.79, 1.0);
uniform vec4 negative_colour : source_color = vec4(0.82, 0.25, 0.20, 1.0);
uniform float node_radius = 0.018;
uniform bool has_selection = false;
uniform float selection_fade = 0.28;
varying float node_value;
varying float node_selected;

void vertex() {
    node_value = INSTANCE_CUSTOM.r;
    node_selected = INSTANCE_CUSTOM.g;
    VERTEX *= node_radius * mix(1.0, 1.6, node_selected);
}

void fragment() {
    vec3 c = node_value >= 0.0 ? positive_colour.rgb : negative_colour.rgb;
    c = mix(c, vec3(0.86, 0.98, 1.0), node_selected);
    // Quiet diffuse-like falloff keeps markers legible without emissive balls.
    float facing = 0.35 + 0.65 * max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
    ALBEDO = c * facing * (has_selection ? mix(selection_fade, 1.0, node_selected) : 1.0);
}
