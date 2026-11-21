class_name Hud
extends Control
## Heads-up display, menus, results, pause, CRT overlay and touch controls.
## Layout uses "design units": the screen is 225 units tall (like the browser version).

var race: Node
var font: Font
var u := 1.0
var W := 400.0
var touch_mode := false
var joy_vy := 0.0
var screen_blood: Array[Dictionary] = []
var fingers := {}          # touch index -> role
var joy_origin := Vector2()
var joy_pos := Vector2()
var joy_active := false

var results: Control
var pause_panel: Control
var crt: ColorRect
var char_buttons: Array[Button] = []
var res_title: Label
var res_grid: GridContainer
var seg_buttons := {}

const YELLOW := Color("ffe36e")
const INKC := Color("2a1830")
const RANKCOL := [Color("ffe36e"), Color("e6e9ff"), Color("ffb27a"), Color.WHITE, Color.WHITE, Color.WHITE]

static func ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return str(n) + suf

static func fmt(tm: float) -> String:
	if tm < 0.0:
		return "--:--.--"
	var m := int(tm / 60.0)
	var s := tm - m * 60.0
	return "%d:%05.2f" % [m, s]

func setup(r: Node) -> void:
	race = r
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()
	touch_mode = DisplayServer.is_touchscreen_available()
	_build_crt()
	_build_menus()
	_build_results()
	_build_pause()
	set_crt(race.settings.get_value("video", "crt", true))
	set_aa(race.settings.get_value("video", "aa", true))

# ------------------------------------------------------------------ widgets
func _style(col: Color, radius := 14, border := Color(1, 1, 1, 0.25)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _button(text: String, col := Color("ff4f8b"), size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _style(col, 999, col.darkened(0.35)))
	b.add_theme_stylebox_override("hover", _style(col.lightened(0.1), 999, col.darkened(0.35)))
	b.add_theme_stylebox_override("pressed", _style(col.darkened(0.15), 999, col.darkened(0.35)))
	b.add_theme_stylebox_override("focus", _style(col, 999, Color.WHITE))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", INKC)
	b.add_theme_constant_override("outline_size", 6)
	return b

func _label(text: String, size: int, col := Color.WHITE, outline := 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INKC)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _overlay() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.05, 0.16, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(sc)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cc.custom_minimum_size = Vector2(0, 0)
	sc.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	bg.set_meta("vb", vb)
	bg.set_meta("cc", cc)
	return bg

func _seg(vb: VBoxContainer, title: String, opts: Array, cur: int, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_label(title, 20, Color.WHITE, 6))
	var group: Array[Button] = []
	for i in opts.size():
		var b := _button(opts[i], Color("ff4f6e") if i == cur else Color(1, 1, 1, 0.14), 18)
		b.toggle_mode = false
		var idx := i
		b.pressed.connect(func():
			for j in group.size():
				var c := Color("ff4f6e") if j == idx else Color(1, 1, 1, 0.14)
				group[j].add_theme_stylebox_override("normal", _style(c, 999, c.darkened(0.3)))
				group[j].add_theme_stylebox_override("hover", _style(c.lightened(0.1), 999, c.darkened(0.3)))
			cb.call(idx))
		group.append(b)
		hb.add_child(b)
	vb.add_child(hb)

func _build_crt() -> void:
	crt = ColorRect.new()
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float rows = 225.0;
void fragment() {
	vec2 uv = UV;
	float line = 0.5 + 0.5 * cos(uv.y * rows * 6.2831853);
	float scan = (1.0 - line) * 0.26;
	vec2 d = (uv - 0.5) * vec2(1.0, 1.15);
	float vig = smoothstep(0.42, 0.78, length(d));
	float roll = smoothstep(0.06, 0.0, abs(fract(uv.y - TIME * 0.12) - 0.5)) * 0.05;
	float mask = mod(floor(FRAGCOORD.x), 3.0);
	vec3 tint = mask < 1.0 ? vec3(1.0, 0.3, 0.3) : (mask < 2.0 ? vec3(0.3, 1.0, 0.4) : vec3(0.35, 0.45, 1.0));
	COLOR = vec4(mix(vec3(0.0), tint, 0.25), scan + vig * 0.6);
	COLOR.rgb += roll;
	COLOR.a = max(COLOR.a, roll);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	crt.material = m
	add_child(crt)

func set_crt(on: bool) -> void:
	crt.visible = on
	race.settings.set_value("video", "crt", on)
	race.settings.save("user://settings.cfg")

func set_aa(on: bool) -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X if on else Viewport.MSAA_DISABLED
	race.settings.set_value("video", "aa", on)
	race.settings.save("user://settings.cfg")

# ------------------------------------------------------------------ flow
func set_shadows(on: bool) -> void:
	Env.set_shadows(on)
	race.settings.set_value("video", "shadows", on)
	race.settings.save("user://settings.cfg")

# ------------------------------------------------------------------ screens
var screens := {}
var cur_screen := ""
var history: Array[String] = []
var char_name: Label
var char_blurb: Label
var char_stats: Control
var map_cards: Array[PanelContainer] = []
var map_title: Label
var map_start: Button
var map_note: Label
var previews: Array = []
var res_buttons: HBoxContainer

func _card_style(col: Color, sel: bool) -> StyleBoxFlat:
	var sb := _style(col, 18, YELLOW if sel else Color(1, 1, 1, 0.25))
	sb.set_border_width_all(5 if sel else 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _hbox(sep := 12) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", sep)
	return hb

func _back_button(vb: Container) -> void:
	var b := _button("Back", Color("6c5ce7"), 22)
	b.pressed.connect(go_back)
	var cc := CenterContainer.new()
	cc.add_child(b)
	vb.add_child(cc)

func show_screen(n: String, remember := true) -> void:
	if remember and cur_screen != "" and cur_screen != n:
		history.append(cur_screen)
	for k in screens:
		screens[k].visible = k == n
	cur_screen = n
	race.menu_view = "garage" if n == "character" else "orbit"
	if n == "map":
		_refresh_maps()
	if n == "character":
		_refresh_char()
	if n == "lobby":
		_refresh_lobby()

func go_back() -> void:
	Sfx.play("get", 0.4)
	if history.is_empty():
		show_screen("title", false)
	else:
		show_screen(history.pop_back(), false)

func _build_menus() -> void:
	for th in Tracks.THEMES:
		previews.append(WorldGen.preview(th))
	_build_title()
	_build_modes()
	_build_character()
	_build_maps()
	_build_settings()
	_build_online()
	_build_lobby()
	show_screen("title", false)

func _build_title() -> void:
	var o := _overlay()
	screens["title"] = o
	var vb: VBoxContainer = o.get_meta("vb")
	var title := _label("Carnage Karts", 76, YELLOW, 20)
	title.add_theme_color_override("font_shadow_color", Color("e0306f"))
	title.add_theme_constant_override("shadow_offset_y", 6)
	vb.add_child(title)
	vb.add_child(_label("Six cute critters. Very messy finishes.", 20, Color.WHITE, 6))
	vb.add_child(Control.new())
	for item in [["Play", Color("ff4f8b"), func(): show_screen("mode")], ["Play Online", Color("f5a623"), func(): show_screen("online")], ["Settings", Color("6c5ce7"), func(): show_screen("settings")]]:
		var b := _button(item[0], item[1], 32)
		b.custom_minimum_size = Vector2(300, 66)
		b.pressed.connect(item[2])
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)
	var help := _label("", 14, Color(1, 1, 1, 0.85), 5)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(700, 0)
	if touch_mode:
		help.text = "Karts drive themselves. Touch the left side to steer (push up/down to aim items). ITEM fires, tap the slots up top to swap, DRIFT hops: hold it and steer into the bend until the sparks turn blue, orange then pink, then let go to boost."
	else:
		help.text = "W / Up gas · S / Down brake · A D / Left Right steer · Shift hop/drift (steer into the bend for blue → orange → pink sparks, release to boost) · Space use item (hold Up/Down to aim) · Q swap item · R back to track · P pause · M mute"
	vb.add_child(help)

func _build_modes() -> void:
	var o := _overlay()
	screens["mode"] = o
	var vb: VBoxContainer = o.get_meta("vb")
	vb.add_child(_label("Choose a mode", 46, YELLOW, 14))
	var hb := _hbox(16)
	var info := [
		["quick", "Quick Race", "One race on any track\nagainst five critters.", Color("ff4f8b")],
		["gp", "Grand Prix", "All four tracks in a row.\nPoints decide the champion.", Color("f5a623")],
		["tt", "Time Trial", "Just you and the clock.\nNo items. Beat your record.", Color("38b6a3")],
	]
	for m in info:
		var b := Button.new()
		b.text = m[1] + "\n\n" + m[2]
		b.custom_minimum_size = Vector2(250, 190)
		b.add_theme_font_size_override("font_size", 21)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", INKC)
		b.add_theme_constant_override("outline_size", 6)
		for st in ["normal", "focus"]:
			b.add_theme_stylebox_override(st, _card_style(m[3], false))
		b.add_theme_stylebox_override("hover", _card_style(m[3].lightened(0.1), true))
		b.add_theme_stylebox_override("pressed", _card_style(m[3].darkened(0.1), true))
		var mm: String = m[0]
		b.pressed.connect(func():
			race.mode = mm
			Sfx.play("pick", 0.5)
			show_screen("character"))
		hb.add_child(b)
	vb.add_child(hb)
	_back_button(vb)

func _build_character() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	screens["character"] = root
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.05, 0.16, 0.72), 22, Color(1, 1, 1, 0.2)))
	pc.anchor_left = 0.0
	pc.anchor_top = 0.0
	pc.anchor_bottom = 1.0
	pc.offset_left = 18
	pc.offset_top = 18
	pc.offset_bottom = -18
	pc.custom_minimum_size = Vector2(400, 0)
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	vb.add_child(_label("Choose your critter", 30, YELLOW, 10))
	char_name = _label("", 44, Color.WHITE, 12)
	vb.add_child(char_name)
	char_blurb = _label("", 17, Color(1, 1, 1, 0.9), 5)
	char_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	char_blurb.custom_minimum_size = Vector2(360, 0)
	vb.add_child(char_blurb)
	char_stats = Control.new()
	char_stats.custom_minimum_size = Vector2(360, 96)
	char_stats.draw.connect(_draw_stats)
	vb.add_child(char_stats)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in Critters.SPECIES.size():
		var sp: Dictionary = Critters.SPECIES[i]
		var b := _button(sp.name, sp.kart, 18)
		b.custom_minimum_size = Vector2(116, 46)
		var idx := i
		b.pressed.connect(func(): _select(idx))
		char_buttons.append(b)
		grid.add_child(b)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	vb.add_child(gc)
	var hb := _hbox(12)
	var back := _button("Back", Color("6c5ce7"), 22)
	back.pressed.connect(go_back)
	var nxt := _button("Next", Color("ff4f8b"), 26)
	nxt.custom_minimum_size = Vector2(160, 0)
	nxt.pressed.connect(func():
		Sfx.play("pick", 0.5)
		if race.net.active:
			race.net.pick(race.selected)
			history.clear()
			show_screen("lobby", false)
		else:
			show_screen("map"))
	hb.add_child(back)
	hb.add_child(nxt)
	vb.add_child(hb)

