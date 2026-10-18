shader_type canvas_item;

// Mirror close-up (CloseupView, rooms data hotspot `view.type == "mirror"`): the mirror as it hangs
// in the room's own background, seen face-on, with a live reflection in its glass.
//
// TEXTURE — the room background (as painted). `homography` maps a canvas pixel of this rect (the
// face-on view, `canvas_size`) to a pixel of TEXTURE (`src_size`): the glass quadrilateral of the
// painting (in perspective on the side wall) becomes the upright `glass_rect`, the frame and the wall
// around it follow the same mapping. Inside the glass: `reflection` (CloseupView's SubViewport — the
// gallery behind Agata and Agata herself) mirrored left↔right, a little darker and colder, wavy like
// old glass, with a trace of the painted dull surface. The wall fades out towards the rect's edges.

uniform sampler2D reflection : filter_linear, repeat_disable;
uniform mat3 homography;
uniform vec2 canvas_size = vec2(540.0, 1074.0);
uniform vec2 src_size = vec2(1672.0, 941.0);
uniform vec4 glass_rect = vec4(120.0, 210.0, 300.0, 714.0);
uniform vec4 tint : source_color = vec4(0.68, 0.75, 0.84, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.55;
uniform float dim : hint_range(0.0, 1.0) = 0.8;
uniform float haze : hint_range(0.0, 1.0) = 0.16;
uniform float waviness : hint_range(0.0, 0.05) = 0.006;
uniform float feather_px = 70.0;
uniform float reflection_on = 1.0;

void fragment() {
	vec2 d = UV * canvas_size;
	vec3 s = homography * vec3(d, 1.0);
	vec2 suv = clamp((s.xy / s.z) / src_size, vec2(0.0), vec2(1.0));
	vec3 painted = texture(TEXTURE, suv).rgb;
	vec3 col = painted;
	vec2 g = (d - glass_rect.xy) / glass_rect.zw;
	if (reflection_on > 0.5 && g.x >= 0.0 && g.x <= 1.0 && g.y >= 0.0 && g.y <= 1.0) {
		// Old glass is never quite flat: slow, fixed waves, a breath of drift.
		vec2 w = g;
		w.x += waviness * (sin(g.y * 21.0 + 1.3) * 0.7 + sin(g.y * 7.0 + g.x * 3.0 + TIME * 0.15) * 0.3);
		w.y += waviness * 0.6 * sin(g.x * 13.0 + g.y * 5.0 + 0.4);
		vec3 r = texture(reflection, vec2(1.0 - clamp(w.x, 0.0, 1.0), clamp(w.y, 0.0, 1.0))).rgb;
		float luma = dot(r, vec3(0.299, 0.587, 0.114));
		r = mix(r, vec3(luma), 0.25);                 // a little greyer
		r = mix(r, r * tint.rgb * 1.25, tint_amount);  // colder
		r *= dim;
		r = mix(r, painted, haze);                     // the dull painted surface shows through
		// Darker towards the edges of the glass (silvering worn at the frame).
		vec2 e = min(g, 1.0 - g);
		float edge = smoothstep(0.0, 0.08, min(e.x * 2.2, e.y * 4.5));
		r *= mix(0.72, 1.0, edge);
		// Faint diagonal sheen.
		r += smoothstep(0.55, 0.95, (g.x * 0.6 + (1.0 - g.y) * 0.4)) * 0.035;
		col = r;
	}
	vec2 m = min(d, canvas_size - d);
	float a = smoothstep(0.0, feather_px, min(m.x, m.y));
	COLOR = vec4(col, a);
}
