// Agata in real 3D (Actor3D): the light of the sprite renders (pipeline/render/render_sprites.py, Cycles),
// recomputed per pixel in one unshaded pass — three suns fixed to the camera (key / fill / rim, Lambert,
// strength / π like Cycles) + uniform world light (grey background of the render). No engine lights:
// one draw call, the same look in the browser (Compatibility) and on desktop. The room tone is applied
// later in 2D (self_modulate of the figure), exactly as on the sprites.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, depth_test_default;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 key_dir = vec3(-0.470, 0.574, 0.671);   // towards the light, world space (Godot axes)
uniform vec3 fill_dir = vec3(0.604, 0.342, -0.720);
uniform vec3 rim_dir = vec3(0.296, -0.5, 0.814);
uniform float key_e = 1.432;    // Blender sun 4.5 / π
uniform float fill_e = 0.637;   // 2.0 / π
uniform float rim_e = 0.796;    // 2.5 / π
uniform vec3 ambient = vec3(0.6, 0.6, 0.65);
uniform float wrap = 0.0;       // soft terminator (0 = pure Lambert)
uniform float gain = 1.0;
uniform float roughness = 0.553;   // glTF roughnessFactor of the Meshy material (metallic 0)
uniform float f0 = 0.04;           // dielectric (Principled IOR 1.5)
uniform float spec_gain = 1.0;
uniform float alpha_cut = 0.5;
uniform float inside_light = 0.45;   // back faces (the inside of the clothes): share of the light that reaches them
uniform float debug_flat = -1.0;   // >= 0: output this grey (colour-pipeline probe)
uniform bool debug_albedo = false; // output the texture as sampled (no light)

// The Compatibility renderer samples and writes this viewport in sRGB codes (measured: a flat 0.5 comes
// out as 128, the texture comes out as stored) — lighting is done in linear like Cycles, then encoded.
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

float lam(vec3 n, vec3 l) {
	return max((dot(n, l) + wrap) / (1.0 + wrap), 0.0);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	if (a.a < alpha_cut) {
		discard;
	}
	vec3 n = normalize(NORMAL);   // view space
	vec3 lk = normalize((VIEW_MATRIX * vec4(key_dir, 0.0)).xyz);
	vec3 lf = normalize((VIEW_MATRIX * vec4(fill_dir, 0.0)).xyz);
	vec3 lr = normalize((VIEW_MATRIX * vec4(rim_dir, 0.0)).xyz);
	// Double-sided material (inside of the skirt, the coat): with cull_disabled Godot already turns NORMAL towards
	// the viewer on back faces (debug render 31.10: back faces green = facing the camera). Flipping it again here lit
	// the inside of the skirt from behind with the full grazing Fresnel of the world — a flat blue-grey patch between
	// the legs when she bent to the floor. The inside of clothes is in the cloth's own shadow: inside_light.
	float inside = FRONT_FACING ? 1.0 : inside_light;
	vec3 v = vec3(0.0, 0.0, 1.0);  // orthographic camera
	vec3 light = ambient + key_e * lam(n, lk) + fill_e * lam(n, lf) + rim_e * lam(n, lr);
	// Specular of a rough dielectric (normalised Blinn-Phong ≈ GGX at this roughness, Schlick
	// Fresnel) from the three suns and the uniform world: the soft sheen of the Cycles renders.
	float al = roughness * roughness;
	float sh = max(2.0 / (al * al) - 2.0, 1.0);
	float nv = max(dot(n, v), 0.0);
	float fr_env = f0 + (1.0 - f0) * pow(1.0 - nv, 5.0) * (1.0 - roughness) * (1.0 - roughness);
	vec3 spec = ambient * fr_env;
	vec3 ls[3] = vec3[3](lk, lf, lr);
	float es[3] = float[3](key_e, fill_e, rim_e);
	for (int i = 0; i < 3; i++) {
		vec3 h = normalize(ls[i] + v);
		float nl = max(dot(n, ls[i]), 0.0);
		float fr = f0 + (1.0 - f0) * pow(1.0 - max(dot(h, v), 0.0), 5.0);
		spec += vec3(es[i] * nl * fr * (sh + 8.0) / (8.0 * PI) * pow(max(dot(n, h), 0.0), sh));
	}
	vec3 lin = (to_linear(a.rgb) * light * (1.0 - fr_env) + spec * spec_gain) * inside;
	ALBEDO = to_srgb(lin * gain);
	if (debug_albedo) {
		ALBEDO = a.rgb;
	}
	if (debug_flat >= 0.0) {
		ALBEDO = vec3(debug_flat);
	}
}
