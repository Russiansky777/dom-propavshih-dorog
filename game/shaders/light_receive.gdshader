shader_type canvas_item;

// Room art under the room's light map (RoomLighting): background, layers, occluders, props.
// The light map is a 1/4-resolution SubViewport the size of the canvas (1920x1080), cleared to 0.5
// (= light 1, the art as painted), lowered by darkness (ambient / SUB masks) and raised by lights
// (points / ADD masks), all ×0.5 so a light up to 2× fits in 8 bits. Two samples per pixel — the
// whole lighting of a room costs about one extra texture read on the art.

uniform sampler2D room_light_tex : filter_linear, repeat_disable;
uniform vec2 canvas_size = vec2(1920.0, 1080.0);

varying vec2 lm_uv;

void vertex() {
	lm_uv = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / canvas_size;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec3 l = texture(room_light_tex, clamp(lm_uv, vec2(0.0), vec2(1.0))).rgb * 2.0;
	COLOR = vec4(c.rgb * l, c.a);
}
