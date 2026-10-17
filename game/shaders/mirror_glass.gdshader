shader_type canvas_item;

// Mirror glass: slight cold tint + UV wobble while the mirror is not mounted.
// `wobble_enabled` is driven from GDScript by the `mirror_mounted` flag (1.0 = unmounted, wobbling).
uniform float wobble_enabled = 1.0;
uniform float wobble_strength : hint_range(0.0, 0.1) = 0.014;
uniform float wobble_speed : hint_range(0.0, 10.0) = 2.2;
uniform vec4 tint : source_color = vec4(0.72, 0.84, 0.98, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 uv = UV;
	float w = wobble_enabled * wobble_strength;
	uv.x += sin(uv.y * 18.0 + TIME * wobble_speed) * w;
	uv.y += cos(uv.x * 14.0 + TIME * wobble_speed * 0.8) * w * 0.6;
	uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec4 col = texture(TEXTURE, uv);
	col.rgb = mix(col.rgb, col.rgb * tint.rgb, tint_amount);
	// Diagonal glass sheen.
	float sheen = smoothstep(0.35, 0.75, (UV.x + UV.y) * 0.5) * 0.10;
	col.rgb += sheen;
	COLOR = col;
}