func _draw_stats() -> void:
	var sp: Dictionary = Critters.SPECIES[race.selected]
	var rows := [["Speed", float(sp.spd)], ["Acceleration", float(sp.acc)], ["Handling", float(sp.hdl)]]
	var f := font
	for i in rows.size():
		var y := 10.0 + i * 30.0
		char_stats.draw_string_outline(f, Vector2(0, y + 15), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, INKC)
		char_stats.draw_string(f, Vector2(0, y + 15), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		var bx := 140.0
		var bw := 210.0
		char_stats.draw_rect(Rect2(bx, y, bw, 18), Color(1, 1, 1, 0.15))
		var v := clampf((rows[i][1] - 0.9) / 0.2, 0.08, 1.0)
		char_stats.draw_rect(Rect2(bx, y, bw * v, 18), sp.kart)
		char_stats.draw_rect(Rect2(bx, y, bw, 18), INKC, false, 2.0)

func _select(i: int, quiet := false) -> void:
	race.selected = i
	if not quiet:
		race._spawn_racers(true)
		Sfx.play("get", 0.5)
	_refresh_char()

func _refresh_char() -> void:
	var sp: Dictionary = Critters.SPECIES[race.selected]
	if char_name:
		char_name.text = sp.name
		char_blurb.text = sp.blurb
		char_stats.queue_redraw()
	for j in char_buttons.size():
		var b := char_buttons[j]
		var c: Color = Critters.SPECIES[j].kart
		var border: Color = YELLOW if j == race.selected else c.darkened(0.35)
		b.add_theme_stylebox_override("normal", _style(c, 999, border))
		b.add_theme_stylebox_override("hover", _style(c.lightened(0.1), 999, border))

func _track_preview(pts: PackedVector2Array, col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(176, 96)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var sz := c.size
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for q in pts:
			mn = mn.min(q)
			mx = mx.max(q)
		var sc := minf((sz.x - 24.0) / (mx.x - mn.x), (sz.y - 24.0) / (mx.y - mn.y))
		var off := (sz - (mx - mn) * sc) * 0.5
		var arr := PackedVector2Array()
		for k in range(0, pts.size(), 3):
			arr.append(off + (pts[k] - mn) * sc)
		arr.append(arr[0])
		c.draw_polyline(arr, INKC, 11.0, true)
		c.draw_polyline(arr, col, 6.0, true)
		c.draw_circle(arr[0], 6.0, YELLOW))
	return c

func _build_maps() -> void:
	var o := _overlay()
	screens["map"] = o
	var vb: VBoxContainer = o.get_meta("vb")
	map_title = _label("Choose a track", 42, YELLOW, 14)
	vb.add_child(map_title)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for i in Tracks.THEMES.size():
		var th: Dictionary = Tracks.THEMES[i]
		var pc := PanelContainer.new()
		pc.mouse_filter = Control.MOUSE_FILTER_STOP
		var cvb := VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 4)
		cvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(cvb)
		cvb.add_child(_track_preview(previews[i], Tracks.col(th, "sky_top").lerp(Color.WHITE, 0.35)))
		var nm := _label(th.name, 19, Color.WHITE, 6)
		cvb.add_child(nm)
		var bl := _label(th.blurb, 12, Color(1, 1, 1, 0.85), 4)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(176, 0)
		pc.custom_minimum_size = Vector2(206, 0)
		cvb.add_child(bl)
		var rec := _label("", 13, YELLOW, 4)
		rec.name = "Record"
		cvb.add_child(rec)
		for ch in cvb.get_children():
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var idx := i
		pc.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and race.mode != "gp":
				Sfx.play("get", 0.5)
				race.load_map(idx)
				_refresh_maps())
		map_cards.append(pc)
		grid.add_child(pc)
	vb.add_child(grid)
	map_note = _label("", 16, Color.WHITE, 5)
	vb.add_child(map_note)
	var hb := _hbox(12)
	var back := _button("Back", Color("6c5ce7"), 22)
	back.pressed.connect(go_back)
	map_start = _button("Start Race", Color("ff4f8b"), 30)
	map_start.custom_minimum_size = Vector2(280, 62)
	map_start.pressed.connect(func():
		history.clear()
		race.begin_mode(race.mode))
	hb.add_child(back)
	hb.add_child(map_start)
	vb.add_child(hb)

