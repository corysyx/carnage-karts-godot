class_name Env
extends RefCounted
## Sky, sun, fog and the screen-space ink outline pass.


static var depth_ink := true

static func setup(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("5fb0ff")
	sm.sky_horizon_color = Color("ffe0f3")
	sm.ground_horizon_color = Color("ffe0f3")
	sm.ground_bottom_color = Color("b6e39a")
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9c0ff")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color("ffe0f3")
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color("fff6e8")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	root.add_child(sun)
	if depth_ink:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		q.mesh = qm
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/ink_post.gdshader")
		m.render_priority = 100
		q.material_override = m
		q.extra_cull_margin = 16384.0
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(q)
