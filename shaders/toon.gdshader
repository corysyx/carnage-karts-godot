// Cel shading: lighting snaps into shadow / base / highlight bands.
// Vertex colours are multiplied by `albedo`. Optional flat (faceted) normals for the low-poly look.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(1.0);
uniform bool flat_shading = false;
uniform float shadow_band : hint_range(0.0, 1.0) = 0.62;
uniform float highlight : hint_range(0.0, 0.5) = 0.12;
uniform vec4 shadow_tint : source_color = vec4(0.55, 0.5, 0.78, 1.0);
// Faces seen nearly edge-on are inked, which draws silhouette lines on hills.
uniform float rim_ink : hint_range(0.0, 0.6) = 0.0;
uniform vec4 ink : source_color = vec4(0.16, 0.09, 0.19, 1.0);

void fragment() {
	ALBEDO = albedo.rgb * COLOR.rgb;
	if (flat_shading) {
		NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	}
	if (rim_ink > 0.0 && abs(dot(normalize(NORMAL), VIEW)) < rim_ink) {
		ALBEDO = ink.rgb;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * ATTENUATION;
	float band = ndl > 0.55 ? 1.0 + highlight : (ndl > 0.05 ? 1.0 : 0.0);
	vec3 lit = mix(ALBEDO * shadow_tint.rgb * shadow_band, ALBEDO * band, step(0.5, band));
	DIFFUSE_LIGHT += lit * LIGHT_COLOR / PI;
}