func _refresh_maps() -> void:
	var gp: bool = race.mode == "gp"
	map_title.text = "The Critter Cup" if gp else ("Time Trial: choose a track" if race.mode == "tt" else "Choose a track")
	map_start.text = "Start Grand Prix" if gp else "Start Race"
	map_note.text = "Four races, one after another. 10, 8, 6, 4, 2, 1 points per race." if gp else "%d laps · %s AI" % [race.laps, race.DIFF_NAME[race.difficulty]] if race.mode != "tt" else "%d laps · no items" % race.laps
	for i in map_cards.size():
		var th: Dictionary = Tracks.THEMES[i]
		var sel: bool = (not gp) and i == race.map_idx
		map_cards[i].add_theme_stylebox_override("panel", _card_style(Tracks.col(th, "asphalt").lerp(Tracks.col(th, "sky_top"), 0.35), sel or gp))
		var rec: Label = map_cards[i].find_child("Record", true, false)
		var r: float = race.record_for(i)
		if gp:
			rec.text = "Race %d" % (i + 1)
		else:
			rec.text = ("Record " + fmt(r)) if r > 0.0 else "No record yet"

func _build_settings() -> void:
	var o := _overlay()
	screens["settings"] = o
	var vb: VBoxContainer = o.get_meta("vb")
	vb.add_child(_label("Settings", 46, YELLOW, 14))
	var st: ConfigFile = race.settings
	_seg(vb, "Gore:", ["Off", "On", "Extra"], race.gore_level, func(i): race.gore_level = i; race.gore.level = i; race.save_settings())
	_seg(vb, "Difficulty:", ["Easy", "Normal", "Hard"], race.difficulty, func(i): race.difficulty = i; race.save_settings())
	_seg(vb, "Laps:", ["1", "2", "3", "4", "5"], race.laps - 1, func(i): race.laps = i + 1; race.save_settings())
	var vols := [0.0, 0.35, 0.7, 1.0]
	var vcur := 3
	for i in vols.size():
		if absf(vols[i] - Sfx.volume) < 0.05:
			vcur = i
	_seg(vb, "Sound:", ["Off", "Low", "Medium", "High"], vcur, func(i): Sfx.volume = vols[i]; st.set_value("audio", "volume", vols[i]); st.save("user://settings.cfg"); Sfx.play("pick"))
	_seg(vb, "CRT filter:", ["Off", "On"], 1 if st.get_value("video", "crt", true) else 0, func(i): set_crt(i == 1))
	_seg(vb, "Anti-aliasing:", ["Off", "On"], 1 if st.get_value("video", "aa", true) else 0, func(i): set_aa(i == 1))
	_seg(vb, "Shadows:", ["Off", "On"], 1 if st.get_value("video", "shadows", true) else 0, func(i): set_shadows(i == 1))
	_back_button(vb)

# ------------------------------------------------------------------ flow
func on_race_start() -> void:
	for k in screens:
		screens[k].visible = false
	results.visible = false
	screen_blood.clear()

func to_menu() -> void:
	if race.net.active:
		race.net.leave()
	race.net_roster = []
	race.state = "menu"
	race.paused = false
	results.visible = false
	pause_panel.visible = false
	race.gore.reset()
	for p in race.projectiles:
		p.node.queue_free()
	race.projectiles.clear()
	race.mode = "quick" if race.mode == "gp" else race.mode
	race._spawn_racers(true)
	history.clear()
	show_screen("title", false)

func show_pause(on: bool) -> void:
	pause_panel.visible = on

func _build_results() -> void:
	results = _overlay()
	results.visible = false
	var vb: VBoxContainer = results.get_meta("vb")
	res_title = _label("Results", 44, YELLOW, 14)
	vb.add_child(res_title)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.35), 16, Color(1, 1, 1, 0.15)))
	res_grid = GridContainer.new()
	res_grid.add_theme_constant_override("h_separation", 26)
	res_grid.add_theme_constant_override("v_separation", 4)
	pc.add_child(res_grid)
	vb.add_child(pc)
	res_buttons = _hbox(14)
	vb.add_child(res_buttons)

func _build_pause() -> void:
	pause_panel = _overlay()
	pause_panel.visible = false
	var vb: VBoxContainer = pause_panel.get_meta("vb")
	vb.add_child(_label("Paused", 48, YELLOW, 14))
	var hb := _hbox(14)
	var res := _button("Resume")
	res.pressed.connect(func(): race.toggle_pause())
	var quit := _button("Quit to Menu", Color("6c5ce7"))
	pause_panel.set_meta("quit", quit)
	quit.pressed.connect(func(): race.paused = false; pause_panel.visible = false; to_menu())
	hb.add_child(res)
	hb.add_child(quit)
	vb.add_child(hb)

