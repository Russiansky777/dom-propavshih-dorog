extends SceneTree
## I-T7: decodes imported textures (as the build ships them: BPTC etc.) to PNG — evidence of the real in-game pixels.
## godot --headless --main-pack <сборка .pck/.exe> -s tools/decode_pack_textures.gd -- res://a.png /abs/out_a.png [res://b.png /abs/out_b.png ...]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var code := 0
	for k in range(0, args.size() - 1, 2):
		var tex := load(args[k]) as Texture2D
		if tex == null:
			push_error("cannot load " + args[k]); code = 1; continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.save_png(args[k + 1])
		print("decoded ", args[k], " ", img.get_size(), " -> ", args[k + 1])
	quit(code)
