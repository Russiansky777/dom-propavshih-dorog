shader_type canvas_item;
render_mode unshaded, blend_add;

// Visible beam of daylight (data type "shaft" in data/story/lights/<LOC>.json): the soft polygon mask
// (TEXTURE alpha, built by LightMask with a gradient bright at the glass) × streaks along the beam
// direction — slow-drifting bands of brighter and dimmer air, so the beam reads as a beam and not as
// a haze. Additive and unshaded; `intensity` = alpha × fade × flicker (GDScript).

uniform float intensity = 0.2;
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec2 rect_px = vec2(1000.0, 1000.0);   // size of the mask texture on screen
uniform vec2 dir = vec2(-0.48, 0.88);          // beam direction (screen, normalised in GDScript)
uniform float streak_amount : hint_range(0.0, 1.0) = 0.45;
uniform float streak_px = 38.0;                // width of a band across the beam
uniform float drift = 0.05;                    // band drift speed (bands per second)

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), u);
}

void fragment() {
	float m = texture(TEXTURE, UV).a;
	vec2 px = UV * rect_px;
	vec2 perp = vec2(-dir.y, dir.x);
	float across = dot(px, perp) / streak_px;
	float along = dot(px, dir) / (streak_px * 9.0);
	float s = noise1(across + TIME * drift) * 0.65 + noise1(across * 2.3 - TIME * drift * 0.7 + 17.0) * 0.35;
	s = mix(1.0, 0.45 + 1.1 * s, streak_amount) * (0.9 + 0.1 * noise1(along + TIME * 0.11));
	COLOR = vec4(color.rgb * m * s * intensity, 1.0);
}