func _res_row(cells: Array, col: Color, size := 22) -> void:
	for c in cells:
		res_grid.add_child(_label(str(c), size, col, 6))

func _res_button(text: String, col: Color, cb: Callable) -> void:
	var b := _button(text, col)
	b.pressed.connect(cb)
	res_buttons.add_child(b)

func show_results() -> void:
	for c in res_grid.get_children():
		c.queue_free()
	for c in res_buttons.get_children():
		c.queue_free()
	var rows: Array = race.final_rows()
	var place := 0
	for i in rows.size():
		if rows[i].k.is_player:
			place = i + 1
	var tname: String = race.theme().name
	match race.mode:
		"tt":
			res_grid.columns = 2
			var P: Kart = race.player
			res_title.text = "NEW RECORD!" if race.tt_record else "Time Trial"
			_res_row(["Track", tname], Color.WHITE)
			_res_row(["Your time", fmt(P.finish_time)], YELLOW)
			_res_row(["Best lap", fmt(P.best_lap)], Color.WHITE)
			_res_row(["Record", fmt(race.record_for(race.map_idx))], YELLOW if race.tt_record else Color.WHITE)
			_res_button("Retry", Color("ff4f8b"), func(): results.visible = false; race.start_race())
			_res_button("Change Track", Color("38b6a3"), func(): results.visible = false; race.state = "menu"; show_screen("map", false))
			_res_button("Main Menu", Color("6c5ce7"), func(): to_menu())
		"gp":
			res_grid.columns = 4
			res_title.text = "Race %d of 4: %s" % [race.gp_round + 1, tname]
			_res_row(["#", "Racer", "Points", "Total"], Color(1, 1, 1, 0.7), 16)
			for e in race.gp_last:
				var sp: Dictionary = Critters.SPECIES[e.sp_idx]
				var me: bool = e.sp_idx == race.selected
				_res_row([ordinal(e.place), sp.name + (" (you)" if me else ""), "+%d" % e.pts, race.gp_points[e.sp_idx]], YELLOW if me else Color.WHITE)
			if race.gp_round < Tracks.THEMES.size() - 1:
				_res_button("Next Race", Color("ff4f8b"), func(): results.visible = false; race.next_gp_race())
			else:
				_res_button("Final Standings", Color("f5a623"), func(): _show_gp_final())
			_res_button("Quit", Color("6c5ce7"), func(): to_menu())
		_:
			res_grid.columns = 4
			res_title.text = "Champion Critter!" if place == 1 else "You finished " + ordinal(place)
			_res_row(["#", "Racer", "Time", "Splats" if race.gore_level > 0 else "Bonks"], Color(1, 1, 1, 0.7), 16)
			for i in rows.size():
				var k: Kart = rows[i].k
				_res_row([ordinal(i + 1), k.sp.name + (" (you)" if k.is_player else (" (%s)" % race.net.name_of(k.net_owner) if k.net_owner != 0 else "")), fmt(rows[i].t) + (" *" if rows[i].est else ""), k.kills], YELLOW if k.is_player else Color.WHITE)
			if race.online():
				if race.net.is_host:
					_res_button("Back to Lobby", Color("ff4f8b"), func(): race.net.back_to_lobby())
				else:
					res_buttons.add_child(_label("Waiting for the host…", 20, Color.WHITE, 6))
				_res_button("Leave", Color("6c5ce7"), func(): to_menu())
				results.visible = true
				return
			_res_button("Race Again", Color("ff4f8b"), func(): results.visible = false; race.start_race())
			_res_button("Change Track", Color("38b6a3"), func(): results.visible = false; race.state = "menu"; show_screen("map", false))
			_res_button("Main Menu", Color("6c5ce7"), func(): to_menu())
	results.visible = true

func _show_gp_final() -> void:
	for c in res_grid.get_children():
		c.queue_free()
	for c in res_buttons.get_children():
		c.queue_free()
	var idx: Array = range(Critters.SPECIES.size())
	idx.sort_custom(func(a, b): return race.gp_points[a] > race.gp_points[b])
	var winner: Dictionary = Critters.SPECIES[idx[0]]
	res_title.text = ("You win the Critter Cup!" if idx[0] == race.selected else winner.name + " wins the Critter Cup!")
	res_grid.columns = 3
	_res_row(["#", "Racer", "Points"], Color(1, 1, 1, 0.7), 16)
	for i in idx.size():
		var sp: Dictionary = Critters.SPECIES[idx[i]]
		var me: bool = idx[i] == race.selected
		_res_row([ordinal(i + 1), sp.name + (" (you)" if me else ""), race.gp_points[idx[i]]], YELLOW if me else RANKCOL[mini(i, 2)] if i < 3 else Color.WHITE, 26 if i == 0 else 22)
	_res_button("Main Menu", Color("6c5ce7"), func(): to_menu())

func add_screen_blood(n: int, big: bool) -> void:
	if race.gore_level == 0:
		return
	for i in n:
		var r := (12.0 if big else 6.0) + randf() * (24.0 if big else 12.0)
		var s := {"x": randf() * W, "y": randf() * 190.0, "r": r, "life": 2.6 + randf() * 1.6, "blobs": [], "drips": []}
		for b in 7:
			var a := randf() * TAU
			var d := r * (0.6 + randf() * 0.8)
			s.blobs.append(Vector3(cos(a) * d, sin(a) * d, r * (0.15 + randf() * 0.3)))
		for d in 2 + randi() % 3:
			s.drips.append({"dx": (randf() - 0.5) * r * 1.3, "w": 1.5 + randf() * 3.0, "len": 0.0, "sp": 6.0 + randf() * 18.0})
		screen_blood.append(s)
	if screen_blood.size() > 40:
		screen_blood = screen_blood.slice(screen_blood.size() - 40)

# ------------------------------------------------------------------ touch
func _btn_pos(name: String) -> Vector3:
	# returns (x, y, radius) in design units
	match name:
		"item": return Vector3(W - 30, 192, 24)
		"drift": return Vector3(W - 80, 200, 18)
		"brake": return Vector3(W - 122, 205, 16)
		"pause": return Vector3(W / 2.0 + 60, 18, 11)
	return Vector3.ZERO

