class_name Net
extends Node
## Online multiplayer for friends.
##
## Players share a 4-letter room code. All traffic goes through a free public
## MQTT relay over a secure WebSocket (MqttPeer), so it works on any network.
## The host is the server: clients only talk to it and it relays.
## Native test builds can use ENet instead (--enet).
##
## Who decides what:
##  - each player drives their own kart and reports its state (~20 Hz)
##  - the host runs the AI karts and sends everyone a snapshot of all karts
##  - item use, hits and item-box pickups are sent as reliable events; the
##    kart's owner decides whether a projectile hit it

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const PREFIX := "carnagekarts-"
const MAX_PLAYERS := 6
const SEND_DT := 0.066

signal status_changed(text: String)
signal lobby_changed

var race: Node
var active := false            # in an online session (lobby or race)
var is_host := false
var in_race := false
var code := ""
var my_id := 0
var status := ""
## net id -> {"sp": int, "name": String}
var players := {}
var lobby_map := 0
var lobby_laps := 3

var broker_url := MqttPeer.DEFAULT_BROKER
var use_enet := false          # native test transport
var relay: MqttPeer
var join_t := -1.0
var send_t := 0.0
var latest := {}               # slot -> PackedFloat32Array (host: last state from clients)
var rx_t := 0.0                # client: time since the last snapshot from the host

func _ready() -> void:
	name = "Net"
	use_enet = "--enet" in OS.get_cmdline_user_args()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): fail("Couldn't connect to that room."))
	multiplayer.server_disconnected.connect(func(): fail("The host left the game."))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--relay="):
			broker_url = a.substr(8)
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('relay') || ''", true))
		if q != "" and q != "null":
			broker_url = q

func _set_status(s: String) -> void:
	if race and race.autotest:
		print("[net %d] %s" % [my_id, s])
	status = s
	status_changed.emit(s)

## In a room and ready (host: room open, client: accepted by the host).
func ready_in_room() -> bool:
	if not active:
		return false
	if is_host:
		return use_enet or (relay != null and relay.status == MultiplayerPeer.CONNECTION_CONNECTED)
	return players.has(my_id)

func my_name() -> String:
	return "P%d" % _player_no(my_id)

func _player_no(id: int) -> int:
	var ids := players.keys()
	ids.sort()
	return ids.find(id) + 1

func name_of(id: int) -> String:
	var n := _player_no(id)
	return "P%d" % n if n > 0 else "P?"

# ------------------------------------------------------------------ host / join
func _new_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var c := ""
	for i in 4:
		c += CODE_CHARS[rng.randi() % CODE_CHARS.length()]
	return c

func _start_relay(room: String, as_host: bool) -> bool:
	relay = MqttPeer.new()
	relay.refused.connect(func(why: String):
		fail("That race has already started. Try again when it's over." if why == "racing" else "That room is full (6 players)."))
	relay.broker_failed.connect(func():
		if active:
			fail("Lost connection to the host." if in_race else "Couldn't reach the online relay. Check your internet connection."))
	if relay.start(broker_url, room, as_host) != OK:
		fail("Couldn't reach the online relay.")
		return false
	multiplayer.multiplayer_peer = relay
	return true

func host() -> void:
	leave()
	active = true
	is_host = true
	my_id = 1
	players = {1: {"sp": race.selected}}
	lobby_map = race.map_idx
	lobby_laps = race.laps
	if use_enet:
		var e := ENetMultiplayerPeer.new()
		var port := 24680
		if e.create_server(port, MAX_PLAYERS) != OK:
			fail("Couldn't open a game on port %d." % port)
			return
		multiplayer.multiplayer_peer = e
		code = "LAN"
		_set_status("Room open LAN")
		lobby_changed.emit()
		return
	code = _new_room_code()
	if _start_relay(code, true):
		_set_status("Opening room…")
		lobby_changed.emit()

func join(room: String) -> void:
	leave()
	room = room.strip_edges().to_upper()
	active = true
	is_host = false
	if use_enet:
		var e := ENetMultiplayerPeer.new()
		if e.create_client(room if room.contains(".") else "127.0.0.1", 24680) != OK:
			fail("Couldn't reach that game.")
			return
		multiplayer.multiplayer_peer = e
		code = "LAN"
		_set_status("Connecting…")
		return
	if room.length() != 4:
		fail("Room codes are 4 letters.")
		return
	code = room
	if _start_relay(code, false):
		join_t = 0.0
		_set_status("Looking for room %s…" % code)

func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	relay = null
	active = false
	in_race = false
	is_host = false
	players.clear()
	latest.clear()
	join_t = -1.0
	my_id = 0

func fail(why: String) -> void:
	var was_racing := in_race
	var was_active := active
	leave()
	_set_status(why)
	if was_active:
		race.on_net_failed(why, was_racing)

func _process(dt: float) -> void:
	if is_host and relay and status == "Opening room…" and relay.status == MultiplayerPeer.CONNECTION_CONNECTED:
		_set_status("Room open " + code)
		lobby_changed.emit()
	if join_t >= 0.0:
		join_t += dt
		if join_t > 15.0:
			fail("No room called %s. Check the code, and make sure the host is still in the lobby." % code)
			return
	if in_race:
		rx_t += dt
		if not is_host and rx_t > 8.0:
			fail("Lost connection to the host.")
			return
		if is_host:
			for k in race.racers:
				if k.puppet and k.net_owner != 0 and k.net_age > 6.0:
					var id: int = k.net_owner
					if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
						(multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id).peer_disconnect_now()
					elif relay:
						relay._disconnect_peer(id, true)
					_on_peer_disconnected(id)
		send_t += dt
		if send_t >= SEND_DT:
			send_t = 0.0
			_send_states()


