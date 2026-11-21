class_name Kart
extends Node3D
## One racer: arcade physics, fence collision, jumps, water, laps,
## AI steering and model animation (wheels steer/spin, body rolls,
## driver leans into turns, drift slides, landing squash).

const SPD := 18.5          # top speed on road, m/s
const GRAV := 57.5
const RADIUS := 1.0

var race: Node
var world: WorldGen
var sp: Dictionary
var is_player := false
var idx := 0
var sp_idx := 0

var model: Node3D
var body: Node3D
var driver: Node3D
var head: Node3D
var wheel_fl: Node3D
var wheel_fr: Node3D
var spins: Array[Node3D] = []
var bone: Node3D
var ghost: Node3D
var shield_mesh: MeshInstance3D

var pos := Vector2()
var z := 0.0
var vz := 0.0
var on_ground := true
var a := 0.0
var speed := 0.0
var nr := Vector3()
var seg := 0
var lap := -1
var half := false
var prog := -5
var finished := false
var finish_time := -1.0
var place := 0
var ko := 0.0
var drown := false
var ko_pos := Vector3()
var spin := 0.0
var spin_a := 0.0
var invuln := 0.0
var shield := 0.0
var boost := 0.0
var items: Array = [null, null]
var sel := 0
var pending := ""
var roulette := 0.0
var item_held := 0.0
var lap_start := 0.0
var last_lap := -1.0
var best_lap := -1.0
var kills := 0
var kos := 0
var off_t := 0.0
var drift_t := 0.0       # mini-turbo charge (MK8 style tiers)
var drift_dir := 0       # -1 / +1 while drifting, 0 otherwise
var drift_tier := 0      # 0 none, 1 blue, 2 orange, 3 pink
var drift_prev := false  # drift button held last frame
var hop_t := 0.0         # time since the hop (direction can be chosen during it)
const TIER_AT := [0.0, 0.85, 1.9, 3.1]
const TIER_BOOST := [0.0, 0.5, 1.0, 1.6]
const TIER_COL := [Color("f4efe6"), Color("5ec8ff"), Color("ffa040"), Color("ff6fd8")]
var skill := 1.0
var skill_mul := 1.0
var lane_off := 0.0
var ai_t := 0.0
var stuck_t := 0.0
var stuck_rev := 0.0
var ai_drift := false
var mt_count := [0, 0, 0, 0]  # mini-turbos by tier (stats)
var steer_vis := 0.0
var drift_vis := 0.0
var squash := 0.0
var rank := 0
var anim_t := 0.0
var bloody_tyres := 0.0

static func adiff(from: float, to: float) -> float:
	var d := fmod(to - from, TAU)
	if d > PI:
		d -= TAU
	elif d < -PI:
		d += TAU
	return d

func setup(r: Node, w: WorldGen, species: Dictionary, player: bool, slot: int) -> void:
	race = r
	world = w
	sp = species
	sp_idx = Critters.SPECIES.find(species)
	is_player = player
	idx = slot
	model = Critters.build(sp)
	add_child(model)
	body = model.get_node("Body")
	driver = body.get_node("Driver")
	head = driver.get_node("Head")
	wheel_fl = model.get_node("Wheels/WheelFL")
	wheel_fr = model.get_node("Wheels/WheelFR")
	for n in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		spins.append(model.get_node("Wheels/%s/Spin" % n))
	bone = Critters.build_bone()
	bone.visible = false
	add_child(bone)
	ghost = Critters.build_ghost()
	ghost.visible = false
	race.add_child(ghost)
	shield_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.25
	sm.height = 2.5
	shield_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.88, 1.0, 0.28)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_mesh.material_override = mat
	shield_mesh.position.y = 0.75
	shield_mesh.visible = false
	add_child(shield_mesh)
	skill = 1.0 if player else [0.9, 0.94, 0.92, 0.96, 0.89][slot % 5]
	lane_off = (randf() - 0.5) * 4.0
	ai_t = randf() * 2.0

