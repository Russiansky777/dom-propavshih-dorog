shader_type canvas_item;

// What a thing from the bag lies on when Agata looks at it closely (ItemExamine, items.json `examine.backdrop`):
// linen cloth ("cloth"), a scrubbed table ("table") or paper ("paper") under a warm lamp — a woven or grained
// surface computed here (no picture needed), lit in the middle, dark at the edges.

uniform vec4 base : source_color = vec4(0.62, 0.54, 0.42, 1.0);
uniform vec4 dark : source_color = vec4(0.10, 0.075, 0.05, 1.0);
uniform float weave : hint_range(0.0, 0.3) = 0.08;      // cloth threads
uniform float grain : hint_range(0.0, 0.3) = 0.0;       // wood grain / paper fibre
uniform float vignette : hint_range(0.0, 1.0) = 0.85;
uniform vec2 aspect = vec2(1.7778, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * aspect;
	vec3 c = base.rgb;
	// Threads: warp and weft, slightly irregular.
	float wx = sin(p.x * 520.0 + noise(p * 40.0) * 2.0);
	float wy = sin(p.y * 520.0 + noise(p.yx * 40.0) * 2.0);
	c *= 1.0 + weave * 0.5 * (wx * 0.5 + wy * 0.5);
	c *= 1.0 + weave * (noise(p * 9.0) - 0.5);
	// Grain: long streaks along x (wood) or soft fibres (paper).
	c *= 1.0 + grain * (noise(vec2(p.x * 3.0, p.y * 60.0)) - 0.5) * 1.6;
	// A warm lamp over the middle.
	vec2 v = (UV - vec2(0.5, 0.47)) * vec2(1.0, 1.25);
	float lit = smoothstep(0.9, 0.05, length(v));
	c = mix(dark.rgb, c, mix(1.0 - vignette, 1.0, lit));
	COLOR = vec4(c, 1.0);
}
