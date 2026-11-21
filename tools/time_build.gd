extends SceneTree
func _init() -> void:
	for i in Tracks.THEMES.size():
		var t0 := Time.get_ticks_msec()
		var w := WorldGen.new()
		root.add_child(w)
		w.build(Tracks.THEMES[i])
		var mn := INF
		var mxr := 0.0
		print("%s: %d ms, lap %.0f m, ext %.0fx%.0f, road h %.1f..%.1f" % [Tracks.THEMES[i].name, Time.get_ticks_msec() - t0, w.N * 0.5, w.ext_x, w.ext_z, Array(w.TH).min(), Array(w.TH).max()])
		w.queue_free()
	quit()
