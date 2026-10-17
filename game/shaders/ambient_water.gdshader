// «Живой мир» — water surface: the river (mode 0) and puddles on the road (mode 1).
// Drawn on a Polygon2D = the water outline from data/story/ambient/<LOC>.json, right above the
// background: the painted water is redrawn through a slowly drifting ripple (reflections shimmer,
// stronger near the viewer), with thin glints running with the flow and — while it drizzles — rings
// of the drops. Rings live on the floor plane: cells of `ring_cell_m` metres in floor coordinates
// (depth line of the room + camera focal length, see ambient_ground.gd), so they are ellipses,
// smaller and flatter far away; rings thinner than a pixel fade out. Saturated pixels (posts, the
// boat, a rope, stones painted in the water) and `exclude` rects stay still.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D src_tex : filter_linear, repeat_disable;
uniform vec2 src_origin = vec2(0.0);
uniform vec2 src_size = vec2(1920.0, 1080.0);
uniform vec2 poly[32];
uniform int poly_n = 0;
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
uniform float protect_sat = 0.32;
uniform vec4 depth = vec4(640.0, 1070.0, 0.6, 1.1);       // top_y, bottom_y, scale_top, scale_bottom
uniform vec4 ground = vec4(300.0, 2059.0, 208.0, 0.0);    // horizon_y, focal_px, px_per_m
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

// Drop rings on the floor plane. Returns 0..1 (ring brightness).
float drop_rings(vec2 p, float t) {
	float s = line_scale(p.y);
	float ppm = s * ground.z;                       // screen px per metre across the view
	vec2 g = vec2((p.x - 960.0) / ppm, ground.y / ppm);  // metres: across, distance from the camera
	vec2 cell = floor(g / ring_cell_m);
	vec2 f = g - cell * ring_cell_m;
	float h = amb_hash12(cell);
	float per = ring_period * (0.7 + 0.6 * h);
	float tt = t / per + amb_hash12(cell + 7.31);
	float k = floor(tt);
	float ph = fract(tt);
	if (amb_hash12(cell + k * 0.137 + 3.1) > rain) {
		return 0.0;
	}
	float m = ring_m * 1.2;
	vec2 c = vec2(m) + vec2(amb_hash12(cell + k + 1.7), amb_hash12(cell + k + 9.2)) * (ring_cell_m - 2.0 * m);
	float r = ph * ring_m;
	float d = length(f - c);
	float w = 1.1 / ppm;                            // ~1 px line width in metres
	float ring = 1.0 - smoothstep(0.0, w, abs(d - r));
	float vis = smoothstep(0.8, 2.0, ring_m * ppm);  // sub-pixel rings far away fade out
	return ring * (1.0 - ph) * vis;
}

void fragment() {
	vec2 p = room_pos;
	float t = TIME;
	float edge = smoothstep(0.0, feather_px, amb_edge_dist(p));
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
	vec4 base = amb_src(p);
	vec4 moved = amb_src(p - d);
	float prot = smoothstep(protect_sat, protect_sat + 0.12, max(amb_sat(base.rgb), amb_sat(moved.rgb)));
	vec3 col = mix(moved.rgb, base.rgb, prot);
	float still = (1.0 - prot) * edge;
	// Glints: thin bright streaks drifting with the flow.
	if (glint > 0.0) {
		float gl = amb_noise2(vec2(p.x / (70.0 * s), p.y / (6.0 * s)) + fl * 1.4 * t + vec2(0.0, n1));
		gl = smoothstep(0.78, 0.97, gl);
		col += gl * glint * still * vec3(0.92, 0.95, 1.0) * (0.35 + 0.65 * dot(base.rgb, vec3(0.33)));
	}
	if (rain > 0.0) {
		float rr = drop_rings(p, t);
		col = mix(col, max(col * 1.25, vec3(0.75, 0.78, 0.82)), rr * 0.55 * still);
	}
	COLOR = vec4(col * COLOR.rgb, COLOR.a);
}
