extends Node3D
## Game flow: menu -> countdown -> race -> results. Owns the racers, camera,
## item boxes, projectiles, and wires up HUD, gore and sound.

const ITEMS := ["rocket", "saw", "mine", "slime", "boost", "shield"]
const ITEM_NAME := {"rocket": "Carrot Rocket", "saw": "Buzz Saw", "mine": "Spike Mine", "slime": "Slime Puddle", "boost": "Sugar Rush", "shield": "Bubble Shield"}
const KILL_LINES := ["turned you into jam!", "popped you like a juice box!", "made a critter smoothie out of you!", "sent you to the big meadow in the sky!"]
const SPLAT_LINES := ["SPLAT! You turned {n} into jam!", "SQUISH! {n} is now road paint!", "KABLOOEY! Bye bye, {n}!", "{n} went everywhere!"]
const MODES := ["quick", "gp", "tt"]
const MODE_NAME := {"quick": "Quick Race", "gp": "Grand Prix", "tt": "Time Trial"}
const GP_POINTS := [10, 8, 6, 4, 2, 1]
const DIFF_NAME := ["Easy", "Normal", "Hard"]
const DIFF_MUL := [0.9, 1.0, 1.07]

var world: WorldGen
var gore: Gore
var hud: Hud
var cam: Camera3D
var racers: Array[Kart] = []
var order: Array[Kart] = []
var player: Kart
var projectiles: Array[Dictionary] = []
var boxes: Array[Dictionary] = []
var state := "menu"
var paused := false
var t := 0.0
var race_time := 0.0
var cd := 0.0
var go_t := 0.0
var fin_t := 0.0
var finish_count := 0
var last_num := 4
var gas_press_cd := 9.0
var shake := 0.0
var hit_flash := 0.0
var cam_a := 0.0
var cam_h := 5.0
var selected := 0
var gore_level := 1
var msgs: Array[Dictionary] = []
var item_pressed := false
var aim := 0
var touch_steer := 0.0
var touch_brake := false
var touch_drift := false
var settings := ConfigFile.new()
var autotest := false
var shots: Array = []
var shot_dir := ""
# modes and options
var mode := "quick"
var map_idx := 0
var loaded_map := -1
var laps := 3
var difficulty := 1
var gp_round := 0
var gp_points := [0, 0, 0, 0, 0, 0]      # by species index
var gp_last: Array = []                   # last race: [{sp_idx, place, pts}]
var tt_record := false
var menu_view := "orbit"                  # "orbit" (track) or "garage" (character showcase)
var net: Net
var net_roster: Array = []                 # online: [[sp_idx, owner net id], ...] per grid slot
var net_diff := 1
var pid_n := 0

func _ready() -> void:
	randomize()
	settings.load("user://settings.cfg")
	gore_level = settings.get_value("game", "gore", 1)
	selected = settings.get_value("game", "critter", 0)
	laps = settings.get_value("game", "laps", 3)
	difficulty = settings.get_value("game", "difficulty", 1)
	map_idx = settings.get_value("game", "map", 0)
	Env.setup(self)
	Env.set_shadows(settings.get_value("video", "shadows", true))
	add_child(Sfx.new())
	net = Net.new()
	net.race = self
	add_child(net)
	Sfx.volume = settings.get_value("audio", "volume", 1.0)
	gore = Gore.new()
	add_child(gore)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.far = 600.0
	add_child(cam)
	load_map(map_idx)
	hud = Hud.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(hud)
	hud.setup(self)
	var web_demo := OS.has_feature("web") and str(JavaScriptBridge.eval("location.hash", true)) == "#demo"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shot_dir = arg.substr(8)
			shots = [2.0, 9.0, 18.0, 30.0, 45.0, 60.0]
		if arg.begins_with("--map="):
			load_map(int(arg.substr(6)))
		if arg.begins_with("--mode="):
			mode = arg.substr(7)
	var uargs := OS.get_cmdline_user_args()
	if not OS.has_feature("web"):
		for a in uargs:
			if a.begins_with("--menushot="):
				add_child(load("res://tools/lobbyshot.gd").new())
	if OS.has_feature("web"):
		# test hooks: ?nettest=host or ?nettest=JOINCODE (runs AI-driven, logs to console)
		var nt := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('nettest') || ''", true))
		if nt != "" and nt != "null":
			uargs = ["--autotest", "--net-host" if nt == "host" else "--net-join=" + nt]
			Env.set_shadows(false)
			hud.set_aa(false)
			hud.set_crt(false)
			get_viewport().scaling_3d_scale = 0.4
			var mp := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('map') || ''", true))
			if mp != "" and mp != "null":
				load_map(int(mp))
	if "--autotest" in uargs:
		autotest = true
	for arg in uargs:
		if arg == "--net-host":
			net.host()
			hud.show_screen("lobby")
			return
		if arg.begins_with("--net-join="):
			net.join(arg.substr(11))
			hud.show_screen("lobby")
			return
	if autotest or web_demo:
		autotest = true
		begin_mode(mode)
	elif OS.has_feature("web"):
		# opened from an invite link: ?join=CODE
		var jc := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('join') || ''", true))
		if jc.length() == 4:
			JavaScriptBridge.eval("history.replaceState(null, '', location.pathname)", true)
			net.join(jc)
			hud.show_screen("lobby")

