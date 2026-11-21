class_name Sfx
extends Node
## Tiny sound player: a pool of players for one-shot effects plus a looping engine.

static var inst: Sfx
static var muted := false
static var volume := 1.0
var streams := {}
var pool: Array[AudioStreamPlayer] = []
var engine: AudioStreamPlayer
var next := 0

func _ready() -> void:
	inst = self
	# Synthesised fallbacks (tools/make_sfx.py), replaced by ElevenLabs recordings
	# in assets/sfx/el/ where they exist. Several takes of a sound = random pick each time.
	for n in ["pick", "get", "fire", "splat", "boom", "boing", "beep", "beep_hi", "shield", "boost", "bump", "splash"]:
		var takes: Array = []
		for i in range(1, 9):
			var path := "res://assets/sfx/el/%s%d.ogg" % [n, i]
			if ResourceLoader.exists(path):
				takes.append(load(path))
		if takes.is_empty():
			takes.append(load("res://assets/sfx/%s.wav" % n))
		streams[n] = takes
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	engine = AudioStreamPlayer.new()
	var eng: AudioStreamWAV = load("res://assets/sfx/engine.wav").duplicate()
	eng.loop_mode = AudioStreamWAV.LOOP_FORWARD
	eng.loop_begin = 0
	eng.loop_end = eng.data.size() / 2
	engine.stream = eng
	engine.volume_db = -80.0
	add_child(engine)

static func play(n: String, vol := 1.0) -> void:
	if inst == null or muted or volume <= 0.01 or vol <= 0.02 or not inst.streams.has(n):
		return
	var p := inst.pool[inst.next]
	inst.next = (inst.next + 1) % inst.pool.size()
	p.stream = inst.streams[n].pick_random()
	p.volume_db = linear_to_db(clampf(vol * volume, 0.001, 1.0)) - 4.0
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

static func engine_update(on: bool, speed: float, boosting: bool) -> void:
	if inst == null:
		return
	var e := inst.engine
	if on and not muted and volume > 0.01:
		if not e.playing:
			e.play()
		e.volume_db = -16.0 + linear_to_db(maxf(volume, 0.001))
		e.pitch_scale = clampf(0.9 + absf(speed) * 0.11 + (0.6 if boosting else 0.0), 0.5, 4.0)
	elif e.playing:
		e.stop()