func _hit(name: String, p: Vector2) -> bool:
	var b := _btn_pos(name)
	return p.distance_to(Vector2(b.x, b.y)) < b.z * 1.15

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		touch_mode = true
	if not touch_mode or not (race.state == "race" or race.state == "countdown" or race.state == "finished") or race.paused:
		return
	if e is InputEventScreenTouch:
		var p: Vector2 = e.position / u
		if e.pressed:
			var role := ""
			if _hit("item", p):
				role = "item"
				race.item_pressed = true
			elif _hit("drift", p):
				role = "drift"
				race.touch_drift = true
			elif _hit("brake", p):
				role = "brake"
				race.touch_brake = true
			elif _hit("pause", p):
				role = "pause"
				race.toggle_pause()
			elif p.y < 46 and absf(p.x - W / 2.0) < 42:
				role = "slot"
				race.swap_slot(race.player, 0 if p.x < W / 2.0 else 1)
			elif p.x < W / 2.0 and not joy_active:
				role = "joy"
				joy_active = true
				joy_origin = p
				joy_pos = p
			fingers[e.index] = role
		else:
			var role: String = fingers.get(e.index, "")
			fingers.erase(e.index)
			match role:
				"drift": race.touch_drift = false
				"brake": race.touch_brake = false
				"joy":
					joy_active = false
					race.touch_steer = 0.0
					joy_vy = 0.0
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if fingers.get(e.index, "") == "joy":
			var p: Vector2 = e.position / u
			var d := p - joy_origin
			var R := 26.0
			if d.length() > R:
				d = d.normalized() * R
			joy_pos = joy_origin + d
			var v := d.x / R
			v = 0.0 if absf(v) < 0.08 else (v - signf(v) * 0.08) / 0.92
			race.touch_steer = clampf(v, -1.0, 1.0)
			joy_vy = clampf(-d.y / R, -1.0, 1.0)
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ drawing helpers
func T(s: String, x: float, y: float, size: float, align := HORIZONTAL_ALIGNMENT_LEFT, col := Color.WHITE) -> void:
	var fs := int(size * u)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var px := x * u
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		px -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		px -= w
	draw_string_outline(font, Vector2(px, y * u), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.22)), INKC)
	draw_string(font, Vector2(px, y * u), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func C(x: float, y: float, r: float, col: Color) -> void:
	draw_circle(Vector2(x, y) * u, r * u, col)

func RR(x: float, y: float, w: float, h: float, col: Color, border := Color(0, 0, 0, 0), bw := 0.0, rad := 8.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad * u))
	if bw > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(maxf(1.0, bw * u)))
	draw_style_box(sb, Rect2(x * u, y * u, w * u, h * u))

func icon(it: String, cx: float, cy: float, s: float) -> void:
	var c := Vector2(cx, cy) * u
	var k := s * u
	match it:
		"rocket":
			var pts := PackedVector2Array([c + Vector2(0.45, -0.45) * k, c + Vector2(-0.3, 0.05) * k, c + Vector2(-0.05, 0.3) * k])
			draw_colored_polygon(pts, Color("ff8a2a"))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), INKC, 1.5 * u)
			draw_circle(c + Vector2(-0.3, 0.32) * k, 0.12 * k, Color("5cc25c"))
			draw_circle(c + Vector2(-0.38, 0.2) * k, 0.1 * k, Color("5cc25c"))
		"saw":
			var pts := PackedVector2Array()
			for i in 24:
				var a := i / 24.0 * TAU
				pts.append(c + Vector2(cos(a), sin(a)) * k * (0.45 if i % 2 == 0 else 0.33))
			draw_colored_polygon(pts, Color("e8e4f0"))
			pts.append(pts[0])
			draw_polyline(pts, INKC, 1.5 * u)
			draw_circle(c, 0.12 * k, Color("6f6482"))
		"mine":
			for i in 8:
				var a := i / 8.0 * TAU
				draw_line(c, c + Vector2(cos(a), sin(a)) * k * 0.45, Color("4a4458"), 2.5 * u)
			draw_circle(c, 0.28 * k, Color("5b5368"))
			draw_circle(c + Vector2(0, -0.32) * k, 0.09 * k, Color("ff3355"))
		"slime":
			draw_set_transform(c, 0, Vector2(1, 0.45))
			draw_circle(Vector2.ZERO, 0.45 * k, Color("86e65f"))
			draw_set_transform(Vector2.ZERO)
			draw_circle(c + Vector2(-0.12, -0.04) * k, 0.06 * k, INKC)
			draw_circle(c + Vector2(0.12, -0.04) * k, 0.06 * k, INKC)
		"boost":
			draw_rect(Rect2(c + Vector2(-0.04, 0.0) * k, Vector2(0.08, 0.45) * k), Color("fff7e8"))
			draw_circle(c + Vector2(0, -0.12) * k, 0.3 * k, Color("ff6fa8"))
			draw_arc(c + Vector2(0, -0.12) * k, 0.17 * k, 0, 4.5, 12, Color.WHITE, 2.0 * u)
		"shield":
			draw_circle(c, 0.4 * k, Color("7fd6ff"))
			draw_circle(c, 0.33 * k, Color("b9ecff"))
			draw_circle(c + Vector2(-0.14, -0.14) * k, 0.08 * k, Color.WHITE)

