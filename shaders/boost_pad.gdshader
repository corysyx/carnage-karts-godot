// Dash panel: bright chevrons scrolling forward. UV.x runs across the pad,
// UV.y along it in the driving direction.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 col_a : source_color = vec4(1.0, 0.48, 0.1, 1.0);
uniform vec4 col_b : source_color = vec4(1.0, 0.86, 0.25, 1.0);
uniform vec4 rim : source_color = vec4(0.16, 0.09, 0.19, 1.0);
uniform float chevrons = 3.0;

void fragment() {
	vec2 uv = UV;
	float f = fract(uv.y * chevrons - abs(uv.x - 0.5) * 1.4 - TIME * 1.6);
	vec3 c = mix(col_a.rgb, col_b.rgb, step(0.5, f));
	// glow towards the centre line
	c += vec3(0.25, 0.18, 0.05) * (1.0 - abs(uv.x - 0.5) * 2.0) * (0.6 + 0.4 * sin(TIME * 9.0));
	float edge = min(min(uv.x, 1.0 - uv.x) * 5.0, min(uv.y, 1.0 - uv.y) * 6.0);
	if (edge < 0.12) {
		c = rim.rgb;
	} else if (edge < 0.3) {
		c = vec3(1.0, 0.97, 0.9);
	}
	ALBEDO = c;
}
