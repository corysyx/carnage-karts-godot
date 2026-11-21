class_name ItemModels
extends RefCounted
## Low-poly models for items in the world. Forward is -Z.

static func build(type: String) -> Node3D:
	var root := Node3D.new()
	var part := Node3D.new()
	root.add_child(part)
	match type:
		"rocket":
			Critters._mi(part, Critters._cyl(0.0, 0.2, 0.8, 8), Color("ff8a2a"), Vector3.ZERO, Vector3(-PI / 2, 0, 0), Vector3.ONE, 0.02)
			for r in [-0.5, 0.5]:
				Critters._mi(part, Critters._cyl(0.0, 0.07, 0.3, 5), Color("5cc25c"), Vector3(r * 0.2, 0.05, 0.48), Vector3(PI / 2 + 0.4, 0, r), Vector3.ONE, 0.012)
			Critters._mi(part, Critters._sphere(0.06, 6), Critters.INK, Vector3(0.08, 0.1, -0.08), Vector3.ZERO, Vector3.ONE, 0.0)
			Critters._mi(part, Critters._sphere(0.06, 6), Critters.INK, Vector3(-0.08, 0.1, -0.08), Vector3.ZERO, Vector3.ONE, 0.0)
		"saw":
			Critters._mi(part, Critters._cyl(0.5, 0.5, 0.06, 12), Color("e8e4f0"), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 0.02, true)
			Critters._mi(part, Critters._cyl(0.36, 0.36, 0.09, 12), Color("b9b2c8"), Vector3.ZERO, Vector3(0, 0.26, 0), Vector3.ONE, 0.0, true)
			Critters._mi(part, Critters._cyl(0.12, 0.12, 0.12, 8), Color("6f6482"), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 0.0)
		"mine":
			Critters._mi(part, Critters._sphere(0.32, 10), Color("5b5368"), Vector3(0, 0.32, 0), Vector3.ZERO, Vector3.ONE, 0.02)
			for i in 8:
				var a := i / 8.0 * TAU
				var d := Vector3(cos(a), 0.35 if i % 2 else -0.1, sin(a)).normalized()
				Critters._mi(part, Critters._cyl(0.0, 0.07, 0.28, 5), Color("4a4458"), Vector3(0, 0.32, 0) + d * 0.36, Vector3.ZERO, Vector3.ONE, 0.0).look_at_from_position(Vector3(0, 0.32, 0) + d * 0.36, Vector3(0, 0.32, 0) + d * 2.0, Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT)
			var light := Critters._mi(part, Critters._sphere(0.09, 8), Color("ff3355"), Vector3(0, 0.68, 0), Vector3.ZERO, Vector3.ONE, 0.0)
			light.name = "Light"
			for x in [-0.12, 0.12]:
				Critters._mi(part, Critters._sphere(0.05, 6), Critters.INK, Vector3(x, 0.38, -0.29), Vector3.ZERO, Vector3.ONE, 0.0)
		"slime":
			Critters._mi(part, Critters._sphere(0.75, 12), Color("86e65f"), Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1, 0.28, 1), 0.025)
			for x in [-0.22, 0.22]:
				Critters._mi(part, Critters._sphere(0.09, 8), Color.WHITE, Vector3(x, 0.24, -0.35), Vector3.ZERO, Vector3.ONE, 0.0)
				Critters._mi(part, Critters._sphere(0.05, 6), Critters.INK, Vector3(x, 0.25, -0.43), Vector3.ZERO, Vector3.ONE, 0.0)
	return root
