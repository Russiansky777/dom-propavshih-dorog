shader_type canvas_item;
render_mode unshaded, blend_add;

// Fire in the mouth of the H1 stove (data/story/lights/H1.json, type "fire"): drawn on a quad over the
// opening of the open-door layer; additive, unshaded (the room's darkness does not dim it).
//   - opening mask: straight jambs, segmental arch on top (`arch`), hearth line at the bottom;
//   - flames: two octaves of rising value-noise fbm shaped into tongues (sine columns warped by
//     the noise), dense and white-yellow at the logs, orange in the body, dark red at the tips;
//   - embers: pulsing orange cells along the hearth;
//   - inner glow: the brick throat lit orange from below;
//   - sparks: a few points rising and fading, each alive only part of its own period (rare).
// `intensity` = fade × flicker (from GDScript), `flicker` = the shared −1..1 flicker value.

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float flicker = 0.0;
uniform vec2 size_px = vec2(120.0, 130.0);
uniform float arch : hint_range(0.0, 0.6) = 0.26;
uniform float hearth : hint_range(0.0, 0.4) = 0.08;
uniform float flame_height : hint_range(0.1, 1.2) = 0.62;
uniform float speed = 1.0;
uniform float seed = 0.0;
uniform float glow_amount = 0.42;
uniform float ember_amount = 1.0;
uniform int spark_count = 5;
uniform vec4 col_core : source_color = vec4(1.0, 0.93, 0.66, 1.0);
uniform vec4 col_mid : source_color = vec4(1.0, 0.55, 0.14, 1.0);
uniform vec4 col_tip : source_color = vec4(0.78, 0.16, 0.03, 1.0);
uniform vec4 col_glow : source_color = vec4(1.0, 0.40, 0.10, 1.0);
uniform vec4 col_ember : source_color = vec4(1.0, 0.33, 0.05, 1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.02 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float opening_mask(vec2 uv) {
	float cx = uv.x * 2.0 - 1.0;
	float top = arch * (1.0 - sqrt(max(0.0, 1.0 - cx * cx)));
	float ay = 2.5 / size_px.y;
	float ax = 2.5 / size_px.x;
	float m = smoothstep(top, top + ay, uv.y);
	m *= smoothstep(0.0, ax, uv.x) * smoothstep(1.0, 1.0 - ax, uv.x);
	m *= smoothstep(1.0, 1.0 - ay, uv.y);
	return m;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float k = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * k);
}

