shader_type canvas_item;
// TR1 trailer: the whole frame's grade over the game picture — tint (cold dusk outside / warm lamp inside), lift of
// the shadows, a soft vignette. Grain is added later at the final size (tools/trailer_assemble.py).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 tint = vec3(1.0);
uniform vec3 lift = vec3(0.0);
uniform float vignette = 0.32;        // darkening at the corners
uniform float vignette_soft = 0.75;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	c = c * tint + lift * (1.0 - c);
	vec2 q = SCREEN_UV - 0.5;
	q.x *= 1.25;
	float v = 1.0 - vignette * smoothstep(0.25, vignette_soft, length(q));
	COLOR = vec4(c * v, 1.0);
}
