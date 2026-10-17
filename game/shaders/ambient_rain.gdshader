// «Живой мир» — drizzle over the whole room (data/story/ambient: `rain`).
// Three depth layers of thin slanted streaks, procedural (no particles): far streaks are shorter,
// thinner, slower and fainter. The slant leans with the wind gusts. Each layer: cells of
// cell_w × (len + gap) px in a frame sheared by the slant; a cell holds one streak with probability
// `density × intensity`, at a random x and phase, its column offset at random (no grid visible).
// Drawn above everything in the room except the UI (z 4096); it never receives input.
shader_type canvas_item;
render_mode blend_mix;

uniform float intensity = 0.6;
uniform float slant = 0.2;          // tan of the angle from the vertical; + = falls to the right
uniform float gust_slant = 0.06;    // extra lean in a gust
uniform float gust_rate = 0.12;
uniform vec4 color : source_color = vec4(0.82, 0.86, 0.92, 1.0);
// Per layer (far, mid, near): x = streak length px, y = width px, z = speed px/s, w = alpha.
uniform vec4 layer0 = vec4(9.0, 0.9, 520.0, 0.16);
uniform vec4 layer1 = vec4(18.0, 1.1, 820.0, 0.22);
uniform vec4 layer2 = vec4(34.0, 1.5, 1250.0, 0.26);
// Per layer: x = cell width px, y = gap after a streak px, z = density 0..1.
uniform vec3 cells0 = vec3(9.0, 60.0, 0.55);
uniform vec3 cells1 = vec3(17.0, 110.0, 0.5);
uniform vec3 cells2 = vec3(37.0, 200.0, 0.45);

#include "res://shaders/ambient_common.gdshaderinc"

varying vec2 room_pos;
varying float slant_now;

void vertex() {
	room_pos = VERTEX;
	// The gust lean is the same for the whole frame: once per vertex, not per pixel.
	float g = amb_noise1(TIME * gust_rate + 3.0);
	slant_now = slant + gust_slant * (g - 0.5) * 2.0;
}

float streaks(vec2 p, float sl, vec4 L, vec3 C, float seed, float t) {
	float cell_h = L.x + C.y;
	// Shear: a slanted streak becomes vertical; falling = moving down that column.
	float x = p.x - p.y * sl;
	float col = floor(x / C.x);
	float y = p.y - t * L.z + amb_hash11(col * 1.37 + seed) * cell_h * 7.0;
	float row = floor(y / cell_h);
	float fy = y - row * cell_h;
	float v = fy / L.x;
	if (v < 0.0 || v > 1.0) {
		return 0.0;  // in the gap under the streak: most pixels stop here
	}
	vec2 id = vec2(col, row) + seed;
	if (amb_hash12(id) > C.z * intensity) {
		return 0.0;
	}
	float fx = x - col * C.x;
	float x0 = (0.2 + 0.6 * amb_hash12(id + 3.7)) * C.x;
	// Width across the streak (the shear widens horizontal distances by 1/cos).
	float dx = abs(fx - x0) * inversesqrt(1.0 + sl * sl);
	if (dx > L.y * 0.5 + 0.8) {
		return 0.0;
	}
	float a = (1.0 - smoothstep(L.y * 0.5, L.y * 0.5 + 0.8, dx)) * (0.25 + 0.75 * v);  // head brighter than the tail
	return a * L.w * (0.6 + 0.4 * amb_hash12(id + 9.1));
}

void fragment() {
	vec2 p = room_pos;
	float t = TIME;
	float sl = slant_now;
	float a = streaks(p, sl * 0.8, layer0, cells0, 11.0, t);
	a = max(a, streaks(p, sl * 0.9, layer1, cells1, 23.0, t));
	a = max(a, streaks(p, sl, layer2, cells2, 37.0, t));
	COLOR = vec4(color.rgb, clamp(a, 0.0, 1.0) * color.a);
}
