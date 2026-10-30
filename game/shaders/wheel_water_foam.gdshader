shader_type canvas_item;
// Foam and churned (aerated) water for AmbientWheel (J 30.10): a patch is a quad; inside it a lacy froth — noise
// thresholded into bubbles and holes, soft at the rim, never a hard-edged disc. The vertex colour carries the patch's
// own parameters (all four corners the same): r — seed, g — age 0..1 (the lace opens up and thins as it ages),
// b — kind (0 foam lace drifting on the surface, 1 white churn where water lands), a — opacity.

uniform vec3 foam_col : source_color = vec3(0.94, 0.96, 0.97);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float seed = COLOR.r * 113.0;
	float age = COLOR.g;
	float churn = step(0.5, COLOR.b);
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	// irregular rim: the outline itself wobbles with noise
	float rim_n = vnoise(vec2(atan(q.y, q.x) * 2.2 + seed, seed * 0.3));
	float fall = 1.0 - smoothstep(0.25 + 0.25 * rim_n, 1.0, r);
	vec2 p = UV * vec2(6.0, 4.0) + vec2(seed, seed * 0.37) + vec2(TIME * (0.12 + 0.5 * churn), TIME * 0.05);
	float n = fbm(p);
	// foam: lace of bubbles with dark holes, opening as it ages; churn: dense white, boiling (faster noise)
	float lo = mix(0.40 + 0.22 * age, 0.30 + 0.25 * age, churn);
	float hi = lo + mix(0.16, 0.30, churn);
	float lace = smoothstep(lo, hi, n);
	float a = fall * lace * COLOR.a;
	COLOR = vec4(foam_col * (0.92 + 0.12 * n), a);
}
