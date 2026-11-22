extends SceneTree
## Renders a top-down view of a track: godot --path . -s tools/aerial.gd -- --map=3 --out=/tmp/a.png
func _init() -> void:
	var mi := 3
	var out := "/tmp/aerial.png"
	var low := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): mi = int(a.substr(6))
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--low="): low = float(a.substr(6))
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
	if low > 0.0:
		# low camera just behind the start line, a little to one side
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 60.0
		var k0 := w.N - 16
		var n0 := Vector2(-w.T[k0].y, w.T[k0].x)
		var p0 := w.P[k0] + n0 * 3.0
		var k1 := 10
		cam.look_at_from_position(Vector3(p0.x, w.TH[k0] + low, p0.y), Vector3(w.P[k1].x, w.TH[k1], w.P[k1].y) + Vector3(n0.x, 0, n0.y) * 5.0, Vector3.UP)
	else:
		cam.look_at_from_position(Vector3(0, 300, 0), Vector3.ZERO, Vector3(0, 0, -1))
	cam.make_current()
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
