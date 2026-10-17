shader_type canvas_item;
render_mode unshaded;

// Cast shadow of an actor from a room light (ActorLightShadow): the current frame of the actor's
// sheet used as a silhouette — black, alpha = blurred coverage × `alpha`, fading towards the head
// end (`head_fade`) so the far end of a long shadow dissolves into the floor. The node transform
// (GDScript) lays the silhouette on the floor away from the light.

uniform float alpha : hint_range(0.0, 1.0) = 0.3;
uniform float blur_px = 2.0;          // blur radius in sheet texels
uniform float figure_h = 363.0;       // feet → top of the frame in local (sheet) px
uniform float head_fade : hint_range(0.0, 1.0) = 0.6;

varying float hfrac;

void vertex() {
	hfrac = clamp(-VERTEX.y / max(figure_h, 1.0), 0.0, 1.0);
}

void fragment() {
	vec2 d = TEXTURE_PIXEL_SIZE * blur_px;
	float a = texture(TEXTURE, UV).a * 0.28;
	a += texture(TEXTURE, UV + vec2(d.x, 0.0)).a * 0.12;
	a += texture(TEXTURE, UV - vec2(d.x, 0.0)).a * 0.12;
	a += texture(TEXTURE, UV + vec2(0.0, d.y)).a * 0.12;
	a += texture(TEXTURE, UV - vec2(0.0, d.y)).a * 0.12;
	a += texture(TEXTURE, UV + d).a * 0.06;
	a += texture(TEXTURE, UV - d).a * 0.06;
	a += texture(TEXTURE, UV + vec2(d.x, -d.y)).a * 0.06;
	a += texture(TEXTURE, UV + vec2(-d.x, d.y)).a * 0.06;
	float fade = mix(1.0, 1.0 - head_fade, hfrac);
	COLOR = vec4(0.0, 0.0, 0.0, a * alpha * fade);
}