func save_settings() -> void:
	settings.set_value("game", "critter", selected)
	settings.set_value("game", "gore", gore_level)
	settings.set_value("game", "laps", laps)
	settings.set_value("game", "difficulty", difficulty)
	settings.set_value("game", "map", map_idx)
	settings.save("user://settings.cfg")

# ------------------------------------------------------------------ maps
func load_map(i: int) -> void:
	map_idx = clampi(i, 0, Tracks.THEMES.size() - 1)
	if loaded_map == map_idx and world != null:
		return
	for p in projectiles:
		p.node.queue_free()
	projectiles.clear()
	for b in boxes:
		b.node.queue_free()
	boxes.clear()
	if world:
		for k in racers:
			k.ghost.queue_free()
			k.queue_free()
		racers.clear()
		world.queue_free()
	var t0 := Time.get_ticks_msec()
	world = WorldGen.new()
	add_child(world)
	world.build(Tracks.THEMES[map_idx])
	if autotest:
		print("map %s built in %d ms (lap %.0f m)" % [Tracks.THEMES[map_idx].name, Time.get_ticks_msec() - t0, world.N * WorldGen.SPACING])
	Env.apply_theme(Tracks.THEMES[map_idx])
	if gore.world == null:
		gore.setup(self, world)
	gore.world = world
	gore.level = gore_level
	gore.reset()
	_build_boxes()
	loaded_map = map_idx
	_spawn_racers(true)

func online() -> bool:
	return net != null and net.in_race

func kart_by_slot(i: int) -> Kart:
	for k in racers:
		if k.idx == i:
			return k
	return null

func theme() -> Dictionary:
	return Tracks.THEMES[map_idx]

# ------------------------------------------------------------------ setup
func _spawn_racers(menu: bool) -> void:
	for k in racers:
		k.ghost.queue_free()
		k.queue_free()
	racers.clear()
	var others: Array = []
	for i in Critters.SPECIES.size():
		if i != selected:
			others.append(i)
	others.shuffle()
	if not menu and online():
		_spawn_online()
		return
	var solo := mode == "tt" and not menu
	for slot in 6:
		var is_p := slot == 5
		if solo and not is_p:
			continue
		var k := Kart.new()
		add_child(k)
		var sp: Dictionary = Critters.SPECIES[selected if is_p else others[slot]]
		k.setup(self, world, sp, is_p, slot)
		var gs := 0 if solo else slot
		var s := (world.N - 5 - gs * 4 + world.N) % world.N
		k.place_on_grid(s, 0.0 if solo else (1.75 if slot % 2 else -1.75))
		racers.append(k)
		if is_p:
			player = k
	order = racers.duplicate()
	for i in order.size():
		order[i].rank = i
	if not menu:
		cam_a = player.a

func _spawn_online() -> void:
	for slot in 6:
		var sp_i: int = net_roster[slot][0]
		var owner: int = net_roster[slot][1]
		var mine := owner == net.my_id
		var k := Kart.new()
		add_child(k)
		k.setup(self, world, Critters.SPECIES[sp_i], mine, slot)
		k.net_owner = owner
		k.puppet = not (mine or (owner == 0 and net.is_host))
		k.place_on_grid((world.N - 5 - slot * 4 + world.N) % world.N, 1.75 if slot % 2 else -1.75)
		racers.append(k)
		if mine:
			player = k
	order = racers.duplicate()
	for i in order.size():
		order[i].rank = i
	cam_a = player.a

## Online: the host started a race.
func start_online(map: int, n_laps: int, roster: Array, diff: int) -> void:
	paused = false
	hud.show_pause(false)
	mode = "quick"
	laps = n_laps
	net_diff = diff
	net_roster = roster
	load_map(map)
	start_race()

## Online: the host went back to the lobby.
func net_to_lobby() -> void:
	state = "menu"
	paused = false
	hud.results.visible = false
	hud.show_pause(false)
	for p in projectiles:
		p.node.queue_free()
	projectiles.clear()
	gore.reset()
	_spawn_racers(true)
	hud.show_screen("lobby", false)

## Online: a friend dropped out mid-race; the host's AI takes their kart.
func net_player_left(id: int) -> void:
	for k in racers:
		if k.net_owner == id:
			k.net_owner = 0
			k.puppet = false
			k.has_net = false
			k.nr = world.nearest_local(k.pos, k.seg, 10)
			k.half = k.seg > world.N * 0.4
			k.vz = 0.0
			msg(net.name_of(id) + " left. A critter took the wheel.", Color("9fe3ff"))

