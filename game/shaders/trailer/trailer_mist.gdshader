shader_type canvas_item;
// TR1 trailer: low mist over the water — slow drifting value noise (two octaves crossing), soft at every edge of its
// rect, brightest in the middle band. Colour, strength and drift — data/trailer/<id>.json layers[kind = mist].

uniform vec4 mist_color : source_color = vec4(0.74, 0.8, 0.94, 1.0);
uniform float alpha = 0.3;
uniform float speed_px = 10.0;       // drift, art px per second
uniform float noise_scale = 0.006;   // per art px
uniform vec2 rect_size = vec2(1000.0, 250.0);
uniform float time_s = 0.0;          // shot time (the movie's own clock: the same frames on every render)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 p = px * noise_scale * vec2(1.0, 2.6);   // stretched along the river
	float n1 = fbm(p + vec2(time_s * speed_px * noise_scale, 0.0));
	float n2 = fbm(p * 1.7 + vec2(-time_s * speed_px * noise_scale * 0.6, 3.1));
	float n = smoothstep(0.3, 0.85, n1 * 0.65 + n2 * 0.45);
	float band = smoothstep(0.0, 0.45, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float sides = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
	COLOR = vec4(mist_color.rgb, alpha * n * band * sides);
}
