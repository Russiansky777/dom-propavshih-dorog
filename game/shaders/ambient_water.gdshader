// «Живой мир» — water surface: the river (mode 0) and puddles on the road (mode 1).
// Drawn on a Polygon2D = the water outline from data/story/ambient/<LOC>.json, right above the
// background: the painted water is redrawn through a slowly drifting ripple (reflections shimmer,
// stronger near the viewer), with thin glints running with the flow and — while it drizzles — rings
// of the drops. Rings live on the floor plane: cells of `ring_cell_m` metres in floor coordinates
// (depth line of the room + camera focal length, see ambient_ground.gd), so they are ellipses,
// smaller and flatter far away; rings thinner than a pixel fade out. Saturated pixels (posts, the
// boat, a rope, stones painted in the water) and `exclude` rects stay still.
// Director 23.10 (F14: «вода у нас всё ещё мёртвая»), all cheap and from data (ambient water entries / water_style):
//   tremble_px — reflections tremble: thin horizontal bands slide sideways and back (posts, trees, lights on
//                the water waver), stronger near the viewer;
//   sparkle    — twinkling points of light on the bright parts of the water (sky, lanterns), drifting with it;
//   streaks    — flow lines and foam running with `flow` (the mill race, the flume at the sluice, a current).
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D src_tex : filter_linear, repeat_disable;
uniform vec2 src_origin = vec2(0.0);
uniform vec2 src_size = vec2(1920.0, 1080.0);
uniform bool src_alpha = false;             // the source is a room layer (water cut-out), keep its alpha
uniform int edge_mode = 0;
uniform vec4 edge_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D edge_tex : filter_linear, repeat_disable;
uniform float feather_px = 16.0;
uniform int mode = 0;
uniform vec2 flow = vec2(-12.0, 0.0);       // px/s of the ripple pattern at depth scale 1
uniform vec2 ripple_px = vec2(0.5, 2.0);    // shimmer amplitude at the far / near edge of the region
uniform vec2 y_range = vec2(400.0, 700.0);  // far / near edge (bbox of the outline)
uniform float glint = 0.25;
uniform float rain = 0.0;                   // 0..1, drop rings
uniform float ring_cell_m = 0.45;
uniform float ring_m = 0.07;
uniform float ring_period = 1.1;
uniform float ring_gain = 1.0;              // contrast of a ring: brightening and bend of the reflection (F21)
uniform float ring_w_px = 1.4;              // crest width, screen px (F21)
uniform float protect_sat = 0.32;
uniform vec4 depth = vec4(640.0, 1070.0, 0.6, 1.1);       // top_y, bottom_y, scale_top, scale_bottom
uniform vec4 ground = vec4(300.0, 2059.0, 208.0, 0.0);    // horizon_y, focal_px, px_per_m
uniform float tremble_px = 0.0;
uniform float sparkle = 0.0;
uniform float streaks = 0.0;
uniform vec4 streak_color : source_color = vec4(0.9, 0.93, 0.95, 1.0);
uniform vec4 exclude[4];
uniform int exclude_n = 0;

#define AMB_REGION
#include "res://shaders/ambient_common.gdshaderinc"

varying vec2 room_pos;

void vertex() {
	room_pos = VERTEX;
}

float line_scale(float y) {
	float slope = (depth.w - depth.z) / max(depth.y - depth.x, 0.001);
	return max(depth.z + (y - depth.x) * slope, 0.02);
}

// Drop rings on the floor plane. x: signed ring profile (+ just inside the crest, − just outside:
// a ring reads on bright sky reflections and on dark mud water alike); yz: screen direction away
// from the drop (for the refraction of the reflection across the ring).
vec3 drop_rings(vec2 p, float t) {
	float s = line_scale(p.y);
	float ppm = s * ground.z;                            // screen px per metre across the view
	vec2 g = vec2((p.x - 960.0) / ppm, ground.y / ppm);  // metres: across, distance from the camera
	vec2 cell = floor(g / ring_cell_m);
	vec2 f = g - cell * ring_cell_m;
	float h = amb_hash12(cell);
	float per = ring_period * (0.7 + 0.6 * h);
	float tt = t / per + amb_hash12(cell + 7.31);
	float k = floor(tt);
	float ph = fract(tt);
	if (amb_hash12(cell + k * 0.137 + 3.1) > rain) {
		return vec3(0.0);
	}
	float m = ring_m * 1.2;
	vec2 c = vec2(m) + vec2(amb_hash12(cell + k + 1.7), amb_hash12(cell + k + 9.2)) * (ring_cell_m - 2.0 * m);
	float r = (0.15 + 0.85 * sqrt(ph)) * ring_m;         // fast at first, then slowing down
	vec2 dv = f - c;
	float d = length(dv);
	float w = ring_w_px / ppm;                           // crest width in metres
	float sd = (r - d) / w;
	float prof = sd * exp(-sd * sd * 0.5) * 1.2;
	float vis = smoothstep(0.8, 2.5, ring_m * ppm);      // sub-pixel rings far away fade out
	float sq = clamp((p.y - ground.x) / ground.y, 0.03, 1.0);
	vec2 dir = normalize(vec2(dv.x, -dv.y * sq) + vec2(0.0001, 0.0));
	return vec3(clamp(prof, -1.0, 1.0) * (1.0 - ph) * vis, dir);
}