func place_on_grid(s: int, lat: float) -> void:
	var nrm := Vector2(-world.T[s].y, world.T[s].x)
	pos = world.P[s] + nrm * lat
	a = atan2(world.T[s].y, world.T[s].x)
	seg = s
	nr = world.nearest_local(pos, s, 10)
	z = world.ground(pos, nr).x
	lap = -1
	prog = -5
	sync_visual(0.0)

func forward() -> Vector2:
	return Vector2(cos(a), sin(a))

# ------------------------------------------------------------------ physics
func step(dt: float, inp: Dictionary) -> void:
	if invuln > 0.0: invuln -= dt
	if shield > 0.0: shield -= dt
	if boost > 0.0: boost -= dt
	if roulette > 0.0:
		roulette -= dt
		if roulette <= 0.0:
			roulette = 0.0
			var fs := free_slot()
			if fs >= 0:
				items[fs] = pending
				if items[sel] == null:
					sel = fs
			item_held = 0.0
			if is_player:
				Sfx.play("get")
	if ko > 0.0:
		ko -= dt
		if ko <= 0.0:
			respawn()
		return
	var thr: float = inp.thr
	var st: float = inp.steer
	if spin > 0.0:
		spin -= dt
		thr = 0.0
		st = 0.0
		spin_a += 16.0 * dt
		speed *= 1.0 - 2.6 * dt
		if spin <= 0.0:
			spin_a = 0.0
	var g0 := world.ground(pos, nr)
	var surf := int(g0.y)
	var max_s := SPD * skill_mul * float(sp.spd)
	if surf == 0:
		max_s *= 0.6
	elif surf == 2:
		max_s *= 0.35
	if boost > 0.0:
		max_s *= 1.5
		if thr <= 0.0 and spin <= 0.0:
			thr = 1.0
	if thr > 0.0:
		if speed < max_s:
			speed += minf(max_s - speed, (32.5 if boost > 0.0 else 13.0 * float(sp.acc)) * dt)
		else:
			speed -= minf(speed - max_s, 18.75 * dt)
	elif thr < 0.0:
		speed -= (27.5 if speed > 0.0 else 10.0) * dt
		speed = maxf(speed, -6.0)
	else:
		speed -= speed * 1.1 * dt
	var turn := 2.3 * float(sp.hdl) * clampf(speed / 6.25, -1.0, 1.0) * (1.0 if on_ground else 0.4)
	_drift(dt, inp, thr, st, surf)
	if drift_dir != 0:
		# Locked into the drift: the stick only tightens (into the turn) or
		# widens (away from it); you can never straighten out or turn the other way.
		var into := st * float(drift_dir)
		var tight := lerpf(0.25, 1.55, (into + 1.0) * 0.5)
		a += float(drift_dir) * 2.3 * float(sp.hdl) * tight * dt
		# the back end swings out: a little sideways slide to the outside
		var outside := Vector2(sin(a), -cos(a)) * float(drift_dir)
		pos += outside * speed * 0.07 * dt
		steer_vis += (float(drift_dir) * (0.55 + 0.35 * into) - steer_vis) * minf(1.0, 10.0 * dt)
	else:
		a += st * turn * dt
		steer_vis += (st - steer_vis) * minf(1.0, 10.0 * dt)
	drift_vis += ((float(drift_dir) * (0.42 + 0.12 * st * float(drift_dir))) - drift_vis) * minf(1.0, 9.0 * dt)
	if squash > 0.0:
		squash = maxf(0.0, squash - dt * 5.0)
	# move + fences
	var np := pos + forward() * speed * dt
	var nn := world.nearest_local(np, seg, 20)
	if absf(nn.y) > WorldGen.KLIM and not world.is_open(int(nn.x), nn.y):
		var i := int(nn.x)
		var foot := world.P[i].lerp(world.P[(i + 1) % world.N], nn.z)
		var w := (np - foot).normalized()
		np = foot + w * WorldGen.KLIM
		var v := forward() * speed
		var vn := v.dot(w)
		if vn > 0.0:
			var imp := vn / maxf(1.0, absf(speed))
			if imp > 0.8:
				speed *= -0.3
				if is_player:
					Sfx.play("bump")
					race.shake = maxf(race.shake, 0.25)
			else:
				speed *= 1.0 - imp * 0.5
				var tv := v - w * vn
				if speed > 0.0:
					a += adiff(a, atan2(tv.y, tv.x)) * 0.4
				if randf() < 0.7:
					race.gore.spark(Vector3(np.x + w.x * 0.4, z + 0.3, np.y + w.y * 0.4), Color("ffe680") if randf() < 0.5 else Color.WHITE)
				if is_player and randf() < 0.12:
					Sfx.play("bump")
		nn = world.nearest_local(np, seg, 20)
	var ng := world.ground(np, nn).x
	if ng - z > 0.8:
		speed *= -0.3
	else:
		pos = np
		nr = nn
	var gg := world.ground(pos, nr)
	var gh := gg.x
	if on_ground:
		if gh < z - 0.3:
			on_ground = false
		else:
			vz = clampf((gh - z) / maxf(dt, 0.001), -15.0, 27.5)
			z = gh
	if not on_ground:
		vz -= GRAV * dt
		z += vz * dt
		if z <= gh:
			if vz < -10.0:
				squash = minf(1.0, -vz / 35.0)
			if is_player and vz < -17.0:
				race.shake = maxf(race.shake, 0.15)
				Sfx.play("bump")
			z = gh
			on_ground = true
			vz = 0.0
	if int(gg.y) == 2 and on_ground:
		ko = 1.1
		drown = true
		ko_pos = Vector3(pos.x, z, pos.y)
		speed = 0.0
		race.gore.splash(ko_pos)
		if is_player:
			Sfx.play("splash")
			race.msg("Sploosh! Critters can't swim.", Color("9fe3ff"))
		return
	# blood on the tyres leaves red tracks
	if race.gore.blood_near(pos):
		bloody_tyres = 2.5
	if bloody_tyres > 0.0:
		bloody_tyres -= dt
		if on_ground and absf(speed) > 2.0 and randf() < 0.5:
			var side := Vector2(-sin(a), cos(a)) * 0.6
			race.gore.track(pos + side * (1.0 if randf() < 0.5 else -1.0), z, a, bloody_tyres / 2.5)
	if boost > 0.0 and randf() < 0.8:
		race.gore.spark(Vector3(pos.x, z + 0.4, pos.y) - Vector3(cos(a), 0, sin(a)) * 1.1, Color.from_hsv(randf(), 0.5, 1.0))
	if absf(nr.y) > WorldGen.HALF + 1.5:
		off_t += dt
	else:
		off_t = 0.0
	if off_t > (8.0 if is_player else 3.5):
		respawn()
	_update_seg()

