class_name Gore
extends Node3D
## Particles and decals: blood droplets, fur chunks, eyeballs, sparks,
## confetti, fire, water splashes, and blood pools / tyre tracks that stay
## on the ground for the rest of the race. Everything is drawn with a few
## MultiMeshes so it stays cheap on phones.

const MAX_P := 900
const MAX_D := 1400
const BLOOD := [Color("be0a18"), Color("96061a"), Color("dc1e28"), Color("78040e")]
const CONF := [Color("ff6fa8"), Color("ffe36e"), Color("6edcff"), Color("a0ff8c"), Color("c896ff")]

var race: Node
var world: WorldGen
var level := 1
# particle state (struct of arrays)
var p_pos := PackedVector3Array()
var p_vel := PackedVector3Array()
var p_life := PackedFloat32Array()
var p_size := PackedFloat32Array()
var p_type := PackedByteArray()   # 0 blood, 1 gib, 2 eye, 3 spark, 4 confetti, 5 fire, 6 splash
var p_col := PackedColorArray()
var count := 0
var mm_cube: MultiMesh
var mm_ball: MultiMesh
var mm_dec: MultiMesh
var dec_n := 0
var dec_cells := {}

func setup(r: Node, w: WorldGen) -> void:
	race = r
	world = w
	p_pos.resize(MAX_P); p_vel.resize(MAX_P); p_life.resize(MAX_P); p_size.resize(MAX_P); p_type.resize(MAX_P); p_col.resize(MAX_P)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var ball := SphereMesh.new()
	ball.radius = 0.5; ball.height = 1.0; ball.radial_segments = 8; ball.rings = 4
	mm_cube = _mm(cube, MAX_P, true)
	mm_ball = _mm(ball, 64, true)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0; disc.bottom_radius = 1.0; disc.height = 0.01; disc.radial_segments = 10; disc.rings = 1
	mm_dec = _mm(disc, MAX_D, false)

func _mm(mesh: Mesh, n: int, lit: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	if not lit:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 500.0
	add_child(mi)
	return mm

func reset() -> void:
	count = 0
	dec_n = 0
	dec_cells.clear()
	mm_dec.visible_instance_count = 0

func _add(p: Vector3, v: Vector3, type: int, col: Color, size: float, life: float) -> void:
	if count >= MAX_P:
		return
	p_pos[count] = p; p_vel[count] = v; p_type[count] = type; p_col[count] = col; p_size[count] = size; p_life[count] = life
	count += 1

func spark(p: Vector3, col: Color) -> void:
	_add(p, Vector3(randf_range(-2, 2), randf_range(0, 2.5), randf_range(-2, 2)), 3, col, 0.1, 0.3)

func sparkle(p: Vector3, n: int, cols: Array = CONF) -> void:
	for i in n:
		var a := randf() * TAU
		var s := randf_range(2.5, 7.5)
		_add(p, Vector3(cos(a) * s, randf_range(-3, 7), sin(a) * s), 3, cols[i % cols.size()], 0.14, randf_range(0.4, 0.7))

func explosion(p: Vector3, n := 26) -> void:
	for i in n:
		var a := randf() * TAU
		var s := randf() * 10.0
		_add(p, Vector3(cos(a) * s, randf() * 10.0, sin(a) * s), 5, [Color("ffe65a"), Color("ff963c"), Color("ff503c")][i % 3], randf_range(0.25, 0.6), randf_range(0.35, 0.7))

func splash(p: Vector3) -> void:
	for i in 30:
		var a := randf() * TAU
		var s := randf() * 7.0
		_add(p + Vector3(0, 0.3, 0), Vector3(cos(a) * s, randf_range(10, 25), sin(a) * s), 6, Color("c8ebff"), 0.22, 1.5)

## The big one: a racer gets splattered.
func splat(p: Vector3, sp: Dictionary, dir_a: float) -> void:
	if level == 0:
		for i in 60:
			var a := randf() * TAU
			var s := randf_range(2.5, 14.0)
			_add(p, Vector3(cos(a) * s, randf_range(8, 28), sin(a) * s), 4, CONF[i % CONF.size()], 0.2, 2.4)
		return
	var m := 2.2 if level == 2 else 1.0
	var d := Vector3(cos(dir_a), 0, sin(dir_a))
	for i in int(80 * m):
		var a := randf() * TAU
		var s := randf() * 14.0
		_add(p, Vector3(cos(a) * s, randf_range(5, 28), sin(a) * s) + d * 6.0, 0, BLOOD[randi() % 4], randf_range(0.12, 0.28), 4.0)
	for i in int(30 * m):
		var a := dir_a + randf_range(-0.45, 0.45)
		var s := randf_range(12, 32)
		_add(p, Vector3(cos(a) * s, randf_range(2, 10), sin(a) * s), 0, BLOOD[randi() % 4], randf_range(0.12, 0.2), 4.0)
	for i in int(7 * m):
		var a := randf() * TAU
		var s := randf_range(4, 15)
		var col: Color = [sp.fur2, sp.fur, sp.kart][i % 3]
		_add(p, Vector3(cos(a) * s, randf_range(12, 35), sin(a) * s), 1, col, randf_range(0.3, 0.6), 9.0)
	for i in (4 if level == 2 else 2):
		var a := randf() * TAU
		_add(p, Vector3(cos(a) * 6.0, randf_range(18, 30), sin(a) * 6.0), 2, Color.WHITE, 0.28, 9.0)
	if level == 2:
		for i in 4:
			var a := randf() * TAU
			_add(p, Vector3(cos(a) * 7.0, randf_range(15, 28), sin(a) * 7.0), 1, Color("fff7e8"), 0.35, 9.0)
	stain(Vector2(p.x, p.z), p.y, 1.1 * sqrt(m), 1.0)
	for i in int(5 * m):
		stain(Vector2(p.x + randf_range(-2.5, 2.5), p.z + randf_range(-2.5, 2.5)), p.y, randf_range(0.35, 0.75), 0.9)

func stain(xz: Vector2, y: float, r: float, strength: float) -> void:
	if level == 0:
		return
	var nr := world.nearest_global(xz, 10.0)
	var gy := y
	if nr.x >= 0:
		gy = world.ground(xz, nr).x
	else:
		gy = world.terrain_h(xz.x, xz.y)
	var k := dec_n % MAX_D
	var col: Color = BLOOD[randi() % 4].darkened(randf() * 0.2)
	col.a = 1.0
	var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(r * randf_range(0.8, 1.25), 1, r * randf_range(0.6, 1.0)))
	mm_dec.set_instance_transform(k, Transform3D(b, Vector3(xz.x, gy + 0.03 + (k % 7) * 0.002, xz.y)))
	mm_dec.set_instance_color(k, col.lerp(Color("5a0610"), 1.0 - strength))
	dec_n += 1
	mm_dec.visible_instance_count = mini(dec_n, MAX_D)
	if strength > 0.5:
		dec_cells[Vector2i(floori(xz.x), floori(xz.y))] = true

