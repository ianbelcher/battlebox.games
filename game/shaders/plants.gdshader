shader_type spatial;
render_mode cull_disabled;
// Shaped flora. Each quad's UV.x carries a silhouette id in its integer
// part (see Mesher._plant_shape); the fragment stage cuts the flat quad
// into grass blades, petals, mushrooms, flames... so ground cover stops
// looking like two crossed sheets of paper. UV2.x = sway, UV2.y = emit.

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = UV2.x;
	if (sway > 0.001) {
		float phase = wp.x * 0.7 + wp.z * 0.6;
		VERTEX.x += sin(TIME * 2.1 + phase) * 0.09 * sway;
		VERTEX.z += cos(TIME * 1.7 + phase * 1.3) * 0.07 * sway;
	}
}

void fragment() {
	int shape = int(floor(UV.x));
	float u = fract(UV.x);
	float up = 1.0 - UV.y; // 0 at the roots, 1 at the top
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	vec3 albedo = base;
	float mask = 1.0;
	float glow = UV2.y;

	if (shape == 0) { // grass tuft: five leaning tapered blades
		mask = 0.0;
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			float root = 0.12 + 0.19 * fi;
			float lean = (root - 0.5) * 0.8 * up * up;
			float xx = u - root - lean;
			float wdt = mix(0.05, 0.008, up);
			float tall = 0.5 + 0.5 * hash1(fi + 7.0);
			if (up < tall && abs(xx) < wdt) { mask = 1.0; }
		}
	} else if (shape == 1) { // flower: green stem, petal head
		mask = 0.0;
		if (up < 0.62 && abs(u - 0.5) < 0.028) {
			mask = 1.0;
			albedo = pow(vec3(0.29, 0.48, 0.19), vec3(2.2));
		}
		vec2 head = vec2((u - 0.5) / 0.24, (up - 0.74) / 0.22);
		float hd = length(head);
		if (hd < 1.0) {
			mask = 1.0;
			// scalloped petal edge + warm center
			float petals = 0.82 + 0.18 * cos(atan(head.y, head.x) * 5.0);
			if (hd > petals) { mask = 0.0; }
			else if (hd < 0.3) { albedo = pow(vec3(1.0, 0.85, 0.35), vec3(2.2)); }
		}
	} else if (shape == 2) { // mushroom: cream stem, colored cap
		mask = 0.0;
		if (up < 0.5 && abs(u - 0.5) < 0.09) {
			mask = 1.0;
			albedo = pow(vec3(0.9, 0.85, 0.72), vec3(2.2));
		}
		vec2 cap = vec2((u - 0.5) / 0.33, (up - 0.48) / 0.34);
		if (cap.y > 0.0 && length(cap) < 1.0) { mask = 1.0; }
	} else if (shape == 3) { // fire: licking animated flame
		vec2 f = vec2(u - 0.5, up);
		// Phase DECREASES with height so the licks travel upward the way
		// real flames do.
		f.x += sin(TIME * 7.0 - up * 9.0 + hash1(floor(UV.x)) * 6.28) * 0.09 * up;
		float body = 1.0 - smoothstep(0.0, mix(0.42, 0.02, f.y), abs(f.x));
		mask = (f.y < 1.0 && body > 0.5) ? 1.0 : 0.0;
		float core = 1.0 - smoothstep(0.0, mix(0.2, 0.01, f.y), abs(f.x));
		albedo = mix(pow(vec3(0.95, 0.35, 0.08), vec3(2.2)),
			pow(vec3(1.0, 0.85, 0.3), vec3(2.2)), core);
		glow = max(glow, 1.6);
	} else if (shape == 4) { // leafy bush: clumped lobes on a stub trunk
		mask = 0.0;
		if (up < 0.3 && abs(u - 0.5) < 0.045) {
			mask = 1.0;
			albedo = pow(vec3(0.42, 0.3, 0.18), vec3(2.2));
		}
		vec2 lobes[3] = { vec2(0.32, 0.42), vec2(0.62, 0.52), vec2(0.52, 0.28) };
		for (int i = 0; i < 3; i++) {
			vec2 d = vec2(u, up) - lobes[i];
			float r = 0.24 + 0.05 * sin(atan(d.y, d.x) * 7.0 + float(i));
			if (length(d) < r) { mask = 1.0; }
		}
	} else if (shape == 5) { // vine sheet: leafy holes + ragged bottom
		float n = hash1(floor(u * 6.0) * 7.7 + floor(up * 6.0) * 3.1 + floor(UV.x));
		mask = (n > 0.3) ? 1.0 : 0.0;
		if (up < 0.15 && hash1(floor(u * 6.0) * 5.3) > 0.5) { mask = 0.0; }
	} else if (shape == 6) { // grain: stalks with seed heads
		mask = 0.0;
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			float root = 0.16 + 0.22 * fi;
			float tall = 0.6 + 0.4 * hash1(fi + 3.0);
			if (up < tall && abs(u - root) < 0.018) { mask = 1.0; }
			vec2 d = vec2(u - root, (up - tall) / 1.8);
			if (up > tall * 0.8 && length(d) < 0.05) { mask = 1.0; }
		}
	} else if (shape == 7) { // stick / stalk (torch, bamboo)
		mask = (abs(u - 0.5) < 0.06) ? 1.0 : 0.0;
		if (up > 0.78 && abs(u - 0.5) < 0.12) { mask = 1.0; }
	} else if (shape == 9) { // ladder: two rails + rungs
		mask = 0.0;
		if (abs(u - 0.24) < 0.055 || abs(u - 0.76) < 0.055) { mask = 1.0; }
		if (u > 0.18 && u < 0.82 && abs(fract(up * 4.0 + 0.5) - 0.5) < 0.13) { mask = 1.0; }
	}

	if (mask < 0.5) { discard; }
	ALBEDO = albedo;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	EMISSION = albedo * glow;
}
