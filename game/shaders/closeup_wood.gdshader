// Р14 (партия J): weathered pine planks for a close-up drawn by the engine (the signal board at the pier) until its
// painting comes: long grain along x from stretched value noise, a few darker growth lines, planks split by thin
// dark seams, rain-greyed ends and a soft darker rim. `base` — the wood's mid colour (data "paper").
shader_type canvas_item;

uniform vec4 base : source_color = vec4(0.49, 0.37, 0.25, 1.0);
uniform vec2 rect_size = vec2(800.0, 600.0);
uniform float planks = 3.0;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 px = UV * rect_size;
	float plank_h = rect_size.y / planks;
	float pi = floor(px.y / plank_h);
	float py = px.y - pi * plank_h;
	vec2 q = vec2(px.x / 140.0, px.y / 7.0) + vec2(pi * 13.7, pi * 3.1);
	float grain = n2(q) * 0.6 + n2(q * 2.3 + 4.0) * 0.3 + n2(q * 5.1 + 9.0) * 0.1;
	float rings = smoothstep(0.82, 0.95, fract(n2(vec2(px.x / 420.0, px.y / 26.0) + pi) * 6.0));
	vec3 c = base.rgb * (0.82 + 0.3 * grain) - rings * 0.035;
	// rain-greyed, a touch lighter towards the ends of each plank
	float ends = smoothstep(0.0, 0.22, UV.x) * smoothstep(1.0, 0.78, UV.x);
	c = mix(c, vec3(dot(c, vec3(0.33))) * 1.08, (1.0 - ends) * 0.35);
	// seams between planks
	float seam = smoothstep(0.0, 3.0, py) * smoothstep(0.0, 3.0, plank_h - py);
	c *= mix(0.45, 1.0, seam);
	// soft darker rim
	vec2 e = min(px, rect_size - px);
	float rim = smoothstep(0.0, 26.0, min(e.x, e.y));
	c *= mix(0.62, 1.0, rim);
	COLOR = vec4(c, 1.0);
}
