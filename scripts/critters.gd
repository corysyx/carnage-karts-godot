class_name Critters
extends RefCounted
## The six racers and their low-poly 3D models, built from simple shapes.
## Kart forward is -Z. Named child nodes are animated by Kart:
##   Body (roll/squash) > WheelFL/WheelFR (steer pivots), Wheels/*, Driver (lean)

const SPECIES := [
	{"id": "bunny", "name": "Bun-Bun", "fur": Color("f7f2ee"), "fur2": Color("ffb3cf"), "kart": Color("ff6fa8"), "kart2": Color("c94681")},
	{"id": "panda", "name": "Pandy", "fur": Color("ffffff"), "fur2": Color("2b2633"), "kart": Color("4fd1a5"), "kart2": Color("2a8f6e")},
	{"id": "fox", "name": "Foxy", "fur": Color("ff8a3d"), "fur2": Color("fff3e6"), "kart": Color("ffd23f"), "kart2": Color("c99a12")},
	{"id": "frog", "name": "Hopper", "fur": Color("7bd65b"), "fur2": Color("e9ffd9"), "kart": Color("5aa7ff"), "kart2": Color("2f6fc4")},
	{"id": "pig", "name": "Oinkers", "fur": Color("ffb8c9"), "fur2": Color("ff8fab"), "kart": Color("a17cff"), "kart2": Color("6e4ed1")},
	{"id": "kitty", "name": "Mochi", "fur": Color("bdb6cf"), "fur2": Color("ffffff"), "kart": Color("ff5a5a"), "kart2": Color("b83232")},
]
const INK := Color("2a1830")