func on_net_failed(why: String, was_racing: bool) -> void:
	if was_racing or state != "menu":
		hud.to_menu()
		msg(why, Color("ff8a9a"), 4.0)
	hud.on_net_status(why)

func _build_boxes() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.9, 0.9)
	for spot in world.box_spots:
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = WorldGen.toon(Color.WHITE, false, 0.04)
		n.add_child(mi)
		var lbl := Label3D.new()
		lbl.text = "?"
		lbl.font_size = 96
		lbl.outline_size = 18
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = 0.008
		lbl.no_depth_test = false
		lbl.modulate = Color.WHITE
		lbl.outline_modulate = Color("2a1830")
		n.add_child(lbl)
		add_child(n)
		boxes.append({"node": n, "mesh": mi, "pos": spot + Vector3(0, 1.0, 0), "active": true, "t": 0.0, "ph": randf() * 6.0})

## Begin a mode from the menus. For Grand Prix this starts round 1.
func begin_mode(m: String) -> void:
	mode = m
	if mode == "gp":
		gp_round = 0
		gp_points = [0, 0, 0, 0, 0, 0]
		load_map(0)
	start_race()

func next_gp_race() -> void:
	gp_round += 1
	load_map(gp_round)
	start_race()

func start_race() -> void:
	save_settings()
	gore.level = gore_level
	gore.reset()
	for p in projectiles:
		p.node.queue_free()
	projectiles.clear()
	for b in boxes:
		b.active = mode != "tt"
		b.node.visible = mode != "tt"
	msgs.clear()
	finish_count = 0
	tt_record = false
	if online():
		Sfx.play("get")
	_spawn_racers(false)
	state = "countdown"
	cd = 3.99
	last_num = 4
	gas_press_cd = 9.0
	race_time = 0.0
	go_t = 0.0
	fin_t = 0.0
	shake = 0.0
	hit_flash = 0.0
	cam_a = player.a
	hud.on_race_start()

## Final finishing order with estimated times for racers still on track.
func final_rows() -> Array:
	var rows: Array = []
	for k in order:
		var tm: float = k.finish_time if k.finished else race_time + float(laps * world.N - k.prog) * 0.5 / 15.5
		rows.append({"k": k, "t": tm, "est": not k.finished})
	rows.sort_custom(func(a, b): return a.t < b.t)
	return rows

func _on_results() -> void:
	if mode == "gp":
		gp_last.clear()
		var rows := final_rows()
		for i in rows.size():
			var k: Kart = rows[i].k
			var pts: int = GP_POINTS[i]
			gp_points[k.sp_idx] += pts
			gp_last.append({"sp_idx": k.sp_idx, "place": i + 1, "pts": pts})
	elif mode == "tt":
		var key := "tt_%d" % map_idx
		var best: float = settings.get_value("records", key, -1.0)
		if best < 0.0 or player.finish_time < best:
			settings.set_value("records", key, player.finish_time)
			settings.set_value("records", key + "_lap", player.best_lap)
			settings.set_value("records", key + "_laps", laps)
			settings.save("user://settings.cfg")
			tt_record = true

func record_for(i: int) -> float:
	return settings.get_value("records", "tt_%d" % i, -1.0)

func msg(text: String, col := Color.WHITE, dur := 2.6) -> void:
	msgs.append({"text": text, "col": col, "t": dur})
	if msgs.size() > 3:
		msgs.pop_front()

func vol_at(p: Vector2) -> float:
	if player == null:
		return 0.0
	return clampf(1.0 - p.distance_to(player.pos) / 45.0, 0.0, 1.0)

# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		toggle_pause()
	if e is InputEventKey and e.pressed and not e.echo:
		if state == "countdown" and (e.physical_keycode == KEY_UP or e.physical_keycode == KEY_W):
			gas_press_cd = cd
		if e.physical_keycode == KEY_M:
			Sfx.muted = not Sfx.muted
	if state == "race" or state == "finished":
		if e.is_action_pressed("use_item"):
			item_pressed = true
		if e.is_action_pressed("swap_item") and player:
			swap_slot(player, -1)
		if e.is_action_pressed("respawn") and player and player.ko <= 0.0:
			player.respawn()

func toggle_pause() -> void:
	if state != "countdown" and state != "race" and state != "finished":
		return
	if online():
		# the race keeps going online; the menu just overlays it
		hud.show_pause(not hud.pause_panel.visible)
		return
	paused = not paused
	hud.show_pause(paused)

func aim_dir() -> int:
	if Input.is_action_pressed("brake") or touch_brake or hud.joy_vy < -0.45:
		return -1
	if Input.is_action_pressed("accelerate") or hud.joy_vy > 0.45:
		return 1
	return 0

