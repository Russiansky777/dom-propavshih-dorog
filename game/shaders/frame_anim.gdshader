// A figure of a composed frame played from its sheet clips (Director 01.11, lines 61 and 68: «на кадрах с Ниной она
// статична», «никто не двигается, когда говорит»). The sprite's texture is the figure's atlas
// (tools/make_frame_layers.py, compose.anim → <layer>_anim.png): every cell is one sheet frame composed exactly as the
// layer picture (scale, feet, tint, shadow, hidden parts). The sprite draws one cell-sized quad (region = cell 0); this
// shader picks the cells to show — the rest clip's frame (and the next one, `rest_mix`, for a sparse clip), the talk
// clip's frame (and its next, `talk_mix`) — and dissolves rest → talk by `talk_w` on premultiplied colour (no ghost
// halo, no see-through mid-fade). StateLayer sets the uniforms every frame.
// A figure without a talk clip (Agata's sheet has none yet) moves its head and shoulders with its own line by a soft
// warp (`warp_talk`), as game/shaders/frame_figure.gdshader does for a still picture.
shader_type canvas_item;

uniform vec2 atlas_px = vec2(1.0);       // atlas size, px
uniform vec2 cell_px = vec2(1.0);        // one cell, px
uniform vec2 rest_a = vec2(0.0);         // top-left of the cells in the atlas, px
uniform vec2 rest_b = vec2(0.0);
uniform float rest_mix = 0.0;
uniform vec2 talk_a = vec2(0.0);
uniform vec2 talk_b = vec2(0.0);
uniform float talk_mix = 0.0;
uniform float talk_w = 0.0;              // 0 — the rest clip, 1 — the talk clip

uniform vec2 feet_px = vec2(0.0);        // the figure's feet in the cell
uniform float height_px = 300.0;
uniform float phase = 0.0;
uniform float warp_talk = 0.0;           // 0..1: the head moves with the words (no talk clip)
uniform float talk_frac = 0.008;
uniform float time_s = 0.0;

// a cell is sampled only inside itself: the linear filter never takes its neighbour (TEXTURE is read in fragment())
vec2 cell_uv(vec2 origin, vec2 p) {
	return (origin + clamp(p, vec2(0.5), cell_px - vec2(0.5))) / atlas_px;
}

vec4 premul(vec4 c, float inside) {
	return vec4(c.rgb * c.a, c.a) * inside;
}

void fragment() {
	vec2 p = UV * atlas_px;    // the quad is cell 0 at the atlas origin: UV·size = the pixel in the cell
	if (warp_talk > 0.0) {
		float H = max(height_px, 1.0);
		float h = clamp((feet_px.y - p.y) / H, 0.0, 1.3);
		float t = time_s;
		float n1 = 0.6 * sin(TAU * 1.55 * t + phase) + 0.4 * sin(TAU * 2.65 * t + 2.0 * phase);
		float n2 = 0.6 * sin(TAU * 0.95 * t + 0.5 * phase) + 0.4 * sin(TAU * 1.85 * t + 3.0 * phase);
		vec2 d = vec2(0.0);
		d.y -= warp_talk * talk_frac * H * (0.5 + 0.5 * n1) * smoothstep(0.72, 1.0, h);
		d.x += warp_talk * talk_frac * 0.7 * H * n2 * smoothstep(0.55, 1.0, h);
		p -= d;
	}
	float inside = step(0.0, p.x) * step(0.0, p.y) * step(p.x, cell_px.x) * step(p.y, cell_px.y);
	vec4 r = mix(premul(texture(TEXTURE, cell_uv(rest_a, p)), inside), premul(texture(TEXTURE, cell_uv(rest_b, p)), inside), rest_mix);
	vec4 c = r;
	if (talk_w > 0.0) {
		vec4 k = mix(premul(texture(TEXTURE, cell_uv(talk_a, p)), inside), premul(texture(TEXTURE, cell_uv(talk_b, p)), inside), talk_mix);
		c = mix(r, k, talk_w);
	}
	COLOR = c.a > 0.0001 ? vec4(c.rgb / c.a, c.a) : vec4(0.0);
}
