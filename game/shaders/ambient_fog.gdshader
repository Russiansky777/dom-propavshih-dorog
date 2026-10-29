// «Живой мир» — туман над рекой (партия J, решение Директора Р2 29.10: «тот берег — серый силуэт до узла на кольце,
// потом туман сходит»). Drawn on a Polygon2D = the fog region (data/story/ambient/<LOC>.json `fog`), over the far
// bank and the far water, under the figures. Not a redraw of the picture: a veil of `color` mixed over it.
//   vertical profile `profile` [top, core_top, core_bottom, bottom] (room px): 0 above top → full in the core
//     (the far shore line, where river fog lies thickest) → 0 at the bottom (the water nearer to us);
//   banks: two layers of 4-octave value noise, stretched ×2.4 along the river and drifting with `drift` px/s at
//     different speeds (parallax), so the fog moves in slow banks; `wisps` 0..1 — how much the banks thin it;
//   the region outline feathers it (`feather_px`, as the other ambient regions);
//   `lift` 0..1 — the fog going (AmbientRoot eases it when the entry's flags turn it off): it rises by `lift_px`
//     and thins out to nothing.
// Numbers tuned on the painted rooms by a numpy replica (Docs/PLAN_J.md, E — fog), same noise as ambient_common.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D src_tex : filter_linear, repeat_disable;   // unused (amb_src of the region include)
uniform vec2 src_origin = vec2(0.0);
uniform vec2 src_size = vec2(1920.0, 1080.0);
uniform int edge_mode = 0;
uniform vec4 edge_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D edge_tex : filter_linear, repeat_disable;
uniform float feather_px = 60.0;

uniform vec4 color : source_color = vec4(0.663, 0.686, 0.737, 1.0);
uniform float density = 0.7;
uniform float wisps = 0.5;
uniform vec4 profile = vec4(240.0, 330.0, 420.0, 460.0);
uniform vec2 drift = vec2(8.0, 0.0);
uniform float scale_px = 200.0;
uniform float lift = 0.0;
uniform float lift_px = 60.0;

#define AMB_REGION
#include "res://shaders/ambient_common.gdshaderinc"

varying vec2 room_pos;

void vertex() {
	room_pos = VERTEX;
}

float fog_fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * amb_noise2(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s / 0.9375;
}

void fragment() {
	vec2 p = room_pos;
	float up = lift * lift_px;
	float v = smoothstep(profile.x - up, profile.y - up, p.y) * (1.0 - smoothstep(profile.z - up, profile.w - up, p.y));
	float edge = amb_edge(p);
	float k = v * edge * (1.0 - lift);
	if (k * density < 0.004) {
		COLOR = vec4(color.rgb, 0.0);
	} else {
		vec2 sc = vec2(scale_px * 2.4, scale_px);
		float t = TIME;
		float a = fog_fbm(p / sc - drift * t / sc);
		float b = fog_fbm(p / sc * 1.7 + vec2(5.3, 1.1) - drift * 1.6 * t / sc);
		float banks = smoothstep(0.28, 0.78, a * 0.6 + b * 0.4);
		float alpha = density * k * (1.0 - wisps + wisps * banks);
		COLOR = vec4(color.rgb * (0.95 + 0.08 * banks), alpha * color.a);
	}
}
