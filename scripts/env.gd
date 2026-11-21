class_name Env
extends RefCounted
## Sky, sun, fog and the screen-space ink outline pass. Colours follow the track theme.

static var depth_ink := true
static var env: Environment
static var sky_mat: ProceduralSkyMaterial
static var sun: DirectionalLight3D

static func setup(root: Node3D) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.15
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
	apply_theme(Tracks.THEMES[0])

static func apply_theme(th: Dictionary) -> void:
	sky_mat.sky_top_color = Tracks.col(th, "sky_top")
	sky_mat.sky_horizon_color = Tracks.col(th, "sky_horizon")
	sky_mat.ground_horizon_color = Tracks.col(th, "sky_horizon")
	sky_mat.ground_bottom_color = Tracks.col(th, "far")
	env.ambient_light_color = Tracks.col(th, "ambient")
	env.fog_light_color = Tracks.col(th, "fog")
	sun.light_color = Tracks.col(th, "sun")

static func set_shadows(on: bool) -> void:
	if sun:
		sun.shadow_enabled = on
