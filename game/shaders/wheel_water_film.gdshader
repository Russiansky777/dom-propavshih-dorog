shader_type canvas_item;
// Live water from a video clip over the mill wheel (AmbientWheel `film`, Director 16.11, 17:28: «давай вставлять
// так»): one Ogg Theora stream holds the water's colour on top and its opacity (grey) under it, `gap_px` apart —
// tools/wheel_water.py --pack. The player is sized to the colour part; this puts the two halves together.

uniform float color_frac = 0.4831;   // colour height / stream height
uniform float alpha_from = 0.5169;   // where the opacity starts / stream height

void fragment() {
	vec3 c = texture(TEXTURE, vec2(UV.x, UV.y * color_frac)).rgb;
	float a = texture(TEXTURE, vec2(UV.x, alpha_from + UV.y * color_frac)).g;
	COLOR = vec4(c, clamp(a, 0.0, 1.0) * COLOR.a);
}