func player_input() -> Dictionary:
	var thr := 0.0
	if Input.is_action_pressed("accelerate"):
		thr = 1.0
	elif Input.is_action_pressed("brake"):
		thr = -1.0
	if hud.touch_mode and not touch_brake:
		thr = 1.0
	if touch_brake:
		thr = -1.0
	var st := Input.get_axis("steer_left", "steer_right")
	if absf(touch_steer) > absf(st):
		st = touch_steer
	return {"thr": thr, "steer": st, "drift": Input.is_action_pressed("drift") or touch_drift}

# ------------------------------------------------------------------ items
func swap_slot(k: Kart, to: int) -> void:
	if to < 0 or to == k.sel:
		to = 1 - k.sel
	k.sel = to
	if k.is_player:
		Sfx.play("get", 0.4)

func roll_item(rank: int) -> String:
	var tt := rank / 5.0
	var w := {"rocket": 35.0 * tt, "boost": 6.0 + 26.0 * tt, "saw": 15.0 + 6.0 * tt, "shield": 20.0 - 10.0 * tt, "mine": 30.0 - 25.0 * tt, "slime": 30.0 - 27.0 * tt}
	var s := 0.0
	for k in w:
		s += w[k]
	var r := randf() * s
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "boost"

func use_item(k: Kart, aim_d: int) -> void:
	var si := k.cur_slot()
	if si < 0 or k.ko > 0.0:
		return
	var it: String = k.items[si]
	k.items[si] = null
	k.item_held = 0.0
	if k.items[1 - si] != null:
		k.sel = 1 - si
	_fire(k, it, aim_d, null, -1)

## Fire an item from a kart. Online, the kart's owner fires it and sends the
## same shot to everyone (net_item), who replay it from the same spot.
func _fire(k: Kart, it: String, aim_d: int, forced_target: Kart, pid: int) -> void:
	var remote := pid >= 0
	if not remote:
		pid_n += 1
		pid = (net.my_id if online() else 0) * 100000 + pid_n
	var target_slot := -1
	var f := k.forward()
	var back := aim_d < 0 or (aim_d == 0 and (it == "mine" or it == "slime"))
	var sg := -1.0 if back else 1.0
	var fa := k.a + PI if back else k.a
	var fwd_v := 0.0 if back else maxf(k.speed, 0.0)
	var loud := k.is_player or vol_at(k.pos) > 0.3
	match it:
		"rocket":
			var target: Kart = forced_target
			if remote:
				pass
			elif back:
				var behind := order.filter(func(o): return o.rank > k.rank and o.ko <= 0.0 and not o.finished)
				target = behind[0] if behind.size() > 0 else null
			else:
				var ahead := order.filter(func(o): return o.rank < k.rank and o.ko <= 0.0 and not o.finished)
				target = ahead[ahead.size() - 1] if ahead.size() > 0 else null
			target_slot = target.idx if target else -1
			_spawn_proj("rocket", k.pos + f * 1.5 * sg, k.z + 0.75, fa, fwd_v + 28.75, k, 7.0, {"target": target, "dir": int(sg), "seg": k.seg, "pid": pid})
			if loud: Sfx.play("fire")
		"saw":
			_spawn_proj("saw", k.pos + f * 1.5 * sg, k.z + 0.5, fa, fwd_v + 25.0, k, 4.5, {"pid": pid})
			if loud: Sfx.play("fire")
		"mine", "slime":
			if back:
				_spawn_proj(it, k.pos - f * 2.0, k.z, 0.0, 0.0, k, 45.0 if it == "mine" else 35.0, {"pid": pid})
			else:
				_spawn_proj(it, k.pos + f * 1.5, k.z + 0.5, k.a, maxf(k.speed, 0.0) + 13.75, k, 45.0 if it == "mine" else 35.0, {"fly": 0.55, "pid": pid})
			if k.is_player: Sfx.play("bump")
		"boost":
			k.boost = 2.2
			if k.is_player: Sfx.play("boost")
		"shield":
			k.shield = 10.0
			if k.is_player: Sfx.play("shield")
	if online() and not remote:
		net.send_item([k.idx, it, aim_d, k.pos.x, k.pos.y, k.z, k.a, k.speed, target_slot, pid])

func net_item(args: Array) -> void:
	var k := kart_by_slot(int(args[0]))
	if k == null:
		return
	k.pos = Vector2(args[3], args[4])
	k.z = args[5]
	k.a = args[6]
	k.speed = args[7]
	_fire(k, args[1], int(args[2]), kart_by_slot(int(args[8])), int(args[9]))

func _proj_by_pid(pid: int) -> Dictionary:
	for p in projectiles:
		if int(p.get("pid", -1)) == pid:
			return p
	return {}

## Online: someone's kart was hit by a projectile.
func net_hit(args: Array) -> void:
	var k := kart_by_slot(int(args[0]))
	if k == null:
		return
	var p := _proj_by_pid(int(args[1]))
	if p.is_empty():
		p = {"type": args[2], "owner": kart_by_slot(int(args[3])), "a": float(args[4])}
	else:
		p.life = 0.0
		p.hit = true
	hit_kart(k, p, true)