## Mario Kart 8 style drift: press to hop, hold a direction to lock the drift,
## steer into the turn to charge faster. Sparks go blue -> orange -> pink;
## let go for a mini, super or ultra mini-turbo. Braking cancels it.
func _drift(dt: float, inp: Dictionary, thr: float, st: float, surf: int) -> void:
	var held: bool = inp.get("drift", false) and spin <= 0.0
	var pressed := held and not drift_prev
	drift_prev = held
	hop_t += dt
	if pressed and on_ground and speed > 5.0:
		# the hop
		on_ground = false
		vz = 6.0
		z += 0.02
		hop_t = 0.0
		squash = 0.35
		if absf(st) > 0.25:
			drift_dir = 1 if st > 0.0 else -1
			drift_t = 0.0
			drift_tier = 0
	# a direction can still be picked while in the air from the hop
	if held and drift_dir == 0 and hop_t < 0.3 and absf(st) > 0.25 and speed > 5.0:
		drift_dir = 1 if st > 0.0 else -1
		drift_t = 0.0
		drift_tier = 0
	if drift_dir == 0:
		return
	var cancel := thr < 0.0 or speed < 4.0 or spin > 0.0
	if not held or cancel:
		if not cancel and drift_tier > 0:
			boost = maxf(boost, TIER_BOOST[drift_tier])
			mt_count[drift_tier] += 1
			if is_player:
				Sfx.play("boost", 0.6 + 0.2 * drift_tier)
		drift_dir = 0
		drift_t = 0.0
		drift_tier = 0
		return
	speed *= 1.0 - 0.05 * dt
	# charge: only on the road, faster when steering into the turn
	if on_ground and surf != 0:
		var into := maxf(0.0, st * float(drift_dir))
		drift_t += dt * (1.0 + 1.1 * into)
	while drift_tier < 3 and drift_t >= TIER_AT[drift_tier + 1]:
		drift_tier += 1
		if is_player:
			Sfx.play("beep_hi" if drift_tier == 3 else "beep", 0.35)
	if on_ground and randf() < 0.85:
		var back := Vector3(cos(a), 0, sin(a)) * 0.85
		var sideways := Vector3(-sin(a), 0, cos(a)) * 0.55
		var col: Color = TIER_COL[drift_tier]
		for sgn: float in [-1.0, 1.0]:
			if drift_tier > 0 or randf() < 0.35:
				race.gore.spark(Vector3(pos.x, z + 0.12, pos.y) - back + sideways * sgn, col)

