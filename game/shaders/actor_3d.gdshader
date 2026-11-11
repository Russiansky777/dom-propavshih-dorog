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
uniform bool as_painted = false;   // a held thing's picture (Actor3D hand props): already painted with its light, shown as is
// The villagers' mouths by the voice (Director 09.11, 21:21; 21:56 «рот сделан плохо»; 22:18 «рты открывающиеся и
// нормальные»): the models are one closed surface with the lips cut apart — turning the jaw tore it into a jagged slit
// with whatever lay behind showing through. The mouth is painted instead: a dark lens on the face along the lip line
// (measured from the model: tests/bake_mouth.gd → data/actors_rest/mouth_<id>.json), opening down and a little up with
// the voice (JawModifier). mouth_inv — world → the mouth's frame (x across, y up, z out of the face; model units);
// mouth_shape — half width of the opening, its height fully open, how much higher the lips' corners are than the middle,
// how far behind it. mouth_open 0 — nothing is painted (Agata, things in hands, a shut mouth).
uniform mat4 mouth_inv = mat4(1.0);
uniform float mouth_open = 0.0;
uniform vec4 mouth_shape = vec4(0.0);
uniform float mouth_up_share = 0.3;
uniform float mouth_depth = 1.6;      // the paint lies on the face within this of the lip line, front and back (model units)
// 11.11 (Director: «губы — фон чёрный почему-то, поищи, как в реальности»). An open mouth is not a black hole:
// inside it is pink to deep red, darkest only in the corners; the upper teeth show under the upper lip, off-white and
// subdued; the tongue lies at the bottom (summet.com «How to paint mouths»: «mouths are very pink», a red wash inside,
// pink at the edges; painters-online «How to paint mouths»: teeth «rarely white», soft, darks in the corners; AnimSchool
// «posing the mouth»: open — the teeth come into play, the tongue is nearly always seen, better than «a black gap»).
// Values are the screen's codes (this viewport is written in sRGB codes — see to_srgb).
uniform vec3 mouth_color : source_color = vec3(0.44, 0.14, 0.13);    // the depth of the mouth: deep red, not black
uniform vec3 mouth_rim : source_color = vec3(0.72, 0.38, 0.36);      // just inside the lips: pink
uniform vec3 mouth_teeth : source_color = vec3(0.87, 0.84, 0.77);    // the upper teeth: off-white
uniform vec3 mouth_tongue : source_color = vec3(0.76, 0.41, 0.39);   // the tongue
uniform float mouth_teeth_h = 0.26;    // the teeth's band under the upper lip (model units: 2.6 mm)
// 11.11, 12:30 (Director: «будто бы не то вышло»): the opening was a dark lens laid over the lower lip — the lip was
// gone. The lower lip now goes down with the opening: under its lower edge a band of the lips' own colour (the face's
// picture, data jaw.lip_color), lit as the face is lit.
uniform vec3 mouth_lip : source_color = vec3(0.0);
uniform float mouth_lip_h = 0.3;       // the lower lip's band (model units: 3 mm)
uniform float mouth_soft = 0.05;      // the edge's softness (model units: half a millimetre)
uniform bool debug_mouth = false;   // probe: the whole lens at full opening in green

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
	if ((mouth_open > 0.004 || debug_mouth) && mouth_shape.x > 0.0) {
		vec3 mp = (mouth_inv * INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float x = mp.x / mouth_shape.x;
		float z = mp.z + mouth_shape.w * x * x;
		if (abs(x) < 1.0 && z > -mouth_depth && z < mouth_depth * 0.6) {
			float prof = pow(1.0 - x * x, 0.75);   // the corners pinched where the lips meet
			float yl = mp.y - mouth_shape.z * x * x;
			float h = mouth_shape.y * (debug_mouth ? 1.0 : mouth_open) * prof;
			// inside the lens: + towards its middle, 0 on its edge (model units)
			float d = min(h * mouth_up_share - yl, yl + h * (1.0 - mouth_up_share));
			float soft = max(fwidth(mp.y) * 1.2, mouth_soft);
			float k = smoothstep(-soft * 0.4, soft, d);
			// across the opening: 0 at the lower lip … 1 at the upper one
			float top = h * mouth_up_share;
			float bot = -h * (1.0 - mouth_up_share);
			float v = clamp((yl - bot) / max(top - bot, 1e-4), 0.0, 1.0);
			float wide = smoothstep(0.25, 0.5, h / max(mouth_shape.y, 1e-4));   // a narrow opening shows only the dark
			// 11.11, 12:30: not a lit bowl (pink rim all round, dark in the middle) — a mouth: the depth is darkest
			// behind the upper teeth and in the corners, the tongue lies low, the wet inner side of the lower lip
			// catches the light
			vec3 inner = mouth_color * mix(1.0, 0.72, smoothstep(0.35, 0.85, v));
			inner *= 1.0 - 0.5 * smoothstep(0.5, 1.0, abs(x));
			// the tongue: a mound low in the opening, highest in the middle, darker to the sides
			float tt = 0.42 - 0.22 * x * x;
			float tongue = (1.0 - smoothstep(tt - 0.12, tt + 0.03, v)) * wide;
			inner = mix(inner, mouth_tongue * (1.0 - 0.4 * smoothstep(0.35, 0.9, abs(x))), tongue * 0.85);
			// the inner side of the lower lip: a thin wet pink band along the bottom
			float wet = (1.0 - smoothstep(0.0, max(soft * 2.5 / max(top - bot, 1e-4), 0.1), v)) * smoothstep(0.0, 0.3, 1.0 - abs(x));
			inner = mix(inner, mouth_rim, wet * 0.7);
			// the upper teeth: a band under the upper lip, its top in the lip's shadow, fading into the corners
			float tb = clamp(mouth_teeth_h / max(top - bot, 1e-4), 0.0, 0.45);
			float teeth = smoothstep(1.0 - tb - 0.06, 1.0 - tb + 0.02, v) * (1.0 - smoothstep(0.95, 1.0, v))
				* (1.0 - smoothstep(0.4, 0.75, abs(x))) * wide;
			vec3 tcol = mouth_teeth * mix(1.0, 0.62, smoothstep(1.0 - tb * 0.45, 0.98, v)) * (1.0 - 0.3 * smoothstep(0.2, 0.7, abs(x)));
			inner = mix(inner, tcol, teeth * 0.9);
			if (!debug_mouth && mouth_lip.r > 0.0) {
				// the lower lip, moved down with the opening, under it
				float dl = bot - yl;
				float lipk = smoothstep(-soft, soft, dl) * (1.0 - smoothstep(mouth_lip_h * 0.6, mouth_lip_h, dl))
					* smoothstep(0.0, mouth_lip_h * 0.6, -bot) * prof;
				vec3 lip_lit = to_srgb((to_linear(mouth_lip) * light * (1.0 - fr_env) + spec * spec_gain) * inside * gain);
				ALBEDO = mix(ALBEDO, lip_lit, lipk * 0.9);
			}
			ALBEDO = mix(ALBEDO, debug_mouth ? vec3(0.0, 1.0, 0.0) : inner, debug_mouth ? k * 0.55 : k);
			if (debug_mouth && abs(yl) < mouth_soft * 0.6) {
				ALBEDO = vec3(1.0, 0.0, 0.0);   // the lip line itself
			}
		}
	}
	if (debug_albedo || as_painted) {
		ALBEDO = a.rgb;
	}
	if (debug_flat >= 0.0) {
		ALBEDO = vec3(debug_flat);
	}
}
