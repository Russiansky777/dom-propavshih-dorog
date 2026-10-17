// «Живой мир» — shared helpers of the ambient shaders (ambient_sway / ambient_water).
// A region shader (#define AMB_REGION before the #include) declares first:
//   uniform vec2 poly[32]; uniform int poly_n;   — the region outline in room px (feathered edge)
//   uniform sampler2D src_tex; uniform vec2 src_origin; uniform vec2 src_size;
//                                                — the picture under the region and where it is drawn
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
// Distance from p to the outline poly[0..poly_n) (the fill is the polygon itself, so inside only).
float amb_edge_dist(vec2 p) {
	float d = 1.0e6;
	for (int i = 0; i < 32; i++) {
		if (i >= poly_n) {
			break;
		}
		vec2 a = poly[i];
		vec2 b = poly[(i + 1 == poly_n) ? 0 : i + 1];
		vec2 pa = p - a;
		vec2 ba = b - a;
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
		d = min(d, length(pa - ba * h));
	}
	return d;
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
