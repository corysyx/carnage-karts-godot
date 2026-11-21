extends SceneTree
## Renders a top-down view of a track: godot --path . -s tools/aerial.gd -- --map=3 --out=/tmp/a.png
func _init() -> void:
	var mi := 3
	var out := "/tmp/aerial.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): mi = int(a.substr(6))
		if a.begins_with("--out="): out = a.substr(6)
	var holder := Node3D.new()
	root.add_child(holder)
	Env.setup(holder)
	var w := WorldGen.new()
	holder.add_child(w)
	w.build(Tracks.THEMES[mi])
	Env.apply_theme(Tracks.THEMES[mi])
	Env.env.fog_enabled = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = w.map_half * 2.0 + 20.0
	cam.far = 1000.0
	holder.add_child(cam)
	await process_frame
	cam.look_at_from_position(Vector3(0, 300, 0), Vector3.ZERO, Vector3(0, 0, -1))
	cam.make_current()
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
