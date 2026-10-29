shader_type canvas_item;
// J (Директор 29.10, стр. 161: «огонь свечи шевелится»): the painted candle flame in a close-up lives — inside an
// ellipse round it the picture is sampled with a small sway that grows towards the tip (the wick stays put), and
// the flame and its halo flicker a little in brightness. Everything else of the picture is untouched.
uniform vec2 center = vec2(0.5, 0.5);   // the flame's middle, UV of the picture
uniform vec2 radius = vec2(0.02, 0.05); // the ellipse round flame and halo, UV
uniform float base_y = 0.55;            // the wick (no sway there), UV
uniform float tip_y = 0.45;             // the flame's tip, UV
uniform float amp = 0.0022;             // sway at the tip, UV
uniform float flicker = 0.07;

void fragment() {
	vec2 d = (UV - center) / radius;
	float m = smoothstep(1.0, 0.35, length(d));
	float up = clamp((base_y - UV.y) / max(base_y - tip_y, 0.0001), 0.0, 1.0);
	vec2 uv = UV;
	float s = up * up * m;
	uv.x += (sin(TIME * 7.3 + UV.y * 220.0) * 0.6 + sin(TIME * 3.1) * 0.8 + sin(TIME * 12.7 + 1.7) * 0.3) * amp * s;
	uv.y += sin(TIME * 5.3 + UV.x * 140.0) * amp * 0.35 * s;
	vec4 c = texture(TEXTURE, uv);
	float f = 1.0 + m * (flicker * sin(TIME * 10.7) + flicker * 0.6 * sin(TIME * 17.9 + 0.8) + flicker * 0.4 * sin(TIME * 4.3 + 2.1));
	COLOR = vec4(c.rgb * f, c.a) * COLOR;
}