func net_box(i: int) -> void:
	if i >= 0 and i < boxes.size() and boxes[i].active:
		var b: Dictionary = boxes[i]
		b.active = false
		b.t = 3.0
		b.node.visible = false
		gore.sparkle(b.pos, 16)

func net_kill(a: int, b: int) -> void:
	for pid in [a, b]:
		var p := _proj_by_pid(pid)
		if not p.is_empty():
			if pid == b:
				gore.explosion(Vector3(p.pos.x, p.y + 0.3, p.pos.y), 14)
			p.life = 0.0
			p.hit = true

func _spawn_proj(type: String, p: Vector2, y: float, ang: float, spd: float, owner: Kart, life: float, extra: Dictionary) -> void:
	var node := ItemModels.build(type)
	add_child(node)
	var d := {"type": type, "pos": p, "y": y, "a": ang, "speed": spd, "owner": owner, "life": life, "t": 0.0, "node": node, "seg": owner.seg, "bounces": 0, "hit": false, "fly": 0.0, "target": null, "dir": 1}
	d.merge(extra, true)
	projectiles.append(d)

func hit_kart(k: Kart, p: Dictionary, forced := false) -> bool:
	if not forced and (k.invuln > 0.0 or k.ko > 0.0):
		return false
	if online() and not forced:
		var by: Kart = p.get("owner")
		net.send_hit([k.idx, int(p.get("pid", -1)), p.type, by.idx if by else -1, float(p.a)])
	if k.shield > 0.0:
		k.shield = 0.0
		gore.sparkle(Vector3(k.pos.x, k.z + 1.0, k.pos.y), 24, [Color("b4ebff"), Color.WHITE])
		if k.is_player:
			Sfx.play("shield")
			msg("Blocked!", Color("9fe3ff"))
		return true
	if p.type == "slime":
		if not k.puppet:
			k.spin = 1.1
		if k.is_player:
			Sfx.play("boing")
			msg("Slimed!", Color("a6ff7a"))
		elif p.owner and p.owner.is_player:
			msg(k.sp.name + " slipped!", Color("a6ff7a"))
		return true
	splat_kart(k, p.owner, p.type, p.a)
	return true

func splat_kart(k: Kart, by: Kart, type: String, dir_a: float) -> void:
	if not k.puppet or k.ko <= 0.0:
		k.knock_out()
	if by and by != k:
		by.kills += 1
	var p3 := Vector3(k.pos.x, k.z + 0.8, k.pos.y)
	gore.splat(p3, k.sp, dir_a)
	if type == "rocket" or type == "mine":
		gore.explosion(p3)
	var v := 1.0 if k.is_player else vol_at(k.pos)
	if v > 0.05:
		Sfx.play("splat", v)
		if type != "saw":
			Sfx.play("boom", v * 0.6)
	var who: String = (by.sp.name + "'s " if by and by != k else "Your own ") + ITEM_NAME[type]
	if k.is_player:
		shake = 0.7
		hit_flash = 1.0
		hud.add_screen_blood(14 if gore_level == 2 else 9, true)
		msg(who + " " + (KILL_LINES.pick_random() if gore_level > 0 else "bonked you!"), Color("ff8a9a"), 3.0)
	else:
		if by and by.is_player:
			msg(SPLAT_LINES.pick_random().replace("{n}", k.sp.name) if gore_level > 0 else "BONK! You got " + k.sp.name + "!", Color("ffe36e"))
		var d := Vector2(cam.global_position.x, cam.global_position.z).distance_to(k.pos)
		if d < 11.0 and player.ko <= 0.0:
			hud.add_screen_blood(5 if d < 6.0 else 2, false)
			shake = maxf(shake, 0.3)

func _ai_items(k: Kart, dt: float) -> void:
	var it = k.cur_item()
	if it == null:
		return
	k.item_held += dt
	var f := k.forward()
	var near := func(dir_sign: float, r: float) -> bool:
		for o in racers:
			if o == k or o.ko > 0.0:
				continue
			var dv: Vector2 = o.pos - k.pos
			var dd := dv.length()
			if dd < r and dd > 0.01 and dir_sign * dv.dot(f) / dd > 0.7:
				return true
		return false
	var use := false
	match it:
		"boost", "shield":
			use = k.item_held > 0.6
		"rocket":
			use = k.item_held > 1.0 or k.item_held > 10.0
		"saw":
			use = k.item_held > 8.0 or near.call(1.0, 22.0)
		_:
			use = k.item_held > 6.0 or near.call(-1.0, 11.0)
	if use and randf() < dt * 3.0:
		var ad := 0
		if it == "rocket":
			ad = -1 if k.rank == 0 else 1
		elif it == "saw":
			ad = 1 if near.call(1.0, 22.0) else (-1 if near.call(-1.0, 15.0) else 1)
		elif it == "mine" or it == "slime":
			ad = -1 if near.call(-1.0, 11.0) else (1 if near.call(1.0, 10.0) else -1)
		use_item(k, ad)

