shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://rendering/optical/spectral_field.gdshaderinc"

uniform float background_strength = 0.006;

void vertex() {
	// Reverse-Z far plane: 0 for Vulkan, -1 for the Compatibility renderer.
	POSITION = vec4(VERTEX.xy, CLIP_SPACE_FAR, 1.0);
}

void fragment() {
	vec4 view_ray = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec3 world_ray = normalize((INV_VIEW_MATRIX * vec4(view_ray.xyz / view_ray.w, 0.0)).xyz);
	ALBEDO = vec3(0.002, 0.004, 0.009) + spectral_environment(world_ray) * background_strength;
	// A dedicated earliest transparent-queue draw preserves source hairlines.
	// Far-plane depth testing still protects all opaque scene geometry.
	ALPHA = 1.0;
}
