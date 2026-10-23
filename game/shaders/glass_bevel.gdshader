shader_type canvas_item;
// H26 (Director 24.10: «зеркало — прямоугольник сейчас вырезанный, а должно быть зеркало»): the office mirror's glass as
// glass in a frame — a bevelled edge (a light facet along the top and left, a dark one along the bottom and right), the
// silvering a little tarnished towards the edges, a cool tint and a soft diagonal glare that slowly drifts. Drawn over
// the live view (OfficeView texture) on the glass contour; UV 0..1 across the glass.

uniform float bevel = 0.045;           // facet width, share of the glass
uniform float bevel_light = 0.22;
uniform float bevel_dark = 0.30;
uniform float tarnish = 0.28;          // darkening of the silver at the very edge
uniform vec4 tint : source_color = vec4(0.86, 0.92, 1.0, 1.0);
uniform float tint_amount = 0.18;
uniform float glare = 0.10;
uniform vec2 aspect = vec2(1.0, 1.6);  // glass height / width, so the facets are equally wide on all sides

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	col.rgb = mix(col.rgb, col.rgb * tint.rgb, tint_amount);
	vec2 u = UV;
	float bx = bevel;
	float by = bevel / max(aspect.y, 0.01);
	float l = 1.0 - smoothstep(0.0, bx, u.x);
	float r = 1.0 - smoothstep(0.0, bx, 1.0 - u.x);
	float t = 1.0 - smoothstep(0.0, by, u.y);
	float b = 1.0 - smoothstep(0.0, by, 1.0 - u.y);
	col.rgb += vec3(1.0, 0.97, 0.9) * max(l, t) * bevel_light;
	col.rgb *= 1.0 - max(r, b) * bevel_dark;
	// Tarnished silver near the frame, worst in the corners.
	float e = min(min(u.x, 1.0 - u.x) / (bx * 3.0), min(u.y, 1.0 - u.y) / (by * 3.0));
	col.rgb *= 1.0 - tarnish * (1.0 - smoothstep(0.0, 1.0, e));
	// A soft diagonal glare, slowly drifting.
	float d = (u.x * 0.8 + u.y * 0.45) - 0.55 - 0.05 * sin(TIME * 0.25);
	col.rgb += vec3(1.0) * glare * (exp(-pow(d / 0.07, 2.0)) + 0.5 * exp(-pow((d - 0.16) / 0.03, 2.0)));
	COLOR = col;
}