func track(xz: Vector2, y: float, a: float, s: float) -> void:
	if level == 0:
		return
	var k := dec_n % MAX_D
	var b := Basis(Vector3.UP, -a).scaled(Vector3(0.22, 1, 0.12))
	mm_dec.set_instance_transform(k, Transform3D(b, Vector3(xz.x, y + 0.035, xz.y)))
	mm_dec.set_instance_color(k, Color("8a0a14").lerp(Color("5a1018"), 1.0 - s))
	dec_n += 1
	mm_dec.visible_instance_count = mini(dec_n, MAX_D)

func blood_near(xz: Vector2) -> bool:
	return dec_cells.has(Vector2i(floori(xz.x), floori(xz.y)))

func _process(dt: float) -> void:
	if race == null or race.paused:
		return
	dt = minf(dt, 0.05)
	var i := count - 1
	while i >= 0:
		p_life[i] -= dt
		if p_life[i] <= 0.0:
			_kill(i)
			i -= 1
			continue
		var t := p_type[i]
		var pp := p_pos[i]
		var vv := p_vel[i]
		if t == 3 or t == 5:
			pp += vv * dt
			vv *= 1.0 - 2.5 * dt
			if t == 5:
				vv.y += 10.0 * dt
			p_pos[i] = pp
			p_vel[i] = vv
			i -= 1
			continue
		vv.y -= 57.5 * dt
		pp += vv * dt
		var gy := maxf(world.terrain_h(pp.x, pp.z), WorldGen.WATER)
		if pp.y < gy + 1.2:
			# close to the ground: check for road (which sits above the terrain under it)
			var nr := world.nearest_global(Vector2(pp.x, pp.z), WorldGen.WALL_OUT + 1.0)
			if nr.x >= 0:
				gy = maxf(world.ground(Vector2(pp.x, pp.z), nr).x, WorldGen.WATER)
		if t == 1 and pp.y > gy + 0.2 and level > 0 and randf() < 0.35:
			_add(pp, Vector3.ZERO, 0, BLOOD[1], 0.12, 3.0)
		if pp.y <= gy:
			if t == 0:
				stain(Vector2(pp.x, pp.z), gy, p_size[i] * 1.4 + 0.08, 0.8)
				_kill(i)
				i -= 1
				continue
			if t == 6:
				_kill(i)
				i -= 1
				continue
			pp.y = gy
			if vv.y < -6.0:
				vv.y *= -0.35
				vv.x *= 0.6
				vv.z *= 0.6
				if t == 1 or t == 2:
					stain(Vector2(pp.x, pp.z), gy, 0.32, 0.9)
			else:
				vv = Vector3(vv.x * 0.85, 0.0, vv.z * 0.85)
		p_pos[i] = pp
		p_vel[i] = vv
		i -= 1
	# upload
	var nc := 0
	var nb := 0
	for j in count:
		var s := p_size[j]
		var t := p_type[j]
		if t == 3 or t == 4 or t == 5:
			s *= clampf(p_life[j] * 3.0, 0.2, 1.0)
		var xf := Transform3D(Basis().scaled(Vector3(s, s, s)), p_pos[j])
		if t == 2 and nb < 64:
			mm_ball.set_instance_transform(nb, xf)
			mm_ball.set_instance_color(nb, Color.WHITE)
			nb += 1
		else:
			mm_cube.set_instance_transform(nc, xf)
			mm_cube.set_instance_color(nc, p_col[j])
			nc += 1
	mm_cube.visible_instance_count = nc
	mm_ball.visible_instance_count = nb

func _kill(i: int) -> void:
	count -= 1
	if i != count:
		p_pos[i] = p_pos[count]; p_vel[i] = p_vel[count]; p_life[i] = p_life[count]
		p_size[i] = p_size[count]; p_type[i] = p_type[count]; p_col[i] = p_col[count]
