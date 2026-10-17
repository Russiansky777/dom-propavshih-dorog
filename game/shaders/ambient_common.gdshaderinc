// «Живой мир» — shared helpers of the ambient shaders (ambient_sway / ambient_water).
// A region shader (#define AMB_REGION before the #include) declares first:
//   uniform sampler2D src_tex; uniform vec2 src_origin; uniform vec2 src_size;
//                                                — the picture under the region and where it is drawn
//   uniform int edge_mode; uniform vec4 edge_rect; uniform sampler2D edge_tex; uniform float feather_px;
//                                                — the feathered edge (see amb_edge)
// Hashes without sin() (stable in WebGL2 at large coordinates).

float amb_hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float amb_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth 1D value noise in 0..1 (gusts).
float amb_noise1(float t) {
	float i = floor(t);
	float f = fract(t);
	f = f * f * (3.0 - 2.0 * f);
	return mix(amb_hash11(i), amb_hash11(i + 1.0), f);
}

// Smooth 2D value noise in 0..1.
float amb_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = amb_hash12(i);
	float b = amb_hash12(i + vec2(1.0, 0.0));
	float c = amb_hash12(i + vec2(0.0, 1.0));
	float d = amb_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

#ifdef AMB_REGION
// 0 at the region outline → 1 deeper than feather_px inside, so the redrawn picture joins the still
// one without a seam. edge_mode 0: none (1 everywhere); 1: a rectangle edge_rect (x, y, w, h),
// analytic; 2: an outline of any shape — a small distance texture edge_tex over edge_rect, made once
// when the room is built (AmbientRoot.feather_mask: chamfer distance / feather), one fetch per pixel.
float amb_edge(vec2 p) {
	if (edge_mode == 1) {
		vec2 d = min(p - edge_rect.xy, edge_rect.xy + edge_rect.zw - p);
		return smoothstep(0.0, max(feather_px, 0.001), min(d.x, d.y));
	}
	if (edge_mode == 2) {
		float m = texture(edge_tex, (p - edge_rect.xy) / edge_rect.zw).r;
		return smoothstep(0.0, 1.0, m);
	}
	return 1.0;
}

vec4 amb_src(vec2 room_p) {
	return texture(src_tex, (room_p - src_origin) / src_size);
}

float amb_sat(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mx > 0.001 ? (mx - mn) / mx : 0.0;
}
#endif