void fragment() {
	vec2 uv = UV;
	float m = opening_mask(uv);
	float t = TIME * speed;
	// h: 0 at the hearth line, 1 at the top of the quad.
	float h = (1.0 - hearth - uv.y) / (1.0 - hearth);
	float aspect = size_px.x / size_px.y;
	vec2 p = vec2(uv.x * aspect, h);
	// Pixel position with the origin at the hearth line (for round shapes: logs, sparks).
	vec2 px = vec2(uv.x, h) * size_px;

	float n1 = fbm(vec2(p.x * 4.2 + seed, p.y * 3.1 - t * 2.3));
	float n2 = fbm(vec2(p.x * 9.0 - seed * 1.3, p.y * 6.5 - t * 3.9));
	float n = n1 * 0.66 + n2 * 0.34;

	// Logs on the hearth: two charred billets crossing, dark inside, glowing cracks and rims.
	float r1 = 0.055 * size_px.y;
	float r2 = 0.06 * size_px.y;
	float d1 = seg_dist(px, vec2(0.14, 0.07) * size_px, vec2(0.60, 0.115) * size_px) - r1;
	float d2 = seg_dist(px, vec2(0.40, 0.125) * size_px, vec2(0.88, 0.065) * size_px) - r2;
	float dlog = min(d1, d2);
	float in_log = 1.0 - smoothstep(-1.0, 1.0, dlog);
	float rim = (1.0 - smoothstep(0.0, 3.5, abs(dlog + 1.0)));
	float crack = smoothstep(0.60, 0.72, vnoise(px * vec2(0.22, 0.5) + vec2(seed * 5.0, 0.0)));
	float log_glow = in_log * crack * (0.55 + 0.45 * sin(t * 1.7 + px.x * 0.13)) + rim * 0.55;

	// Tongues: columns that sway with the low octave; the fire burns over the logs.
	float sway = (n1 - 0.5) * 0.32;
	float tongue = 0.5 + 0.5 * sin((uv.x + sway) * 27.0 + t * 1.2 + seed);
	float tongue2 = 0.5 + 0.5 * sin((uv.x - sway * 0.7) * 13.0 - t * 0.8 + seed * 2.0);
	float bed = smoothstep(0.06, 0.30, uv.x) * smoothstep(0.94, 0.70, uv.x);
	float reach = flame_height * (0.30 + 0.45 * tongue + 0.25 * tongue2) * (0.25 + 0.75 * bed) * (1.0 + 0.15 * flicker);
	float hh = max(h - 0.08, 0.0);                 // flames start on top of the logs
	float f = n * 1.55 - hh / max(reach, 0.02) - 0.08;
	f -= (1.0 - bed) * 0.35;
	float dens = clamp(f, 0.0, 1.0) * step(-0.02, h) * (1.0 - in_log * 0.85);
	dens *= 0.3 + 0.7 * smoothstep(0.02, 0.11, h);   // under the logs: the ember bed, not flame

	vec3 col = mix(col_tip.rgb, col_mid.rgb, smoothstep(0.05, 0.45, dens));
	col = mix(col, col_core.rgb, smoothstep(0.55, 0.98, dens));
	float a_fl = smoothstep(0.0, 0.38, dens);
	vec3 rgb = col * a_fl * 1.1;

	// Inner glow on the brick throat (stronger low, follows the flicker).
	float hg = clamp(h, 0.0, 1.0);
	rgb += col_glow.rgb * glow_amount * pow(1.0 - hg, 1.8) * (0.75 + 0.25 * n) * (1.0 + 0.25 * flicker) * (1.0 - in_log * 0.8);

	// Embers: the bed under and between the logs, cells pulsing at their own rate.
	vec2 ec = vec2(uv.x * 24.0, uv.y * 13.0);
	float cell = vnoise(ec + vec2(seed * 3.0, 0.0));
	float pulse = 0.55 + 0.45 * sin(t * (1.3 + hash12(floor(ec)) * 1.7) + hash12(floor(ec) + 7.0) * 6.283);
	float ember_band = 1.0 - smoothstep(0.0, 0.07, abs(h - 0.015));
	float ember = smoothstep(0.45, 0.85, cell) * pulse * ember_band * ember_amount * (1.0 - in_log);
	rgb += col_ember.rgb * (ember * 1.2 + log_glow * 0.9 * ember_amount);

	// Sparks: rare points rising from the logs and fading.
	float sp = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= spark_count) {
			break;
		}
		float fi = float(i);
		float period = 2.4 + hash12(vec2(fi, seed + 3.1)) * 3.2;
		float cyc = t / period + hash12(vec2(seed, fi * 1.37));
		float ph = fract(cyc);
		float life = 0.30;
		if (ph < life) {
			float k = ph / life;
			float id = floor(cyc);
			float sx = 0.28 + 0.44 * hash12(vec2(fi * 7.1, id));
			vec2 s = vec2(sx + sin(k * 7.0 + fi) * 0.05 * k, 0.12 + k * (0.7 + 0.2 * hash12(vec2(id, fi))));
			vec2 d = (vec2(uv.x, h) - s) * size_px;
			sp += exp(-dot(d, d) / 2.0) * (1.0 - k) * 1.6;
		}
	}
	rgb += vec3(1.0, 0.78, 0.38) * sp;

	COLOR = vec4(rgb * m * intensity, 1.0);
}