func _update_seg() -> void:
	var N := world.N
	var prev := seg
	seg = int(nr.x)
	if seg > N * 0.4 and seg < N * 0.6:
		half = true
	if prev > N * 0.75 and seg < N * 0.25:
		if lap < 0 or half:
			lap += 1
			half = false
			race.on_lap(self)
	elif prev < N * 0.25 and seg > N * 0.75:
		lap -= 1
		half = true
	prog = lap * N + seg

func respawn() -> void:
	var s := seg
	pos = world.P[s]
	nr = world.nearest_local(pos, s, 4)
	z = world.TH[s]
	vz = 0.0
	on_ground = true
	a = atan2(world.T[s].y, world.T[s].x)
	speed = 0.0
	invuln = 1.6
	ko = 0.0
	spin = 0.0
	off_t = 0.0
	drown = false
	stuck_t = 0.0
	stuck_rev = 0.0
	bone.visible = false
	ghost.visible = false
	_set_wreck(false)
	if is_player:
		race.cam_a = a

func free_slot() -> int:
	if items[0] == null:
		return 0
	if items[1] == null:
		return 1
	return -1

func cur_slot() -> int:
	if items[sel] != null:
		return sel
	if items[1 - sel] != null:
		return 1 - sel
	return -1

func cur_item() -> Variant:
	var i := cur_slot()
	return null if i < 0 else items[i]