# ------------------------------------------------------------------ draw
func _draw() -> void:
	var vs := get_viewport_rect().size
	u = vs.y / 225.0
	W = vs.x / u
	# screen blood
	for s in screen_blood:
		var a := clampf(s.life / 1.2, 0.0, 1.0) * 0.88
		var col := Color(0.59, 0.0, 0.05, a)
		C(s.x, s.y, s.r, col)
		for b in s.blobs:
			C(s.x + b.x, s.y + b.y, b.z, col)
		for d in s.drips:
			var l := minf(d.len, 60.0)
			draw_rect(Rect2((s.x + d.dx - d.w / 2.0) * u, s.y * u, d.w * u, l * u), col)
			C(s.x + d.dx, s.y + l, d.w * 0.75, col)
		C(s.x - s.r * 0.2, s.y - s.r * 0.2, s.r * 0.55, Color(0.35, 0.0, 0.03, a * 0.6))
	if race.hit_flash > 0.0:
		var fc := Color(0.8, 0.0, 0.08) if race.gore_level > 0 else Color(1.0, 0.9, 0.43)
		for i in 6:
			var inset := i * 6.0
			draw_rect(Rect2(inset * u, inset * u, (W - inset * 2.0) * u, (225.0 - inset * 2.0) * u), Color(fc, race.hit_flash * 0.18), false, 6.0 * u)
	if race.state == "menu" or race.player == null:
		return
	var P: Kart = race.player
	var CX := W / 2.0
	var RX := W - 10.0
	T("LAP %d/%d" % [clampi(P.lap + 1, 1, race.laps), race.laps], 10, 20, 15)
	T(fmt(0.0 if race.state == "countdown" else (P.finish_time if P.finished else race.race_time)), 10, 36, 12, HORIZONTAL_ALIGNMENT_LEFT, YELLOW)
	if P.last_lap >= 0.0:
		T("last %s · best %s" % [fmt(P.last_lap), fmt(P.best_lap)], 10, 47, 7)
	if race.mode == "tt":
		var rec: float = race.record_for(race.map_idx)
		T("record " + (fmt(rec) if rec > 0.0 else "none yet"), 10, 58, 7, HORIZONTAL_ALIGNMENT_LEFT, YELLOW)
	elif race.mode == "gp":
		T("Grand Prix · race %d/4" % (race.gp_round + 1), 10, 58, 7, HORIZONTAL_ALIGNMENT_LEFT, YELLOW)
	for i in race.order.size():
		var k: Kart = race.order[i]
		var y: float = 62.0 + i * 11.0
		C(14, y - 3, 4.6, INKC)
		C(14, y - 3, 3.6, k.sp.fur)
		C(14, y - 3, 1.6, k.sp.kart)
		T("%d. %s%s" % [i + 1, k.sp.name, " ☠" if (k.ko > 0.0 and not k.drown) else ""], 22, y, 7.5, HORIZONTAL_ALIGNMENT_LEFT, YELLOW if k.is_player else Color.WHITE)
	var r := P.rank + 1
	T(ordinal(r), RX, 42, 36, HORIZONTAL_ALIGNMENT_RIGHT, RANKCOL[r - 1])
	T("of %d" % race.racers.size(), RX, 54, 8, HORIZONTAL_ALIGNMENT_RIGHT)
	# item slots
	var cs := P.cur_slot()
	var rs := P.free_slot() if P.roulette > 0.0 else -1
	for si in 2:
		var act := si == (P.sel if cs < 0 else cs)
		var bs := 36.0 if act else 28.0
		var bx := CX + (21.0 if si else -21.0) - bs / 2.0
		var yy := 6.0 + (0.0 if act else 4.0)
		RR(bx, yy, bs, bs, Color(1, 0.89, 0.43, 0.28) if act else Color(1, 1, 1, 0.16), YELLOW if act else Color(1, 1, 1, 0.7), 3.0 if act else 1.8, 8)
		var it = null
		if si == rs:
			it = race.ITEMS[int(race.t * 14.0) % 6]
		elif P.items[si] != null:
			it = P.items[si]
		if it != null:
			icon(it, bx + bs / 2.0, yy + bs / 2.0, bs * 0.85)
		T(str(si + 1), bx + 3, yy + bs - 3, 6, HORIZONTAL_ALIGNMENT_LEFT, YELLOW if act else Color.WHITE)
	var ci = P.cur_item()
	if ci != null:
		var hint := "" if touch_mode else " (hold Up/Down to aim)"
		var sw := ""
		if P.items[0] != null and P.items[1] != null:
			sw = " · tap to swap" if touch_mode else " · Q swap"
		T(race.ITEM_NAME[ci] + ("" if touch_mode else " — SPACE") + hint + sw, CX, 54, 7, HORIZONTAL_ALIGNMENT_CENTER)
	if P.shield > 0.0:
		T("shield %ds" % ceili(P.shield), CX, 64 if ci != null else 54, 7, HORIZONTAL_ALIGNMENT_CENTER, Color("9fe3ff"))
	# minimap
	_draw_minimap(Vector2(RX - 64, 62) if touch_mode else Vector2(8, 225 - 80), 64.0 if touch_mode else 72.0)
	# speed
	var spd := "%d km/h" % roundi(absf(P.speed) * 3.6)
	if touch_mode:
		T(spd, CX, 220, 10, HORIZONTAL_ALIGNMENT_CENTER, Color("ff8ad0") if P.boost > 0.0 else Color.WHITE)
	else:
		T("%d" % roundi(absf(P.speed) * 3.6), RX, 212, 18, HORIZONTAL_ALIGNMENT_RIGHT, Color("ff8ad0") if P.boost > 0.0 else Color.WHITE)
		T("km/h", RX, 220, 6, HORIZONTAL_ALIGNMENT_RIGHT)
	if P.drift_tier > 0:
		var tn: String = ["", "MINI-TURBO", "SUPER MINI-TURBO", "ULTRA MINI-TURBO!"][P.drift_tier]
		T(tn, CX if touch_mode else RX, 188, 7, HORIZONTAL_ALIGNMENT_CENTER if touch_mode else HORIZONTAL_ALIGNMENT_RIGHT, Kart.TIER_COL[P.drift_tier])
	# centre messages
	if race.state == "countdown":
		var n := ceili(race.cd)
		if n > 0 and n <= 3:
			var sc: float = 1.0 + (race.cd - floorf(race.cd)) * 0.5
			T(str(n), CX, 105, 44 * sc, HORIZONTAL_ALIGNMENT_CENTER, [Color("7be05a"), YELLOW, Color("ff7a8a")][n - 1])
	if race.go_t > 0.0:
		T("GO!", CX, 105, 44 + (1.0 - race.go_t) * 20.0, HORIZONTAL_ALIGNMENT_CENTER, Color("7be05a"))
	if P.ko > 0.0 and not P.drown and race.gore_level > 0:
		T("SPLAT!", CX, 110, 30, HORIZONTAL_ALIGNMENT_CENTER, Color("ff5a6e"))
	for i in race.msgs.size():
		var m: Dictionary = race.msgs[i]
		T(m.text, CX, 78 + i * 13, 9.5, HORIZONTAL_ALIGNMENT_CENTER, Color(m.col, clampf(m.t * 2.0, 0.0, 1.0)))
	if race.state == "race" and P.ko <= 0.0 and P.speed > 2.5:
		var tg: Vector2 = race.world.T[P.seg]
		if P.forward().dot(tg) < -0.4 and int(race.t * 3.0) % 2 == 0:
			T("WRONG WAY!", CX, 130, 16, HORIZONTAL_ALIGNMENT_CENTER, Color("ff7a8a"))
	if P.off_t > 2.5 and P.ko <= 0.0 and race.state == "race":
		T("Lost? Hang tight…" if touch_mode else "Lost? Press R", CX, 150, 9, HORIZONTAL_ALIGNMENT_CENTER)
	if race.state == "finished":
		T("FINISH!", CX, 118, 34, HORIZONTAL_ALIGNMENT_CENTER, YELLOW)
	if Sfx.muted:
		T("muted", RX, 70, 7, HORIZONTAL_ALIGNMENT_RIGHT)
	if touch_mode:
		_draw_touch()