# ------------------------------------------------------------------ main loop
func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if paused:
		hud.queue_redraw()
		return
	t += dt
	if state == "menu":
		if autotest and net.active and net.is_host and not net.in_race and net.players.size() >= int(OS.get_environment("NET_PLAYERS") if OS.has_environment("NET_PLAYERS") else "2"):
			net.start()
			return
		_menu_cam()
		for k in racers:
			k.sync_visual(dt)
			if menu_view == "garage" and not k.is_player:
				k.visible = false
		_update_boxes_visual()
		hud.queue_redraw()
		return
	if shot_dir != "" and shots.size() > 0 and race_time >= shots[0]:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%02d.png" % [shot_dir, int(shots[0])])
		shots.pop_front()
	if state == "countdown":
		cd -= dt
		var n := ceili(cd)
		if n != last_num and n > 0:
			last_num = n
			Sfx.play("beep")
		if cd <= 0.0:
			state = "race"
			go_t = 1.0
			Sfx.play("beep_hi")
			if Input.is_action_pressed("accelerate") and gas_press_cd < 0.6:
				player.boost = 1.3
				msg("Rocket start!", Color("ffe36e"))
			for k in racers:
				if not k.is_player and not k.puppet and randf() < 0.4:
					k.boost = 0.8 + randf() * 0.5
	else:
		if autotest and online() and fmod(race_time, 2.0 if OS.has_feature("web") else 10.0) < dt:
			var ln := "[t=%.0f %s] " % [race_time, state]
			for k in racers:
				ln += "%s%s p=%d (%.0f,%.0f) ko=%.1f | " % [k.sp.name, "*" if k.puppet else "", k.prog, k.pos.x, k.pos.y, k.ko]
			print(ln)
		race_time += dt
		if go_t > 0.0:
			go_t -= dt
		var pk := player.prog
		var diff := net_diff if online() else difficulty
		if online():
			# AI rubber-bands against the leading human
			for k in racers:
				if k.net_owner != 0:
					pk = maxi(pk, k.prog)
		for k in racers:
			if k.puppet:
				k.net_tick(dt)
				continue
			if k.is_player or k.net_owner != 0:
				k.skill_mul = 0.9 if k.finished else 1.0
			else:
				k.skill_mul = k.skill * DIFF_MUL[diff] * (1.0 + clampf(float(pk - k.prog) / (world.N * 0.5), -0.1, 0.12 if diff > 0 else 0.04))
			var inp := player_input() if (k.is_player and not k.finished and not autotest) else k.ai_input(dt)
			k.step(dt, inp)
			if not k.is_player or k.finished or autotest:
				_ai_items(k, dt)
		if item_pressed and not player.finished:
			use_item(player, aim_dir())
		_collide_racers()
		_update_projectiles(dt)
		_update_boxes(dt)
		order = racers.duplicate()
		order.sort_custom(func(x, y): return _key(x) > _key(y))
		for i in order.size():
			order[i].rank = i
		if state == "finished":
			fin_t += dt
			if fin_t > 3.6:
				state = "results"
				_on_results()
				hud.show_results()
				if autotest:
					var line := ""
					for k in order:
						line += "%s lap=%d fin=%s t=%.1f kills=%d kos=%d mt=%s | " % [k.sp.name, k.lap, k.finished, k.finish_time, k.kills, k.kos, k.mt_count]
					print("RESULT [%s %s%s] " % [mode, theme().name, (" online id=%d" % net.my_id) if online() else ""], line, " decals=", gore.dec_n, " gp=", gp_points, " rec=", tt_record)
					if online():
						get_tree().create_timer(12.0).timeout.connect(get_tree().quit)
						return
					if mode == "gp" and gp_round < Tracks.THEMES.size() - 1:
						next_gp_race()
						return
					if not OS.has_feature("web"):
						get_tree().quit()
	item_pressed = false
	for k in racers:
		k.sync_visual(dt)
	_update_boxes_visual()
	for m in msgs:
		m.t -= dt
	msgs = msgs.filter(func(m): return m.t > 0.0)
	shake = maxf(0.0, shake - dt * 1.4)
	hit_flash = maxf(0.0, hit_flash - dt * 1.8)
	_follow_cam(dt)
	Sfx.engine_update((state == "race" or state == "countdown") and player.ko <= 0.0, player.speed, player.boost > 0.0)
	hud.queue_redraw()

func _key(k: Kart) -> float:
	return 1e7 - k.finish_time if k.finished else float(k.prog)

