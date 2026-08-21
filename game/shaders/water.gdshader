shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Water / glass / ice. Water surface vertices (UV2.x = 1) ride slow waves;
// a fresnel term brightens grazing angles so ponds read glossy from the
// isometric camera and the sun leaves a real specular glint.

uniform float shine : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	if (UV2.x > 0.001) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		VERTEX.y += sin(TIME * 1.7 + wp.x * 0.6 + wp.z * 0.45) * 0.05
			+ cos(TIME * 1.1 + wp.z * 0.8 - wp.x * 0.3) * 0.04;
	}
}

void fragment() {
	// Vertex colors arrive sRGB; albedo must be linear.
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALPHA = clamp(COLOR.a + fres * 0.3 * shine, 0.0, 0.95);
	ROUGHNESS = mix(1.0, 0.07, shine);
	SPECULAR = 0.7 * shine;
	EMISSION = pow(COLOR.rgb, vec3(2.2)) * UV2.y;
}
