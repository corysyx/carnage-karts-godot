extends Node
## Debug helper: saves a screenshot of whatever menu is open after a delay.
## godot --path . -- --net-host --menushot=/tmp/lobby.png
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menushot="):
			out = a.substr(11)
	if out == "":
		queue_free()
		return
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