func _draw_minimap(o: Vector2, s: float) -> void:
	var w: WorldGen = race.world
	var sc := s / (2.0 * w.map_half)
	var lw := clampf(sc * 3.0, 0.45, 1.6)
	var c := o + Vector2(s, s) * 0.5
	var pts := PackedVector2Array()
	for i in range(0, w.N + 1, 4):
		var p := w.P[i % w.N]
		pts.append((c + p * sc) * u)
	draw_polyline(pts, Color(0.16, 0.09, 0.19, 0.75), 7.0 * u * lw)
	draw_polyline(pts, Color.WHITE, 3.5 * u * lw)
	C(c.x + w.P[0].x * sc, c.y + w.P[0].y * sc, 2.5, YELLOW)
	for p in race.projectiles:
		if p.speed > 0.0:
			continue
		var q: Vector2 = c + p.pos * sc
		draw_rect(Rect2((q - Vector2(1.5, 1.5)) * u, Vector2(3, 3) * u), Color("ff3355") if p.type == "mine" else Color("7be05a"))
	var rev: Array = race.order.duplicate()
	rev.reverse()
	for k in rev:
		var kp: Vector2 = Vector2(k.ko_pos.x, k.ko_pos.z) if k.ko > 0.0 else k.pos
		var q: Vector2 = c + kp * sc
		var rr := 4.2 if k.is_player else 3.2
		C(q.x, q.y, rr + 1.0, Color.WHITE if k.is_player else INKC)
		C(q.x, q.y, rr, k.sp.kart)

func _draw_touch() -> void:
	if race.state != "race" and race.state != "countdown" and race.state != "finished":
		return
	for nm in ["brake", "drift", "item"]:
		var b := _btn_pos(nm)
		var held: bool = (nm == "brake" and race.touch_brake) or (nm == "drift" and race.touch_drift)
		var base := Color(1, 0.31, 0.55, 0.5) if nm == "item" else Color(0.16, 0.09, 0.19, 0.35)
		C(b.x, b.y, b.z, Color(1, 1, 1, 0.5) if held else base)
		draw_arc(Vector2(b.x, b.y) * u, b.z * u, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0 * u)
		T(nm.to_upper(), b.x, b.y + 3.5, 9 if nm != "item" else 12, HORIZONTAL_ALIGNMENT_CENTER)
	var pb := _btn_pos("pause")
	C(pb.x, pb.y, pb.z, Color(0.16, 0.09, 0.19, 0.4))
	draw_arc(Vector2(pb.x, pb.y) * u, pb.z * u, 0, TAU, 24, Color(1, 1, 1, 0.6), 1.5 * u)
	T("II", pb.x, pb.y + 3.5, 9, HORIZONTAL_ALIGNMENT_CENTER)
	if joy_active:
		C(joy_origin.x, joy_origin.y, 26, Color(0.16, 0.09, 0.19, 0.25))
		draw_arc(joy_origin * u, 26 * u, 0, TAU, 32, Color(1, 1, 1, 0.45), 2.0 * u)
		C(joy_pos.x, joy_pos.y, 11, Color(1, 1, 1, 0.7))

func _process(dt: float) -> void:
	if race == null or race.paused:
		return
	for s in screen_blood:
		s.life -= dt
		for d in s.drips:
			d.len += d.sp * dt
	screen_blood = screen_blood.filter(func(s): return s.life > 0.0)

# ------------------------------------------------------------------ online
var online_status: Label
var code_edit: LineEdit
var lobby_code: Label
var lobby_list: Label
var lobby_track: Label
var lobby_start: Button
var lobby_wait: Label
var lobby_host_box: Control
var lobby_status: Label
var lobby_invite: Button

func invite_link() -> String:
	var base := "https://corysyx.github.io/carnage-karts-godot/"
	if OS.has_feature("web"):
		base = str(JavaScriptBridge.eval("location.origin + location.pathname", true))
	return base + "?join=" + race.net.code

func _copy_invite() -> void:
	var link := invite_link()
	Sfx.play("pick", 0.5)
	if OS.has_feature("web"):
		# share sheet on phones, clipboard elsewhere
		JavaScriptBridge.eval("(function(u){if(navigator.share){navigator.share({title:'Carnage Karts',text:'Race me in Carnage Karts!',url:u}).catch(function(){});}else if(navigator.clipboard){navigator.clipboard.writeText(u);}})(" + JSON.stringify(link) + ")", true)
	else:
		DisplayServer.clipboard_set(link)
	lobby_invite.text = "Link ready!"
	get_tree().create_timer(2.0).timeout.connect(func(): lobby_invite.text = "Copy invite link")

func _build_online() -> void:
	var o := _overlay()
	screens["online"] = o
	var vb: VBoxContainer = o.get_meta("vb")
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(_label("Play Online", 46, YELLOW, 14))
	vb.add_child(_label("Race your friends. One of you hosts, the rest join with the room code.\nEmpty places are filled by AI critters (up to 6 racers).", 16, Color.WHITE, 5))
	var host := _button("Host a game", Color("ff4f8b"), 28)
	host.custom_minimum_size = Vector2(300, 60)
	host.pressed.connect(func():
		Sfx.play("pick", 0.5)
		race.net.host()
		show_screen("lobby"))
	var cc := CenterContainer.new()
	cc.add_child(host)
	vb.add_child(cc)
	vb.add_child(_label("or join a friend", 18, Color(1, 1, 1, 0.8), 5))
	var hb := _hbox(10)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "CODE"
	code_edit.max_length = 4
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.custom_minimum_size = Vector2(170, 56)
	code_edit.add_theme_font_size_override("font_size", 30)
	code_edit.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.92), 14, Color("2a1830")))
	code_edit.add_theme_stylebox_override("focus", _style(Color.WHITE, 14, Color("ff4f8b")))
	code_edit.add_theme_color_override("font_color", Color("2a1830"))
	code_edit.add_theme_color_override("font_placeholder_color", Color(0.16, 0.09, 0.19, 0.35))
	code_edit.text_changed.connect(func(t: String):
		var up := t.to_upper()
		if up != t:
			var c := code_edit.caret_column
			code_edit.text = up
			code_edit.caret_column = c)
	code_edit.text_submitted.connect(func(_t): _do_join())
	var join := _button("Join", Color("38b6a3"), 26)
	join.custom_minimum_size = Vector2(130, 56)
	join.pressed.connect(_do_join)
	hb.add_child(code_edit)
	hb.add_child(join)
	vb.add_child(hb)
	# on-screen letter pad: phone browsers don't open their keyboard for the game
	var pad := GridContainer.new()
	pad.columns = 10
	pad.add_theme_constant_override("h_separation", 5)
	pad.add_theme_constant_override("v_separation", 4)
	var keys: Array = Array("1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")) + ["←"]
	for ch in keys:
		var kb := _button(ch, Color(1, 1, 1, 0.18) if ch != "←" else Color("ff4f6e"), 18)
		kb.custom_minimum_size = Vector2(52, 34)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb: StyleBoxFlat = kb.get_theme_stylebox(st).duplicate()
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			kb.add_theme_stylebox_override(st, sb)
		kb.focus_mode = Control.FOCUS_NONE
		var c: String = ch
		kb.pressed.connect(func():
			Sfx.play("get", 0.3)
			if c == "←":
				code_edit.text = code_edit.text.substr(0, maxi(0, code_edit.text.length() - 1))
			elif code_edit.text.length() < 4:
				code_edit.text += c
			code_edit.caret_column = code_edit.text.length())
		pad.add_child(kb)
	var padc := CenterContainer.new()
	padc.add_child(pad)
	vb.add_child(padc)
	online_status = _label("", 18, Color("ffd2a0"), 5)
	online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_status.custom_minimum_size = Vector2(620, 0)
	vb.add_child(online_status)
	_back_button(vb)

