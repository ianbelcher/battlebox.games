shader_type spatial;
// Solid voxel surface. Vertex colors carry albedo * baked AO * shading.
// UV.x's integer part selects a procedural face pattern (0 = plain) so
// signature blocks — bookshelves, crafting tables, chests, furnaces,
// TNT, melons, pumpkins, hay, planks, bricks, logs — look like
// themselves in the world instead of flat colored cubes.
// UV2.x = wind sway strength, UV2.y = emissive energy.

float hashn(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = UV2.x;
	if (sway > 0.001) {
		float phase = wp.x * 0.35 + wp.z * 0.28;
		VERTEX.x += sin(TIME * 1.6 + phase) * 0.06 * sway;
		VERTEX.z += cos(TIME * 1.25 + phase * 1.2) * 0.05 * sway;
	}
}

void fragment() {
	vec3 albedo = pow(COLOR.rgb, vec3(2.2));
	int pattern = int(floor(UV.x));
	float u = fract(UV.x);
	float v = UV.y;
	float emit = UV2.y;

	if (pattern == 1) { // bookshelf: two rows of colored spines
		float row = step(0.18, v) * step(v, 0.46) + step(0.56, v) * step(v, 0.84);
		if (row > 0.5) {
			float slot = floor(u * 6.0);
			vec3 spines[4] = { vec3(0.45, 0.14, 0.1), vec3(0.12, 0.24, 0.5),
				vec3(0.14, 0.4, 0.16), vec3(0.55, 0.42, 0.1) };
			albedo = spines[int(mod(slot, 4.0))] * (0.8 + 0.2 * hashn(slot + v));
		}
	} else if (pattern == 2) { // crafting table: 3x3 grid lines
		vec2 g = fract(vec2(u, v) * 3.0);
		if (g.x < 0.09 || g.y < 0.09) { albedo *= 0.55; }
	} else if (pattern == 3) { // chest: lid seam + latch
		if (abs(v - 0.6) < 0.03) { albedo *= 0.5; }
		if (abs(u - 0.5) < 0.07 && v > 0.5 && v < 0.75) {
			albedo = vec3(0.32, 0.33, 0.36);
		}
	} else if (pattern == 4) { // furnace: dark mouth with fire
		if (u > 0.25 && u < 0.75 && v < 0.55 && v > 0.08) {
			albedo = vec3(0.03, 0.03, 0.04);
			if (v < 0.35) {
				float lick = 0.18 + 0.1 * sin(TIME * 6.0 + u * 20.0);
				if (v > lick) {} else {
					albedo = vec3(0.9, 0.4, 0.1);
					emit = max(emit, 0.8);
				}
			}
		}
	} else if (pattern == 5) { // tnt: white band on red
		if (v > 0.36 && v < 0.6) { albedo = vec3(0.9, 0.88, 0.82); }
	} else if (pattern == 6) { // melon: dark green stripes
		if (fract(u * 4.0) < 0.3) { albedo *= 0.55; }
	} else if (pattern == 7) { // pumpkin: vertical ribs
		if (fract(u * 3.0 + 0.5) < 0.12) { albedo *= 0.62; }
	} else if (pattern == 8) { // hay: horizontal bands
		if (fract(v * 3.0) < 0.16) { albedo *= 0.55; }
	} else if (pattern == 9) { // planks: grain
		if (fract(v * 4.0) < 0.09) { albedo *= 0.68; }
		if (fract(u * 2.0 + floor(v * 4.0) * 0.5) < 0.045) { albedo *= 0.75; }
	} else if (pattern == 10 || pattern == 11) { // bricks / stone bricks
		float rows = pattern == 10 ? 4.0 : 2.0;
		float row_i = floor(v * rows);
		float off = mod(row_i, 2.0) * 0.5;
		if (fract(v * rows) < 0.08) { albedo *= 0.66; }
		if (fract(u * 2.0 + off) < 0.045) { albedo *= 0.66; }
	} else if (pattern == 12) { // bark: vertical striations
		if (fract(u * 5.0 + hashn(floor(u * 5.0)) * 0.3) < 0.14) { albedo *= 0.7; }
	} else if (pattern == 13) { // log top: growth rings
		float r = length(vec2(u, v) - vec2(0.5));
		if (fract(r * 6.0) < 0.22) { albedo *= 0.72; }
	}

	ALBEDO = albedo;
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
	EMISSION = albedo * emit;
}
