shader_type canvas_item;
// TR1 trailer: one depth layer of a flat picture (tools/make_trailer_layers.py). The layer is drawn over the whole
// art (stage zoomed by the camera about `anchor`); every pixel is zoomed again by its own depth relative to the
// camera — far pixels lag (k0), near ones run ahead (k1): parallax inside a surface without seams. The menu's
// living picture (water, wind in the leaves, the window's lamp — title_bg.gdshader, menu.json title.fx) runs on
// the source position. Parameters come from data/trailer/<id>.json (TrailerShot).

uniform sampler2D mask_tex : filter_linear;
uniform sampler2D depth_tex : filter_linear;
uniform int depth_channel = 0;
uniform vec2 anchor = vec2(0.0);
uniform float cam_zoom = 1.0;            // the camera's push-in now (1 → 1.085)
uniform float time_s = 0.0;             // shot time (the movie clock), offset so the water is mid-motion
uniform float k0 = 0.5;                  // layer zoom gain at depth 0 / 1 (× the camera's)
uniform float k1 = 1.5;
uniform vec3 tint = vec3(1.0);
uniform vec3 lift = vec3(0.0);
uniform vec2 art_size = vec2(1672.0, 941.0);
uniform float water_amp_px = 1.4;
uniform float water_period_s = 8.0;
uniform float water_wavelength_px = 26.0;
uniform float water_shimmer = 0.07;
uniform float sway_amp_px = 2.2;
uniform float sway_period_s = 7.0;
uniform float sway_noise_scale = 0.012;
uniform float window_breathe = 0.04;
uniform float window_period_s = 6.0;
uniform float window_flicker = 0.012;
uniform float window_flicker_hz = 9.0;
uniform float sway_gust = 0.0;
uniform float sway_gust_period_s = 11.0;
uniform float sway_lean = 0.0;

float depth_at(vec2 p) {
	vec4 t = texture(depth_tex, p / art_size);
	return depth_channel == 0 ? t.r : t.g;
}

float rel_zoom(float d) {
	float z = 1.0 + (cam_zoom - 1.0) * (k0 + (k1 - k0) * d);
	return z / cam_zoom;
}

const float TAU_ = 6.2831853;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// Depth zoom about the anchor (one fixed-point step: depth read where the pixel will come from).
	vec2 p0 = UV * art_size;
	float d = depth_at(p0);
	vec2 src = anchor + (p0 - anchor) / rel_zoom(d);
	d = depth_at(src);
	src = anchor + (p0 - anchor) / rel_zoom(d);
	vec2 uv = src / art_size;
	vec4 m = texture(mask_tex, uv);
	vec2 px = src;
	float t = time_s;
	vec2 off = vec2(0.0);
	// Water: a slow wave train across the river, a cross ripple and a fine fast ripple (H57: «вода живая»).
	float w1 = sin(px.y / water_wavelength_px * TAU_ + t * TAU_ / water_period_s + sin(px.x * 0.013) * 1.5);
	float w2 = sin(px.x * 0.021 - t * TAU_ / (water_period_s * 1.37) + px.y * 0.05);
	float w3 = vnoise(vec2(px.x * 0.06 - t * 0.9, px.y * 0.22 + t * 0.35)) - 0.5;
	off += m.r * water_amp_px * vec2(0.7 * w1 + 0.8 * w3, 0.45 * w2 + 0.5 * w3);
	// Wind: a gust envelope over time (smooth noise: it rises, holds a moment and dies down, never on a beat).
	float gust_n = vnoise(vec2(t / sway_gust_period_s * 1.6, 3.7)) * 0.65 + vnoise(vec2(t / sway_gust_period_s * 4.1, 9.1)) * 0.35;
	float gust = smoothstep(0.42, 0.78, gust_n);
	// Sway: every patch of leaves has its own phase (noise over position) and two incommensurate periods.
	float ph = vnoise(px * sway_noise_scale) * TAU_;
	float ph2 = vnoise(px * sway_noise_scale * 1.7 + 13.0) * TAU_;
	float s = sin(t * TAU_ / sway_period_s + ph) * 0.75 + sin(t * TAU_ / (sway_period_s * 0.61) + ph2) * 0.25;
	float shiver = sin(t * TAU_ / (sway_period_s * 0.17) + ph2 * 3.0) * gust;   // leaves flutter faster in a gust
	float amp = sway_amp_px * (1.0 + sway_gust * gust);
	off += m.g * (amp * vec2(s + 0.35 * shiver, 0.3 * cos(t * TAU_ / (sway_period_s * 0.83) + ph)) + vec2(sway_lean * gust, 0.0));
	vec4 c = texture(TEXTURE, uv + off / art_size);
	// Glints: only on the bright parts of the water (the sun's path).
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float glint = sin(px.x * 0.09 + t * 1.7 + w1 * 2.0) * sin(px.y * 0.35 - t * 1.1);
	c.rgb *= 1.0 + m.r * water_shimmer * glint * smoothstep(0.25, 0.7, lum);
	// The window: a slow breath and a faint lamp flicker.
	float breathe = sin(t * TAU_ / window_period_s) * window_breathe;
	float flick = ((vnoise(vec2(t * window_flicker_hz, 0.5)) - 0.5) * 1.4 + (vnoise(vec2(t * window_flicker_hz * 2.7, 7.5)) - 0.5) * 0.6) * 2.0 * window_flicker;
	c.rgb *= 1.0 + m.b * (breathe + flick);
	c.rgb = c.rgb * tint + lift;
	COLOR = c;
}
