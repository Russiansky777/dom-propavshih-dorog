shader_type canvas_item;

// An old photograph made from the room's own painting (CloseupView, `view.photo`): sepia, softer
// contrast, a little grain, faded corners. Only the tone changes — what is in the picture is the
// painted room itself, nothing is added.

uniform vec4 sepia_dark : source_color = vec4(0.16, 0.11, 0.07, 1.0);
uniform vec4 sepia_light : source_color = vec4(0.93, 0.85, 0.70, 1.0);
uniform float contrast : hint_range(0.3, 1.5) = 0.85;
uniform float grain : hint_range(0.0, 0.2) = 0.05;
uniform float vignette : hint_range(0.0, 1.0) = 0.45;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	l = clamp((l - 0.5) * contrast + 0.52, 0.0, 1.0);
	l += (hash(floor(UV * 420.0)) - 0.5) * grain;
	vec3 col = mix(sepia_dark.rgb, sepia_light.rgb, clamp(l, 0.0, 1.0));
	vec2 v = UV - 0.5;
	float fade = smoothstep(0.75, 0.35, length(v * vec2(1.0, 1.15)));
	col = mix(col * (1.0 - vignette * 0.5), col, fade);
	col = mix(col, sepia_light.rgb, (1.0 - fade) * 0.25);
	COLOR = vec4(col, 1.0);
}