func on_lap(k: Kart) -> void:
	if k.lap == 0:
		k.lap_start = race_time
		return
	var lt := race_time - k.lap_start
	k.last_lap = lt
	if k.best_lap < 0.0 or lt < k.best_lap:
		k.best_lap = lt
	k.lap_start = race_time
	if k.lap >= laps and not k.finished:
		k.finished = true
		k.finish_time = race_time
		finish_count += 1
		k.place = racers.filter(func(o): return o.finished).size()
		if k.is_player:
			state = "finished"
			fin_t = 0.0
			Sfx.play("beep_hi")
			msg("YOU WIN!" if k.place == 1 else "You finished " + Hud.ordinal(k.place), Color("ffe36e"), 4.0)
	elif k.is_player:
		msg("FINAL LAP!" if k.lap == laps - 1 else "Lap %d" % (k.lap + 1), Color("ff7a8a") if k.lap == laps - 1 else Color.WHITE)
		Sfx.play("get")

func _collide_racers() -> void:
	for i in racers.size():
		var a := racers[i]
		if a.ko > 0.0:
			continue
		for j in range(i + 1, racers.size()):
			var b := racers[j]
			if b.ko > 0.0:
				continue
			var d := b.pos - a.pos
			var l2 := d.length_squared()
			if l2 < 4.0 * Kart.RADIUS * Kart.RADIUS and l2 > 0.0001 and absf(a.z - b.z) < 1.5:
				var l := sqrt(l2)
				var push := (2.0 * Kart.RADIUS - l) * 0.5
				var n := d / l
				if not a.puppet:
					a.pos -= n * push * (2.0 if b.puppet else 1.0)
					a.speed *= 0.97
				if not b.puppet:
					b.pos += n * push * (2.0 if a.puppet else 1.0)
					b.speed *= 0.97
				if (a.is_player or b.is_player) and randf() < 0.2:
					Sfx.play("bump", 0.6)

func _update_projectiles(dt: float) -> void:
	var N := world.N
	var i := projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = projectiles[i]
		p.t += dt
		p.life -= dt
		# track progress along the road
		var best: int = p.seg
		var bd := INF
		for o in range(-15, 16):
			var q := (int(p.seg) + o + N) % N
			var dd := world.P[q].distance_squared_to(p.pos)
			if dd < bd:
				bd = dd
				best = q
		p.seg = best
		if p.type == "rocket":
			var tg: Kart = p.target
			var aim_pt: Vector2
			if tg and tg.ko <= 0.0 and tg.pos.distance_to(p.pos) < 9.0:
				aim_pt = tg.pos
			else:
				aim_pt = world.P[(best + 10 * int(p.dir) + N) % N]
			p.a += clampf(Kart.adiff(p.a, atan2(aim_pt.y - p.pos.y, aim_pt.x - p.pos.x)), -4.0 * dt, 4.0 * dt)
			if randf() < 0.9:
				gore.spark(Vector3(p.pos.x, p.y, p.pos.y) - Vector3(cos(p.a), 0, sin(p.a)) * 0.6, Color("ffdc5a") if randf() < 0.5 else Color("ff8c3c"))
		if p.speed > 0.0:
			p.pos += Vector2(cos(p.a), sin(p.a)) * p.speed * dt
			var nn := world.nearest_local(p.pos, best, 6)
			if absf(nn.y) > WorldGen.WALL_IN - 0.15 and not world.is_open(int(nn.x), nn.y):
				var ii := int(nn.x)
				var foot := world.P[ii].lerp(world.P[(ii + 1) % N], nn.z)
				var w: Vector2 = (p.pos - foot).normalized()
				if p.type == "saw":
					var dv := Vector2(cos(p.a), sin(p.a))
					var vn := dv.dot(w)
					if vn > 0.0:
						dv -= 2.0 * vn * w
						p.a = atan2(dv.y, dv.x)
						p.bounces += 1
						gore.sparkle(Vector3(p.pos.x, p.y, p.pos.y), 8, [Color("ffe680"), Color.WHITE])
						if p.bounces > 4:
							p.life = 0.0
						elif vol_at(p.pos) > 0.2:
							Sfx.play("bump", vol_at(p.pos))
					p.pos = foot + w * (WorldGen.WALL_IN - 0.2)
				elif p.fly > 0.0:
					p.pos = foot + w * (WorldGen.WALL_IN - 0.3)
					p.speed = 0.0
				else:
					p.life = 0.0
			var g := world.ground(p.pos, world.nearest_local(p.pos, best, 4)).x
			if p.fly > 0.0:
				p.y = g + sin(PI * minf(1.0, p.t / p.fly)) * 2.25
				p.speed *= 1.0 - 1.5 * dt
				if p.t >= p.fly:
					p.speed = 0.0
					p.y = g
					p.fly = 0.0
			elif g - p.y > (2.25 if p.type == "rocket" else 1.0):
				p.life = 0.0
			else:
				p.y = g + (0.9 if p.type == "rocket" else 0.55)
		else:
			p.y = world.ground(p.pos, world.nearest_local(p.pos, best, 4)).x
		if p.life > 0.0:
			for k in racers:
				if k.puppet or k.ko > 0.0 or (k == p.owner and p.t < 1.2):
					continue
				if k.pos.distance_squared_to(p.pos) < (2.25 if p.type == "slime" else 1.9) and absf(k.z - p.y) < 2.25:
					if hit_kart(k, p):
						p.life = 0.0
						p.hit = true
						break
		if p.life > 0.0 and p.speed > 0.0 and p.fly <= 0.0 and (not online() or net.is_host):
			for q in projectiles:
				if q == p or q.speed > 0.0 or q.life <= 0.0:
					continue
				if q.pos.distance_squared_to(p.pos) < 1.25:
					if online():
						net.send_kill(int(p.get("pid", -1)), int(q.get("pid", -1)))
					q.life = 0.0
					p.life = 0.0
					gore.explosion(Vector3(q.pos.x, q.y + 0.3, q.pos.y), 14)
					break
		var node: Node3D = p.node
		node.global_position = Vector3(p.pos.x, p.y, p.pos.y)
		node.rotation.y = atan2(-cos(p.a), -sin(p.a))
		if p.type == "saw":
			node.get_child(0).rotation.y += dt * 25.0
		if p.life <= 0.0:
			if not p.hit and (p.type == "rocket" or p.type == "saw"):
				gore.explosion(Vector3(p.pos.x, p.y, p.pos.y), 20 if p.type == "rocket" else 8)
			node.queue_free()
			projectiles.remove_at(i)
		i -= 1