static func _mi(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, outline := 0.022, flat := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = WorldGen.toon(col, flat, outline)
	m.position = pos
	m.rotation = rot
	m.scale = scl
	parent.add_child(m)
	return m

static func _sphere(r: float, seg := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(4, seg / 2)
	return s

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func _cyl(rt: float, rb: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 3
	return c

## Builds a racer: kart + critter driver.
static func build(sp: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var kc: Color = sp.kart
	var k2: Color = sp.kart2
	# chassis
	_mi(body, _box(1.06, 0.26, 1.62), kc, Vector3(0, 0.36, 0.02))
	_mi(body, _box(0.9, 0.16, 0.5), kc.lightened(0.15), Vector3(0, 0.38, -0.86), Vector3(-0.25, 0, 0))
	_mi(body, _box(1.12, 0.12, 0.16), k2, Vector3(0, 0.27, -1.0))
	_mi(body, _box(0.18, 0.03, 1.5), Color("fff8fc"), Vector3(0, 0.5, 0.0), Vector3.ZERO, Vector3.ONE, 0.0)
	_mi(body, _box(0.86, 0.36, 0.14), k2, Vector3(0, 0.64, 0.6))       # seat back
	_mi(body, _box(1.16, 0.08, 0.28), k2, Vector3(0, 0.86, 0.82))      # spoiler
	_mi(body, _box(0.08, 0.3, 0.08), k2, Vector3(-0.4, 0.68, 0.82))
	_mi(body, _box(0.08, 0.3, 0.08), k2, Vector3(0.4, 0.68, 0.82))
	for x in [-0.28, 0.28]:
		_mi(body, _cyl(0.07, 0.07, 0.22, 8), Color("9890aa"), Vector3(x, 0.36, 0.9), Vector3(PI / 2, 0, 0), Vector3.ONE, 0.015)
		_mi(body, _sphere(0.07, 8), Color("fff7b8"), Vector3(x * 1.3, 0.38, -0.98), Vector3.ZERO, Vector3.ONE, 0.0)
		_mi(body, _box(0.14, 0.06, 0.03), Color("ff4466"), Vector3(x * 1.4, 0.42, 0.84), Vector3.ZERO, Vector3.ONE, 0.0)
	# steering wheel
	var tw := TorusMesh.new()
	tw.inner_radius = 0.1
	tw.outer_radius = 0.15
	tw.rings = 12
	tw.ring_segments = 6
	_mi(body, tw, Color("3a2f48"), Vector3(0, 0.74, -0.32), Vector3(-1.1, 0, 0), Vector3.ONE, 0.0)
	_mi(body, _cyl(0.025, 0.025, 0.32, 6), Color("3a2f48"), Vector3(0, 0.62, -0.42), Vector3(-1.1, 0, 0), Vector3.ONE, 0.0)
	# wheels
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	root.add_child(wheels)
	var tyre := _cyl(0.24, 0.24, 0.24, 12)
	var hub := _cyl(0.11, 0.11, 0.26, 8)
	for w in [["WheelFL", Vector3(-0.62, 0.24, -0.58)], ["WheelFR", Vector3(0.62, 0.24, -0.58)], ["WheelRL", Vector3(-0.64, 0.26, 0.6)], ["WheelRR", Vector3(0.64, 0.26, 0.6)]]:
		var piv := Node3D.new()
		piv.name = w[0]
		piv.position = w[1]
		wheels.add_child(piv)
		var spin := Node3D.new()
		spin.name = "Spin"
		piv.add_child(spin)
		var big: float = 1.1 if String(w[0]).begins_with("WheelR") else 1.0
		_mi(spin, tyre, Color("2d2438"), Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3(big, 1, big), 0.02)
		_mi(spin, hub, Color("d8d0e6"), Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3(big, 1, big), 0.0)
		_mi(spin, _box(0.27, 0.05, 0.3), Color("4a3f5a"), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, big), 0.0)
	# driver
	var drv := Node3D.new()
	drv.name = "Driver"
	drv.position = Vector3(0, 0.5, 0.25)
	body.add_child(drv)
	_mi(drv, _sphere(0.27, 10), sp.fur, Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 1.05, 0.9))
	for x in [-0.17, 0.17]:
		_mi(drv, _sphere(0.085, 8), sp.fur, Vector3(x, 0.26, -0.52), Vector3.ZERO, Vector3.ONE, 0.015)
		_mi(drv, _capsule(0.06, 0.4), sp.fur, Vector3(x * 0.85, 0.24, -0.33), Vector3(PI / 2 - 0.15, 0, 0), Vector3.ONE, 0.015)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.66, 0)
	drv.add_child(head)
	_build_head(head, sp)
	return root

static func _build_head(h: Node3D, sp: Dictionary) -> void:
	var id: String = sp.id
	var fur: Color = sp.fur
	var f2: Color = sp.fur2
	var r := 0.36
	var hs := Vector3(1.12, 1.0, 1.0) if id == "frog" else Vector3.ONE
	_mi(h, _sphere(r, 14), fur, Vector3.ZERO, Vector3.ZERO, hs, 0.025)
	var eye_y := 0.03
	var eye_x := 0.13
	var eye_z := -r * 0.9
	match id:
		"bunny":
			for x in [-0.13, 0.13]:
				var ear := _mi(h, _capsule(0.085, 0.62), fur, Vector3(x, r + 0.24, 0.02), Vector3(0, 0, -x * 1.1), Vector3.ONE, 0.02)
				_mi(ear, _capsule(0.045, 0.44), f2, Vector3(0, 0.02, -0.05), Vector3.ZERO, Vector3(1, 1, 0.5), 0.0)
			_mi(h, _sphere(0.04, 8), Color("ff7fa8"), Vector3(0, -0.04, -r * 0.99), Vector3.ZERO, Vector3.ONE, 0.0)
		"panda":
			for x in [-0.25, 0.25]:
				_mi(h, _sphere(0.1, 8), f2, Vector3(x, r * 0.78, 0.0), Vector3.ZERO, Vector3(1, 1, 0.7), 0.015)
				_mi(h, _sphere(0.085, 8), f2, Vector3(x * 0.55, eye_y, -r * 0.86), Vector3(0, 0, x * 2.0), Vector3(1, 1.3, 0.5), 0.0)
			_mi(h, _sphere(0.045, 8), Color("2b2633"), Vector3(0, -0.06, -r * 0.99), Vector3.ZERO, Vector3(1.2, 0.8, 1), 0.0)
		"fox", "kitty":
			var ec := fur
			var ic := Color("3a2230") if id == "fox" else Color("ffb3cf")
			for x in [-0.2, 0.2]:
				var ear := _mi(h, _cyl(0.0, 0.13, 0.3, 4), ec, Vector3(x, r * 0.85, 0.0), Vector3(0, PI / 4, -x * 1.4), Vector3(1, 1, 0.55), 0.018)
				_mi(ear, _cyl(0.0, 0.08, 0.2, 4), ic, Vector3(0, -0.02, -0.035), Vector3.ZERO, Vector3(1, 1, 0.5), 0.0)
			var snout := _mi(h, _sphere(0.17, 10), f2, Vector3(0, -0.1, -r * 0.78), Vector3.ZERO, Vector3(1.15 if id == "fox" else 1.0, 0.75, 0.9 if id == "fox" else 0.6), 0.015)
			snout.name = "Snout"
			_mi(h, _sphere(0.045, 8), INK if id == "fox" else Color("ff7fa8"), Vector3(0, -0.04, -r - (0.1 if id == "fox" else 0.0)), Vector3.ZERO, Vector3.ONE, 0.0)
			if id == "kitty":
				for x in [-1.0, 1.0]:
					for yy in [-0.07, -0.12]:
						_mi(h, _box(0.22, 0.008, 0.008), INK, Vector3(x * 0.2, yy, -r * 0.85), Vector3(0, 0, x * (yy + 0.1) * 2.0), Vector3.ONE, 0.0)
		"frog":
			eye_x = 0.17
			eye_y = r * 0.78
			eye_z = -r * 0.45
			for x in [-0.17, 0.17]:
				_mi(h, _sphere(0.13, 10), fur, Vector3(x, r * 0.72, -0.08), Vector3.ZERO, Vector3.ONE, 0.018)
				_mi(h, _sphere(0.095, 10), Color.WHITE, Vector3(x, r * 0.76, -0.16), Vector3.ZERO, Vector3.ONE, 0.0)
			_mi(h, _capsule(0.018, 0.34), INK, Vector3(0, -0.08, -r * 0.93), Vector3(0, 0, PI / 2), Vector3.ONE, 0.0)
		"pig":
			for x in [-0.2, 0.2]:
				_mi(h, _cyl(0.0, 0.12, 0.24, 4), f2, Vector3(x, r * 0.8, 0.02), Vector3(0.5, PI / 4, -x * 2.2), Vector3(1, 1, 0.5), 0.018)
			_mi(h, _cyl(0.12, 0.12, 0.12, 10), f2, Vector3(0, -0.06, -r * 0.95), Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.8), 0.015)
			for x in [-0.045, 0.045]:
				_mi(h, _sphere(0.025, 6), Color("b34d6b"), Vector3(x, -0.06, -r * 0.95 - 0.06), Vector3.ZERO, Vector3.ONE, 0.0)
	# eyes, glints and blush
	for x in [-eye_x, eye_x]:
		var e := _mi(h, _sphere(0.055 if id != "panda" else 0.04, 8), INK, Vector3(x, eye_y, eye_z - (0.05 if id == "frog" else 0.0)), Vector3.ZERO, Vector3(1, 1.15, 0.6), 0.0)
		_mi(e, _sphere(0.018, 6), Color.WHITE, Vector3(-0.015, 0.02, -0.035), Vector3.ZERO, Vector3.ONE, 0.0)
		if id != "frog":
			_mi(h, _sphere(0.06, 8), Color("ff8fb3"), Vector3(x * 1.75, -0.06, -r * 0.8), Vector3(0, -x * 3.0, 0), Vector3(1, 0.6, 0.3), 0.0)