# ------------------------------------------------------------------ AI
func ai_input(dt: float) -> Dictionary:
	ai_t -= dt
	if ai_t <= 0.0:
		ai_t = 2.0 + randf() * 3.0
		lane_off = (randf() - 0.5) * 6.2
	var N := world.N
	var look := 6 + int(maxf(0.0, speed) * 4.0 / 14.0)
	var t := (seg + look) % N
	var lo := lane_off
	for q in [t, (t + 8) % N]:
		if world.open_side[q * 2 + 1] == 1:
			lo = minf(lo, -0.75)
		if world.open_side[q * 2] == 1:
			lo = maxf(lo, 0.75)
	var target := world.P[t] + Vector2(-world.T[t].y, world.T[t].x) * lo
	var d := adiff(a, atan2(target.y - pos.y, target.x - pos.x))
	if stuck_rev > 0.0:
		stuck_rev -= dt
		return {"thr": -1.0, "steer": -1.0 if d > 0.0 else 1.0, "drift": false}
	if absf(speed) < 1.25 and race.state != "countdown":
		stuck_t += dt
		if stuck_t > 1.0:
			stuck_t = 0.0
			stuck_rev = 0.8
	else:
		stuck_t = 0.0
	# drift through proper corners, like the player would
	var ahead := (seg + 36) % N
	var bend := adiff(atan2(world.T[seg].y, world.T[seg].x), atan2(world.T[ahead].y, world.T[ahead].x))
	if drift_dir == 0:
		ai_drift = absf(bend) > 0.7 and speed > 11.0 and d * bend > 0.0 and absf(d) < 0.6 and randf() < 0.5 * skill + 0.1
	elif absf(bend) < 0.18 or bend * float(drift_dir) < 0.0 or d * float(drift_dir) < -0.2:
		ai_drift = false
	# don't slide wide off an open (lakeside) edge
	if absf(nr.y) > 3.0 and world.is_open(int(nr.x), nr.y):
		ai_drift = false
	var sv := clampf(d * 2.4, -1.0, 1.0)
	if ai_drift and drift_dir == 0:
		sv = signf(bend)
	return {"thr": 0.0 if (absf(d) > 1.2 and speed > 10.0 and not ai_drift) else 1.0, "steer": sv, "drift": ai_drift}

# ------------------------------------------------------------------ visuals
func _set_wreck(on: bool) -> void:
	driver.visible = not on
	for m in body.get_children():
		if m is MeshInstance3D:
			var mat: ShaderMaterial = m.material_override
			if not mat.has_meta("col"):
				mat.set_meta("col", mat.get_shader_parameter("albedo"))
			mat.set_shader_parameter("albedo", Color("3d3244") if on else mat.get_meta("col"))

func knock_out() -> void:
	ko = 1.9
	drown = false
	ko_pos = Vector3(pos.x, z, pos.y)
	speed = 0.0
	boost = 0.0
	drift_dir = 0
	drift_t = 0.0
	drift_tier = 0
	items = [null, null]
	roulette = 0.0
	shield = 0.0
	spin = 0.0
	kos += 1
	_set_wreck(true)
	bone.visible = race.gore_level > 0
	bone.position = Vector3(0.1, 0.62, 0.1)
	bone.rotation = Vector3(0.2, 0.7, 0.1)
	ghost.visible = true
	ghost.global_position = ko_pos

func sync_visual(dt: float) -> void:
	anim_t += dt
	if ko > 0.0:
		global_position = ko_pos
		visible = not drown
		if ghost.visible:
			ghost.global_position = ko_pos + Vector3(0, 1.0 + (1.9 - ko) * 3.0, 0)
			ghost.rotation.y += dt * 2.0
		return
	visible = not (invuln > 0.0 and int(anim_t * 16.0) % 2 == 1)
	global_position = Vector3(pos.x, z, pos.y)
	var va := a + spin_a + drift_vis
	rotation = Vector3(0, atan2(-cos(va), -sin(va)), 0)
	var bob := sin(anim_t * 30.0 + idx) * 0.025 if (on_ground and absf(speed) > 1.0) else 0.0
	body.position.y = bob
	body.rotation.z = steer_vis * 0.08 * signf(speed + 0.01)
	body.scale = Vector3(1.0 + squash * 0.12, 1.0 - squash * 0.22, 1.0 + squash * 0.12)
	driver.rotation.z = -steer_vis * 0.22
	head.rotation.z = -steer_vis * 0.12
	head.rotation.y = -steer_vis * 0.25
	wheel_fl.rotation.y = -steer_vis * 0.45
	wheel_fr.rotation.y = -steer_vis * 0.45
	for s in spins:
		s.rotation.x -= speed / 0.25 * dt
	shield_mesh.visible = shield > 0.0 and (shield > 2.0 or int(anim_t * 10.0) % 2 == 0)
