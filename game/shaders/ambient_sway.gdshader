// «Живой мир» — wind sway of a region of the picture (trees, bushes, grass, washing).
// Drawn on a Polygon2D = the region outline (data/story/ambient/<LOC>.json `sway_regions`), right
// above the background: it redraws the picture under the region warped by the wind. The warp is
// zero at the anchor (the root line: trunk base, grass roots) and grows to `amp_px` at `top_y`;
// it fades to zero towards the outline over `feather_px`, so the warped pixels join the still
// picture without a seam. kind 0 (tree/bush): swaying + slow gusts + leaf flutter; kind 1 (grass):
// gust waves travelling across the field with the wind. `keep_below_sat` keeps a fence or a wall
// behind a bush still. `src_alpha` = a separate layer picture
// (only the swaying thing, transparent elsewhere) instead of the background.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D src_tex : filter_linear, repeat_disable;
uniform vec2 src_origin = vec2(0.0);
uniform vec2 src_size = vec2(1920.0, 1080.0);
uniform bool src_alpha = false;
uniform int edge_mode = 0;
uniform vec4 edge_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D edge_tex : filter_linear, repeat_disable;
uniform float feather_px = 24.0;
uniform vec4 clip_rect = vec4(-100000.0, -100000.0, 200000.0, 200000.0);
uniform int kind = 0;
uniform float anchor_y = 1080.0;
uniform float top_y = 0.0;
uniform float anchor_slope = 0.0;   // a slanted root line (a shore, a verge): y shifts by slope·(x − anchor_x0)
uniform float anchor_x0 = 0.0;
uniform float amp_px = 4.0;
uniform float freq_hz = 0.4;
uniform float phase = 0.0;
uniform float wind_dir = 1.0;
uniform float gust_rate = 0.12;
uniform float gust_depth = 0.6;
uniform float flutter = 0.3;
uniform float wave_px = 320.0;
// Pixels less saturated than this stay where they are painted (a fence or a wall behind a bush):
// a pixel is redrawn moved only when both it and its source are foliage. 0 = off (trees on the sky).
uniform float keep_below_sat = 0.0;

#define AMB_REGION
#include "res://shaders/ambient_common.gdshaderinc"

varying vec2 room_pos;

void vertex() {
	room_pos = VERTEX;
}

void fragment() {
	vec2 p = room_pos;
	float t = TIME;
	float edge = amb_edge(p);
	float w = 1.0;
	if (kind != 1) {
		float shift = anchor_slope * (p.x - anchor_x0);
		w = clamp((anchor_y + shift - p.y) / max(anchor_y - top_y, 1.0), 0.0, 1.0);
		w = w * sqrt(w);  // a trunk bends more and more towards the crown
	}
	if (amp_px * edge * w < 0.04) {
		// Near the roots or the outline nothing moves visibly: the picture as painted, no noise.
		vec4 c0 = amb_src(p);
		COLOR = src_alpha ? c0 * COLOR : vec4(c0.rgb * COLOR.rgb, COLOR.a);
	} else {
		// Gusts: slow smooth noise, its own phase per region (neighbours never move in step).
		float g = amb_noise1(t * gust_rate + phase * 17.0);
		float wind = mix(1.0 - gust_depth, 1.0, g);
		vec2 d = vec2(0.0);
		if (kind == 1) {
			// Grass: a gust wave runs across the field downwind; blades lean with it.
			float wave = 0.5 + 0.5 * sin((p.x * wind_dir / wave_px - t * freq_hz) * 6.2831853 + phase * 6.2831853);
			float n = amb_noise2(vec2(p.x * 0.015 - t * 0.5 * wind_dir, p.y * 0.04));
			d.x = amp_px * wind * wave * (0.4 + 0.9 * n) * wind_dir;
			d.y = amp_px * 0.15 * (n - 0.5);
		} else {
			float s = sin(6.2831853 * (freq_hz * t + phase)) * 0.7
				+ sin(6.2831853 * (freq_hz * 2.13 * t + phase * 1.7)) * 0.3;
			d.x = amp_px * w * (wind * s + 0.45 * (wind - 0.6) * wind_dir);
			vec2 fl = vec2(amb_noise2(p * 0.06 + vec2(t * 1.7, 0.0)), amb_noise2(p * 0.06 + vec2(5.3, -t * 1.3))) - 0.5;
			d += fl * (amp_px * flutter * w * wind * 2.0);
		}
		d *= edge;
		// Window panes: the moved sample never comes from the frame round the glass (but a pixel on the
		// glass edge itself is never pulled inwards either).
		vec2 lo = clip_rect.xy;
		vec2 hi = clip_rect.xy + clip_rect.zw;
		vec2 sp = clamp(p - d, min(p, lo), max(p, hi));
		vec4 c = amb_src(sp);
		if (keep_below_sat > 0.0) {
			vec4 b = amb_src(p);
			float keep = 1.0 - smoothstep(keep_below_sat - 0.1, keep_below_sat, min(amb_sat(b.rgb), amb_sat(c.rgb)));
			c = mix(c, b, keep);
		}
		COLOR = src_alpha ? c * COLOR : vec4(c.rgb * COLOR.rgb, COLOR.a);
	}
}
