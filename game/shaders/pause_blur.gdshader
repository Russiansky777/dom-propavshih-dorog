shader_type canvas_item;
// Pause backdrop: the game frame behind the menu, slightly blurred and dimmed. One pass over the screen texture,
// 15 taps (centre + a ring of 6 + a ring of 8) — light enough for the web build. `amount` fades it in and out.
// radius_px is in canvas pixels (1920×1080), so the blur looks the same at any window size.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float radius_px = 3.2;
uniform float dim : hint_range(0.0, 1.0) = 0.62;
uniform float desaturate : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec2 r = vec2(SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, 1.0) * (radius_px / 1080.0) * amount;
	vec3 acc = texture(screen_tex, SCREEN_UV).rgb * 0.16;
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472 + 0.3;
		acc += texture(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r).rgb * 0.08;
	}
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7854;
		acc += texture(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r * 2.1).rgb * 0.045;
	}
	float g = dot(acc, vec3(0.299, 0.587, 0.114));
	vec3 c = mix(acc, vec3(g), desaturate * amount);
	c *= mix(1.0, dim, amount);
	COLOR = vec4(c, 1.0);
}