func _do_join() -> void:
	if code_edit.text.strip_edges().length() < 4 and OS.has_feature("web"):
		online_status.text = "Type the 4-letter room code your friend sees."
		return
	Sfx.play("pick", 0.5)
	race.net.join(code_edit.text)
	show_screen("lobby")

func _build_lobby() -> void:
	var o := _overlay()
	screens["lobby"] = o
	var vb: VBoxContainer = o.get_meta("vb")
	lobby_code = _label("", 44, YELLOW, 14)
	vb.add_child(lobby_code)
	lobby_status = _label("", 17, Color(1, 1, 1, 0.85), 5)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_status.custom_minimum_size = Vector2(640, 0)
	vb.add_child(lobby_status)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.35), 16, Color(1, 1, 1, 0.15)))
	lobby_list = _label("", 22, Color.WHITE, 6)
	lobby_list.custom_minimum_size = Vector2(360, 0)
	pc.add_child(lobby_list)
	var pcc := CenterContainer.new()
	pcc.add_child(pc)
	vb.add_child(pcc)
	var ch := _button("Change critter", Color("38b6a3"), 20)
	ch.pressed.connect(func(): Sfx.play("get", 0.4); show_screen("character"))
	lobby_invite = _button("Copy invite link", Color("f5a623"), 20)
	lobby_invite.pressed.connect(_copy_invite)
	var chc := _hbox(10)
	chc.add_child(ch)
	chc.add_child(lobby_invite)
	vb.add_child(chc)
	lobby_track = _label("", 22, Color.WHITE, 6)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	var th := _hbox(10)
	var prev := _button("◀", Color("6c5ce7"), 22)
	prev.pressed.connect(func(): _lobby_track(-1, 0))
	var nx := _button("▶", Color("6c5ce7"), 22)
	nx.pressed.connect(func(): _lobby_track(1, 0))
	var lm := _button("− lap", Color("6c5ce7"), 18)
	lm.pressed.connect(func(): _lobby_track(0, -1))
	var lp := _button("+ lap", Color("6c5ce7"), 18)
	lp.pressed.connect(func(): _lobby_track(0, 1))
	th.add_child(prev)
	th.add_child(lobby_track)
	th.add_child(nx)
	th.add_child(lm)
	th.add_child(lp)
	hv.add_child(th)
	lobby_host_box = hv
	vb.add_child(hv)
	lobby_wait = _label("", 22, Color.WHITE, 6)
	vb.add_child(lobby_wait)
	var hb := _hbox(12)
	var leave := _button("Leave", Color("6c5ce7"), 22)
	leave.pressed.connect(func():
		race.net.leave()
		history.clear()
		show_screen("online", false))
	lobby_start = _button("Start Race", Color("ff4f8b"), 30)
	lobby_start.custom_minimum_size = Vector2(260, 62)
	lobby_start.pressed.connect(func(): race.net.start())
	hb.add_child(leave)
	hb.add_child(lobby_start)
	vb.add_child(hb)
	race.net.lobby_changed.connect(_refresh_lobby)
	race.net.status_changed.connect(func(_t): _refresh_lobby())

func _lobby_track(dm: int, dl: int) -> void:
	var n: Net = race.net
	if not n.is_host:
		return
	Sfx.play("get", 0.4)
	var m := (n.lobby_map + dm + Tracks.THEMES.size()) % Tracks.THEMES.size()
	var l := clampi(n.lobby_laps + dl, 1, 5)
	n.set_track(m, l)

func _refresh_lobby() -> void:
	if lobby_code == null:
		return
	var n: Net = race.net
	if n.active and n.lobby_map != race.map_idx and race.state == "menu" and n.players.size() > 0:
		race.load_map(n.lobby_map)
	var connected := n.ready_in_room()
	if n.is_host:
		lobby_code.text = ("Room code: " + n.code) if connected else "Opening room…"
	else:
		lobby_code.text = ("Room " + n.code) if connected else ("Joining " + n.code + "…")
	if not n.active:
		lobby_code.text = "Not connected"
	var stat := n.status
	if n.is_host and connected:
		stat = "Tell your friends to open the game, tap Play Online and type " + n.code + "." if n.players.size() < 2 else "%d players in the room." % n.players.size()
	lobby_status.text = stat
	var ids := n.players.keys()
	ids.sort()
	var lines := []
	for id in ids:
		var sp: Dictionary = Critters.SPECIES[n.players[id].sp]
		lines.append("%s  %s%s%s" % [n.name_of(id), sp.name, "  (host)" if id == 1 else "", "  ← you" if id == n.my_id else ""])
	var free := 6 - ids.size()
	if ids.size() > 0 and free > 0:
		lines.append("+ %d AI critter%s" % [free, "" if free == 1 else "s"])
	lobby_list.text = "\n".join(lines) if lines.size() > 0 else "…"
	var th: Dictionary = Tracks.THEMES[n.lobby_map]
	lobby_track.text = "%s · %d lap%s" % [th.name, n.lobby_laps, "" if n.lobby_laps == 1 else "s"]
	lobby_host_box.visible = connected
	for c in lobby_host_box.get_child(0).get_children():
		if c is Button:
			c.visible = n.is_host
	lobby_start.visible = n.is_host and connected
	lobby_invite.visible = connected and not n.use_enet
	lobby_wait.visible = connected and not n.is_host
	lobby_wait.text = "Waiting for the host to start…"
	if online_status:
		online_status.text = "" if n.active else n.status

func on_net_status(why: String) -> void:
	if online_status:
		online_status.text = why
	if cur_screen == "lobby" or race.state == "menu":
		history.clear()
		show_screen("online", false)
		online_status.text = why
