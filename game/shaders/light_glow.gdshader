shader_type canvas_item;
render_mode unshaded, blend_add;

// Glow of a small light (the Z1 lantern; a lit window pane), data type "glow" in
// data/story/lights/<LOC>.json. Additive and unshaded, drawn on a quad centred on the source:
//   - halo: soft radial bloom around the glass (elliptic: `halo_aspect`);
//   - glass: a brighter ellipse the size of the glass (`glass_size`, fraction of the quad);
//   - flame (optional, `flame` > 0): a small teardrop wick flame that sways and breathes.
// `intensity` = fade × flicker, `flicker` = shared −1..1 value (from GDScript).

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float flicker = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.72, 0.36, 1.0);
uniform float halo = 0.45;
uniform float halo_aspect = 1.0;
uniform float halo_power = 2.2;
uniform vec2 glass_size = vec2(0.25, 0.3);
uniform vec2 glass_center = vec2(0.5, 0.5);
uniform float glass = 0.55;
uniform float flame = 0.0;
uniform vec2 flame_size = vec2(0.035, 0.11);
uniform vec2 flame_base = vec2(0.5, 0.58);
uniform float seed = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - glass_center;
	float r = length(vec2(c.x, c.y / halo_aspect)) * 2.0;
	float h = pow(max(0.0, 1.0 - r), halo_power) * halo;

	vec2 g = c / max(glass_size * 0.5, vec2(0.001));
	float gl = (1.0 - smoothstep(0.55, 1.0, length(g))) * glass;

	float fl = 0.0;
	if (flame > 0.0) {
		float t = TIME;
		float sway = sin(t * 3.1 + seed) * 0.25 + sin(t * 7.7 + seed * 2.0) * 0.12 + flicker * 0.2;
		float hgt = flame_size.y * (1.0 + 0.10 * flicker + 0.05 * sin(t * 11.0 + seed));
		float y = (flame_base.y - uv.y) / hgt;             // 0 at the wick, 1 at the tip
		float bend = sway * y * y * flame_size.x;
		float x = (uv.x - flame_base.x - bend) / flame_size.x;
		// Teardrop: widest a third of the way up, pointed at the tip, round at the wick.
		float wdt = sqrt(max(0.0, y)) * (1.0 - y) * 2.2;
		float inside = (1.0 - smoothstep(wdt * 0.7, wdt + 0.15, abs(x))) * step(0.0, y) * (1.0 - smoothstep(0.85, 1.0, y));
		fl = inside * flame;
	}
	vec3 rgb = color.rgb * (h + gl) * (1.0 + 0.18 * flicker) + vec3(1.0, 0.86, 0.55) * fl;
	COLOR = vec4(rgb * intensity, 1.0);
}
