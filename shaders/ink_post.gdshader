// Screen-space ink lines: dark outlines where the depth buffer jumps
// (hill silhouettes, trees, fences, karts). Lines fade out with distance.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 ink : source_color = vec4(0.16, 0.09, 0.19, 1.0);
uniform float strength = 0.85;
uniform float far_fade = 70.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float lin(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 ndc = vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	vec4 v = inv_proj * ndc;
	return -v.z / v.w;
}

void fragment() {
	vec2 e = 1.0 / VIEWPORT_SIZE;
	float c = lin(SCREEN_UV, INV_PROJECTION_MATRIX);
	float n = lin(SCREEN_UV + vec2(0.0, e.y), INV_PROJECTION_MATRIX);
	float s = lin(SCREEN_UV - vec2(0.0, e.y), INV_PROJECTION_MATRIX);
	float w = lin(SCREEN_UV - vec2(e.x, 0.0), INV_PROJECTION_MATRIX);
	float r = lin(SCREEN_UV + vec2(e.x, 0.0), INV_PROJECTION_MATRIX);
	float mx = max(max(n, s), max(w, r));
	float edge = step(c * 0.06 + 0.25, mx - c);
	float fade = clamp(1.0 - c / far_fade, 0.0, 1.0);
	ALBEDO = ink.rgb;
	ALPHA = edge * fade * strength;
}
