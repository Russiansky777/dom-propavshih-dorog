// A figure in a composed frame breathes and sways (Director 01.11, lines 61 and 68: «на кадрах с Ниной она статична»,
// «никто не двигается, когда говорит»). A frame's character is one still picture layer (tools/make_frame_layers.py);
// this redraws it warped a little: nothing moves at the feet (the shadow under them stays), the chest and shoulders rise
// with the breath, the body sways from the ankles more and more towards the head, and while the character's own line
// is being said (`talk` 0..1, StateLayer) the head and shoulders move with the words. All in the layer's own texture
// pixels; parameters — game/data/actors/frame_life.json, per layer `life` (StateLayer._setup_life).
shader_type canvas_item;

uniform vec2 feet_px = vec2(0.0);       // the figure's feet in the layer picture (compose.feet)
uniform float height_px = 300.0;        // its height there (compose.height)
uniform float phase = 0.0;              // each figure its own moment (not all breathing together)
uniform float breath_frac = 0.004;      // the shoulders rise by this share of the height
uniform float breath_period_s = 4.2;
uniform float sway_frac = 0.005;        // the head sways by this share of the height
uniform float sway_period_s = 7.0;
uniform float talk = 0.0;               // 0 — quiet, 1 — the line is being said
uniform float talk_frac = 0.006;        // the head moves with the words by this share of the height
uniform float time_s = 0.0;             // StateLayer's clock (stops with the game's pause)

void fragment() {
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float H = max(height_px, 1.0);
	float h = clamp((feet_px.y - px.y) / H, 0.0, 1.3);
	float t = time_s;
	float b = sin(TAU * t / max(breath_period_s, 0.5) + phase);
	float s = 0.7 * sin(TAU * t / max(sway_period_s, 0.5) + 1.7 * phase) + 0.3 * sin(TAU * t / max(sway_period_s * 0.61, 0.3) + 2.3 * phase);
	float n1 = 0.6 * sin(TAU * 1.55 * t + phase) + 0.4 * sin(TAU * 2.65 * t + 2.0 * phase);
	float n2 = 0.6 * sin(TAU * 0.95 * t + 0.5 * phase) + 0.4 * sin(TAU * 1.85 * t + 3.0 * phase);
	vec2 d = vec2(0.0);
	d.y -= breath_frac * H * (0.5 + 0.5 * b) * smoothstep(0.35, 0.95, h);
	d.x += sway_frac * H * s * h * h;
	d.y -= talk * talk_frac * H * (0.5 + 0.5 * n1) * smoothstep(0.72, 1.0, h);
	d.x += talk * talk_frac * 0.7 * H * n2 * smoothstep(0.55, 1.0, h);
	COLOR = texture(TEXTURE, (px - d) * TEXTURE_PIXEL_SIZE);
}
