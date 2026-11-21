class_name Sfx
extends Node
## Tiny sound player: a pool of players for one-shot effects plus a looping engine.

static var inst: Sfx
static var muted := false
var streams := {}
var pool: Array[AudioStreamPlayer] = []
var engine: AudioStreamPlayer
var next := 0

func _ready() -> void:
	inst = self
	for n in ["pick", "get", "fire", "splat", "boom", "boing", "beep", "beep_hi", "shield", "boost", "bump", "splash"]:
		streams[n] = load("res://assets/sfx/%s.wav" % n)
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
	if inst == null or muted or vol <= 0.02 or not inst.streams.has(n):
		return
	var p := inst.pool[inst.next]
	inst.next = (inst.next + 1) % inst.pool.size()
	p.stream = inst.streams[n]
	p.volume_db = linear_to_db(clampf(vol, 0.0, 1.0)) - 4.0
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

static func engine_update(on: bool, speed: float, boosting: bool) -> void:
	if inst == null:
		return
	var e := inst.engine
	if on and not muted:
		if not e.playing:
			e.play()
		e.volume_db = -16.0
		e.pitch_scale = clampf(0.9 + absf(speed) * 0.11 + (0.6 if boosting else 0.0), 0.5, 4.0)
	elif e.playing:
		e.stop()