void fragment() {
	vec2 p = room_pos;
	float t = TIME;
	float edge = amb_edge(p);
	for (int i = 0; i < 4; i++) {
		if (i >= exclude_n) {
			break;
		}
		vec4 r = exclude[i];
		vec2 q = max(r.xy - p, p - (r.xy + r.zw));
		float outside = length(max(q, vec2(0.0)));
		edge *= smoothstep(0.0, 6.0, outside);
	}
	float s = line_scale(p.y);
	float ty = clamp((p.y - y_range.x) / max(y_range.y - y_range.x, 1.0), 0.0, 1.0);
	float amp = mix(ripple_px.x, ripple_px.y, ty);
	// Ripple field in perspective: wavelengths shrink with distance, waves lie across the view.
	vec2 q = vec2(p.x / (46.0 * s), p.y / (11.0 * s));
	vec2 fl = flow / vec2(46.0, 11.0);
	float n1 = amb_noise2(q + fl * t);
	float n2 = amb_noise2(q * 1.7 + vec2(3.1, 7.7) - fl * 0.6 * t);
	vec2 d = vec2((n1 - 0.5) * 0.6, (n2 - 0.5) * 2.0) * amp * edge;
	if (tremble_px > 0.0) {
		float band = p.y / (2.6 * s);
		float w = sin(band * 1.9 + t * 2.1 + n1 * 5.0) * 0.6 + sin(band * 0.61 - t * 1.3 + n2 * 4.0) * 0.4;
		d.x += w * tremble_px * mix(0.4, 1.0, ty) * edge;
	}
	vec3 rr = rain > 0.0 ? drop_rings(p, t) : vec3(0.0);
	d += rr.yz * rr.x * 1.2 * ring_gain * edge;         // a ring bends the reflection across it
	vec4 base = amb_src(p);
	vec4 moved = amb_src(p - d);
	if (src_alpha && moved.a < 0.5) {
		moved = base;                                   // never pull the transparent outside in
	}
	float prot = smoothstep(protect_sat, protect_sat + 0.12, max(amb_sat(base.rgb), amb_sat(moved.rgb)));
	vec3 col = mix(moved.rgb, base.rgb, prot);
	float still = (1.0 - prot) * edge;
	// Glints: thin bright streaks drifting with the flow.
	if (glint > 0.0) {
		float gl = amb_noise2(vec2(p.x / (70.0 * s), p.y / (6.0 * s)) + fl * 1.4 * t + vec2(0.0, n1));
		gl = smoothstep(0.78, 0.97, gl);
		col += gl * glint * still * vec3(0.92, 0.95, 1.0) * (0.35 + 0.65 * dot(base.rgb, vec3(0.33)));
	}
	col += vec3(0.95, 0.97, 1.0) * (rr.x * 0.17 * ring_gain * still);
	// Sparkles: a few cells light up and fade, on the bright reflections only.
	if (sparkle > 0.0) {
		vec2 cs = vec2(10.0 * s, 4.0 * s);
		vec2 cp = p / cs + fl * t * 0.8;
		vec2 cell = floor(cp);
		float hh = amb_hash12(cell);
		float tw = sin(t * (2.0 + hh * 4.0) + hh * 37.0);
		vec2 fc = fract(cp) - 0.5;
		float dot_ = smoothstep(0.5, 0.0, length(fc * vec2(1.0, 2.2)));
		float lum = dot(base.rgb, vec3(0.33));
		float on = step(0.86, hh) * smoothstep(0.55, 1.0, tw) * dot_;
		col += on * sparkle * still * smoothstep(0.18, 0.6, lum) * vec3(1.0, 0.97, 0.9);
	}
	// Flow lines: long streaks along `flow`, carried with it.
	if (streaks > 0.0) {
		float sp = length(flow);
		vec2 dir = sp > 0.01 ? flow / sp : vec2(1.0, 0.0);
		vec2 nrm = vec2(-dir.y, dir.x);
		float u = dot(p, dir) / (90.0 * s) - t * sp / (90.0 * s);
		float v = dot(p, nrm) / (6.0 * s);
		float st = amb_noise2(vec2(u, v)) * amb_noise2(vec2(u * 0.37 + 5.0, v * 0.5 - 2.0));
		st = smoothstep(0.3, 0.62, st);
		col = mix(col, streak_color.rgb, st * streaks * 0.5 * still);
	}
	COLOR = vec4(col * COLOR.rgb, src_alpha ? base.a * COLOR.a : COLOR.a);
}
