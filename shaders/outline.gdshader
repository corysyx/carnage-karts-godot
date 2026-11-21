// Ink outline for models: an inflated back-face shell drawn in a dark colour.
// Pushes vertices away from the mesh centre so boxes don't crack at their corners.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 ink : source_color = vec4(0.16, 0.09, 0.19, 1.0);
uniform float width = 0.035;

void vertex() {
	vec3 dir = length(VERTEX) > 0.0001 ? normalize(VERTEX) : NORMAL;
	VERTEX += normalize(mix(NORMAL, dir, 0.5)) * width;
}

void fragment() {
	ALBEDO = ink.rgb;
}
