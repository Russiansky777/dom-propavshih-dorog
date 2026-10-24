shader_type canvas_item;
// TR1 trailer title: the menu's gold on the letters — a vertical gradient (shadowed amber → pale gold → amber) and a
// glint that runs across the words like light over carving. The label draws white; its outline (dark) stays dark.

uniform vec3 gold_dark = vec3(0.55, 0.36, 0.14);
uniform vec3 gold_light = vec3(1.0, 0.86, 0.6);
uniform vec3 gold_low = vec3(0.78, 0.55, 0.24);
uniform vec2 box_size = vec2(1920.0, 200.0);   // the label's rect (local px)
uniform float glyph_top = 0.2;                 // the letters' band inside the rect (share of height)
uniform float glyph_bottom = 0.8;
uniform float glint_pos = -1.0;                // −0.3 … 1.3 across the width; outside — no glint
uniform float glint_width = 0.14;
uniform float glint_gain = 0.9;
uniform float appear = 1.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float y = clamp((local.y / box_size.y - glyph_top) / max(0.01, glyph_bottom - glyph_top), 0.0, 1.0);
	vec3 g = y < 0.45 ? mix(gold_dark, gold_light, smoothstep(0.0, 0.45, y)) : mix(gold_light, gold_low, smoothstep(0.45, 1.0, y));
	// The glint: a slanted soft band (light from the upper left), a warm white core.
	float x = local.x / box_size.x + (local.y / box_size.y) * 0.08;
	float k = 1.0 - smoothstep(0.0, glint_width, abs(x - glint_pos));
	k = k * k;
	vec3 c = g + vec3(1.0, 0.95, 0.82) * k * glint_gain;
	vec4 base = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(base.rgb * c, base.a * appear);
}
