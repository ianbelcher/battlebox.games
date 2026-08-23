// EVERYTHING GOES GREY WHEN YOU ARE OUT.
//
// Being knocked out used to look like being hurt: a red wash, which is
// also what taking a hit looks like, so "you are out of this fight" and
// "mind yourself" read as the same thing. Colour draining out of the
// world is not something that happens for any other reason, so there is
// nothing to confuse it with.
//
// It reads the screen underneath rather than tinting over it, so the
// world genuinely loses its colour instead of being covered by a grey
// sheet — a wash over the top dulls the HUD too and still leaves green
// grass showing through.
//
// hint_screen_texture works under the Compatibility renderer, which is
// what the browser build uses; there is no Forward+-only path here.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
// 0 is untouched, 1 is fully grey. Eased in by PlayerHud so the colour
// drains rather than snapping out.
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 seen = texture(screen, SCREEN_UV).rgb;
	// Rec. 601 luma: the weights the eye actually uses, so a red team
	// shirt and a blue one do not come out as the same grey.
	float grey = dot(seen, vec3(0.299, 0.587, 0.114));
	// Slightly darker as well as grey. Fully desaturated alone still
	// looks like a bright, busy screen you might be able to act on.
	vec3 out_of_it = vec3(grey) * mix(1.0, 0.82, amount);
	COLOR = vec4(mix(seen, out_of_it, amount), 1.0);
}