## Charred wreck pieces + bone, shown while a racer is knocked out.
static func build_bone() -> Node3D:
	var b := Node3D.new()
	_mi(b, _capsule(0.05, 0.5), Color("fff7e8"), Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3.ONE, 0.015)
	for x in [-0.25, 0.25]:
		for z in [-0.05, 0.05]:
			_mi(b, _sphere(0.065, 8), Color("fff7e8"), Vector3(x, 0, z), Vector3.ZERO, Vector3.ONE, 0.012)
	return b

static func build_ghost() -> Node3D:
	var g := Node3D.new()
	_mi(g, _capsule(0.3, 0.9), Color("f6f2ff"), Vector3(0, 0.45, 0), Vector3.ZERO, Vector3.ONE, 0.02)
	var halo := TorusMesh.new()
	halo.inner_radius = 0.18
	halo.outer_radius = 0.24
	_mi(g, halo, Color("ffd84a"), Vector3(0, 1.05, 0), Vector3.ZERO, Vector3.ONE, 0.0)
	for x in [-0.1, 0.1]:
		_mi(g, _box(0.1, 0.02, 0.02), INK, Vector3(x, 0.62, -0.29), Vector3(0, 0, 0.785), Vector3.ONE, 0.0)
		_mi(g, _box(0.1, 0.02, 0.02), INK, Vector3(x, 0.62, -0.29), Vector3(0, 0, -0.785), Vector3.ONE, 0.0)
	return g