func _update_boxes(dt: float) -> void:
	if mode == "tt":
		return
	for bi in boxes.size():
		var b: Dictionary = boxes[bi]
		if not b.active:
			b.t -= dt
			if b.t <= 0.0:
				b.active = true
				b.node.visible = true
			continue
		for k in racers:
			if k.ko > 0.0 or k.puppet:
				continue
			var bp: Vector3 = b.pos
			if k.pos.distance_squared_to(Vector2(bp.x, bp.z)) < 2.25 and absf(k.z - bp.y + 1.0) < 2.0:
				b.active = false
				b.t = 3.0
				b.node.visible = false
				gore.sparkle(bp, 16)
				if online():
					net.send_box(bi)
				if k.free_slot() >= 0 and k.roulette <= 0.0:
					k.roulette = 1.1 if k.is_player else 0.6
					k.pending = roll_item(k.rank)
					if k.is_player:
						Sfx.play("pick")
				break

func _update_boxes_visual() -> void:
	for b in boxes:
		if not b.active:
			continue
		var n: Node3D = b.node
		n.global_position = b.pos + Vector3(0, sin(t * 3.0 + b.ph) * 0.15, 0)
		b.mesh.rotation = Vector3(t * 0.9 + b.ph, t * 1.3, 0)
		b.mesh.material_override.set_shader_parameter("albedo", Color.from_hsv(fmod(t * 0.25 + b.ph, 1.0), 0.55, 1.0))

# ------------------------------------------------------------------ camera
func _menu_cam() -> void:
	if menu_view == "garage" and player:
		var kp := Vector3(player.pos.x, player.z, player.pos.y)
		var aa := t * 0.5
		var off := Vector3(cos(aa), 0, sin(aa)) * 4.2
		cam.global_position = kp + off + Vector3(0, 1.7, 0)
		# aim a little to the kart's left so it sits right of the menu panel
		var side := cam.global_transform.basis.x
		cam.look_at(kp + Vector3(0, 0.75, 0) - side * 1.3)
		return
	var aa2 := t * 0.12
	var c := Vector2(world.P[0].x, world.P[0].y)
	var p := c + Vector2(cos(aa2), sin(aa2)) * 13.0
	cam.global_position = Vector3(p.x, maxf(world.TH[0] + 4.5, world.terrain_h(p.x, p.y) + 2.0), p.y)
	cam.look_at(Vector3(c.x, world.TH[0] + 0.8, c.y))

func _follow_cam(dt: float) -> void:
	var P := player
	var tp := P.ko_pos if P.ko > 0.0 else Vector3(P.pos.x, P.z, P.pos.y)
	if P.ko <= 0.0:
		cam_a += Kart.adiff(cam_a, P.a) * minf(1.0, 5.0 * dt)
	var dist := 9.0 if P.ko > 0.0 else 6.0
	var f := Vector2(cos(cam_a), sin(cam_a))
	var cp := Vector2(tp.x, tp.z) - f * dist
	var nr := world.nearest_global(cp, 12.0)
	var gh := world.terrain_h(cp.x, cp.y)
	if nr.x >= 0:
		gh = maxf(gh, world.ground(cp, nr).x)
	var target_h := maxf(tp.y + (5.0 if P.ko > 0.0 else 2.8), gh + 1.2)
	cam_h += (target_h - cam_h) * minf(1.0, 6.0 * dt)
	cam_h = maxf(cam_h, gh + 1.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.25
	cam.global_position = Vector3(cp.x, cam_h, cp.y) + jitter
	cam.look_at(Vector3(tp.x + f.x * 3.0, tp.y + 1.0, tp.z + f.y * 3.0))
