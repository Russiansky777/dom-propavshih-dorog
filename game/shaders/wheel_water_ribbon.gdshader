shader_type canvas_item;
// A falling stream of water (AmbientWheel ribbons, J 30.10 — Director 14:30: «улучшить воду до реалистичной»).
// The strip is drawn as quads: UV.x — a coordinate fixed to the water itself (the parcel's age × speed, so the
// texture travels down with the water), UV.y — 0..1 across the stream (1 — its left edge for water falling down). Water is clear: what is behind it shows
// through, bent a little by the uneven surface (refraction from the screen), lifted and cooled; the edges carry more
// water along the line of sight and read brighter; the sky catches a thin highlight on the upper-left edge; flowing
// striations run down the stream; it whitens with air as it falls (vertex r). Vertex alpha fades the stream in at the lip and out where it breaks into drops.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec3 tint : source_color = vec3(0.86, 0.92, 0.96);
uniform float refract_px = 3.0;
uniform float body_mix = 0.2;
uniform float highlight = 0.42;
uniform float aeration = 0.8;
uniform float aer_lip = 0.25;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float across = UV.y * 2.0 - 1.0;
	float ax = abs(across);
	float u = UV.x;
	// striations: long along the flow, narrow across it (slow along u, quick across)
	float s1 = vnoise(vec2(u * 1.3, UV.y * 5.0 + 3.1));
	float s2 = vnoise(vec2(u * 2.9 + 11.0, UV.y * 11.0));
	float streak = s1 * 0.6 + s2 * 0.4;
	// a cylinder-ish surface: the normal tilts toward the edges — bend the background more there
	float bend = across * (0.6 + 0.8 * streak);
	vec2 off = vec2(bend, (s2 - 0.5) * 0.6) * refract_px * SCREEN_PIXEL_SIZE;
	vec3 bg = texture(screen_tex, SCREEN_UV + off).rgb;
	float rim = smoothstep(0.35, 0.95, ax);
	float foamy = smoothstep(0.62, 0.86, streak);
	vec3 col = mix(bg * 1.06, tint, body_mix + 0.3 * rim + 0.35 * foamy);
	// aeration (vertex r: 0 at the lip → 1 where it tears into drops): falling water takes in air and whitens,
	// first in the striations, then across
	float aer = aer_lip + (1.0 - aer_lip) * COLOR.r;
	col = mix(col, vec3(0.95, 0.97, 0.98), clamp(aer * (0.35 + 0.65 * streak) * aeration, 0.0, 0.9));
	// the sky on the upper-left edge
	float hl = smoothstep(0.45, 0.92, across) * (0.55 + 0.45 * s2);
	col += hl * highlight;
	// a thin darker line on the far edge (the stream's shadow side)
	col *= 1.0 - 0.18 * smoothstep(0.7, 0.98, -across);
	float edge = 1.0 - smoothstep(0.78, 1.0, ax);
	COLOR = vec4(col, COLOR.a * edge);
}