# ------------------------------------------------------------------ connections
func _on_peer_connected(id: int) -> void:
	if not is_host and id == 1:
		_on_connected()

func _on_connected() -> void:
	if status == "Connected":
		return
	join_t = -1.0
	my_id = multiplayer.get_unique_id()
	_set_status("Connected")
	c_hello.rpc_id(1, race.selected)

func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	players.erase(id)
	if in_race:
		race.net_player_left(id)
	else:
		_broadcast_lobby()

# ------------------------------------------------------------------ lobby
func _free_sp(want: int, for_id: int) -> int:
	var taken := []
	for id in players:
		if id != for_id:
			taken.append(int(players[id].sp))
	if not want in taken:
		return want
	for i in Critters.SPECIES.size():
		if not i in taken:
			return i
	return want

@rpc("any_peer", "reliable")
func c_hello(sp: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if in_race or players.size() >= MAX_PLAYERS:
		return
	players[id] = {"sp": _free_sp(sp, id)}
	_broadcast_lobby()

@rpc("any_peer", "reliable")
func c_pick(sp: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].sp = _free_sp(sp, id)
		_broadcast_lobby()

## Local player picked a character (from the character screen).
func pick(sp: int) -> void:
	if is_host:
		players[1].sp = _free_sp(sp, 1)
		race.selected = players[1].sp
		_broadcast_lobby()
	elif my_id != 0:
		c_pick.rpc_id(1, sp)

func set_track(map: int, laps: int) -> void:
	if is_host:
		lobby_map = map
		lobby_laps = laps
		_broadcast_lobby()

func _broadcast_lobby() -> void:
	var arr := []
	for id in players:
		arr.append([id, players[id].sp])
	h_lobby.rpc(arr, lobby_map, lobby_laps)
	h_lobby(arr, lobby_map, lobby_laps)

@rpc("authority", "reliable")
func h_lobby(arr: Array, map: int, laps: int) -> void:
	players.clear()
	for e in arr:
		players[int(e[0])] = {"sp": int(e[1])}
	lobby_map = map
	lobby_laps = laps
	if players.has(my_id):
		race.selected = players[my_id].sp
	if not in_race:
		_set_status("In room %s" % code)
	lobby_changed.emit()

## Host: start a race with everyone in the lobby. Humans take the back of the
## grid, AI critters fill the other places.
func start() -> void:
	if not is_host:
		return
	var ids := players.keys()
	ids.sort()
	var used := []
	for id in ids:
		used.append(int(players[id].sp))
	var others := []
	for i in Critters.SPECIES.size():
		if not i in used:
			others.append(i)
	others.shuffle()
	var roster := []
	for slot in 6:
		roster.append([0, 0])
	var hs := 5
	for id in ids:
		roster[hs] = [int(players[id].sp), id]
		hs -= 1
	var oi := 0
	for slot in 6:
		if roster[slot][1] == 0:
			roster[slot] = [others[oi % others.size()], 0]
			oi += 1
	h_start.rpc(lobby_map, lobby_laps, roster, race.difficulty)
	h_start(lobby_map, lobby_laps, roster, race.difficulty)

@rpc("authority", "reliable")
func h_start(map: int, laps: int, roster: Array, diff: int) -> void:
	in_race = true
	if relay:
		relay.refusing = true
	rx_t = 0.0
	if race.autotest:
		print("[net %d] start map=%d laps=%d roster=%s" % [my_id, map, laps, roster])
	latest.clear()
	send_t = 0.0
	race.start_online(map, laps, roster, diff)

func back_to_lobby() -> void:
	if is_host:
		h_to_lobby.rpc()
		h_to_lobby()

@rpc("authority", "reliable")
func h_to_lobby() -> void:
	in_race = false
	if relay:
		relay.refusing = false
	race.net_to_lobby()
	if is_host:
		_broadcast_lobby()

# ------------------------------------------------------------------ race sync
func _send_states() -> void:
	if is_host:
		var snap := []
		for k in race.racers:
			snap.append(k.net_pack())
		h_snap.rpc(snap)
	else:
		for k in race.racers:
			if not k.puppet:
				c_state.rpc_id(1, k.net_pack())

@rpc("any_peer", "unreliable_ordered")
func c_state(d: PackedFloat32Array) -> void:
	if not is_host or not in_race:
		return
	var k: Kart = race.kart_by_slot(int(d[0]))
	if k and k.puppet and k.net_owner == multiplayer.get_remote_sender_id():
		k.net_apply(d)

@rpc("authority", "unreliable_ordered")
func h_snap(snap: Array) -> void:
	if not in_race:
		return
	rx_t = 0.0
	for d in snap:
		var k: Kart = race.kart_by_slot(int(d[0]))
		if k and k.puppet:
			k.net_apply(d)

func send_item(args: Array) -> void:
	ev_item.rpc(args)

func send_hit(args: Array) -> void:
	ev_hit.rpc(args)

func send_box(i: int) -> void:
	ev_box.rpc(i)

func send_kill(a: int, b: int) -> void:
	ev_kill.rpc(a, b)

@rpc("any_peer", "reliable")
func ev_item(args: Array) -> void:
	if in_race:
		race.net_item(args)

@rpc("any_peer", "reliable")
func ev_hit(args: Array) -> void:
	if in_race:
		race.net_hit(args)

@rpc("any_peer", "reliable")
func ev_box(i: int) -> void:
	if in_race:
		race.net_box(i)

@rpc("any_peer", "reliable")
func ev_kill(a: int, b: int) -> void:
	if in_race:
		race.net_kill(a, b)
