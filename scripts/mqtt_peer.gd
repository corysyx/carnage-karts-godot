class_name MqttPeer
extends MultiplayerPeerExtension
## A MultiplayerPeer that sends everything through a public MQTT broker over
## a secure WebSocket. Every player only needs an ordinary outgoing web
## connection, so it works on any network (home Wi-Fi, phone data, school).
##
## Topics: carnagekarts/v2/<ROOM>/<peer id>   messages for one peer
##         carnagekarts/v2/<ROOM>/all         host -> every client
## Payload: [from u32][exclude u32][kind u8][channel u8][mode u8] + data

## Free public brokers, tried in order. Hosts use the first that answers;
## joining players look for the room on each in turn.
const BROKERS := ["wss://broker.emqx.io:8084/mqtt", "wss://test.mosquitto.org:8081/mqtt", "wss://broker.hivemq.com:8884/mqtt"]
const ROOT := "carnagekarts/v2/"
enum Kind { DATA, HELLO, WELCOME, BYE, PING, FULL }
const PING_EVERY := 1.0
const VERSION := 3          # bump when the online protocol changes
const TIMEOUT := 7.0

signal refused(reason: String)   # "full", "racing" or "noroom"
signal broker_failed

var ws := WebSocketPeer.new()
var room := ""
var my_id := 1
var server := false
var status := MultiplayerPeer.CONNECTION_DISCONNECTED
var target := 0
var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var channel := 0
var refusing := false
var max_peers := 6
var peers := {}            # id -> seconds since last heard
var inbox: Array = []      # [from, channel, mode, data]
var cur: Array = []
var rx := PackedByteArray()
var mqtt_up := false
var sub_ok := false
var hello_t := 0.0
var ping_t := 0.0
var keep_t := 0.0
var start_ms := 0
var brokers: Array = []
var bi := 0
var sub_ms := 0
var last_ms := 0

func start(broker_list: Array, room_code: String, as_server: bool) -> Error:
	room = room_code
	server = as_server
	if server:
		my_id = 1
	else:
		my_id = 2 + (randi() % 2000000000)
	brokers = broker_list
	status = MultiplayerPeer.CONNECTION_CONNECTING
	return _try(0)

func _try(i: int) -> Error:
	bi = i
	if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		ws.close()
	ws = WebSocketPeer.new()
	ws.supported_protocols = PackedStringArray(["mqtt"])
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	mqtt_up = false
	sub_ok = false
	keep_t = 0.0
	hello_t = 0.0
	rx = PackedByteArray()
	start_ms = Time.get_ticks_msec()
	_dbg("trying " + str(brokers[i]))
	return ws.connect_to_url(brokers[i])

## This broker didn't work out (or the room isn't on it): try the next one.
func _next(why: String) -> void:
	_dbg("broker %d: %s" % [bi, why])
	if bi + 1 < brokers.size():
		_try(bi + 1)
	elif why == "noroom":
		ws.close()
		status = MultiplayerPeer.CONNECTION_DISCONNECTED
		refused.emit("noroom")
	else:
		_fail()

func _topic(id: Variant) -> String:
	return ROOT + room + "/" + str(id)

# ------------------------------------------------------------------ MQTT bits
static func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var o := PackedByteArray([b.size() >> 8, b.size() & 255])
	o.append_array(b)
	return o

static func _packet(header: int, body: PackedByteArray) -> PackedByteArray:
	var o := PackedByteArray([header])
	var n := body.size()
	while true:
		var d := n % 128
		n /= 128
		if n > 0:
			d |= 128
		o.append(d)
		if n == 0:
			break
	o.append_array(body)
	return o

func _mqtt_connect() -> void:
	var body := _str("MQTT")
	body.append_array(PackedByteArray([4, 2, 0, 60]))   # v3.1.1, clean session, keepalive 60s
	body.append_array(_str("ck%d_%d" % [my_id, randi() % 1000000]))
	ws.put_packet(_packet(0x10, body))

func _subscribe(topics: Array) -> void:
	var body := PackedByteArray([0, 1])
	for t in topics:
		body.append_array(_str(t))
		body.append(0)
	ws.put_packet(_packet(0x82, body))

func _publish(topic: String, payload: PackedByteArray) -> void:
	if not mqtt_up:
		return
	var body := _str(topic)
	body.append_array(payload)
	ws.put_packet(_packet(0x30, body))

func _send(to: Variant, kind: int, data := PackedByteArray(), exclude := 0) -> void:
	var p := PackedByteArray()
	p.resize(11)
	p.encode_u32(0, my_id)
	p.encode_u32(4, exclude)
	p[8] = kind
	p[9] = channel
	p[10] = mode
	p.append_array(data)
	_publish(_topic(to), p)

func _read_mqtt() -> void:
	while true:
		if rx.size() < 2:
			return
		var mul := 1
		var rem := 0
		var i := 1
		while true:
			if i >= rx.size():
				return
			var d: int = rx[i]
			rem += (d & 127) * mul
			mul *= 128
			i += 1
			if d & 128 == 0:
				break
		if rx.size() < i + rem:
			return
		var h: int = rx[0]
		var body := rx.slice(i, i + rem)
		rx = rx.slice(i + rem)
		match h & 0xF0:
			0x20:   # CONNACK
				_dbg("connack %s" % body)
				if body.size() >= 2 and body[1] == 0:
					mqtt_up = true
					_dbg("connected to " + str(brokers[bi]))
					var subs := [_topic(my_id)]
					if not server:
						subs.append(_topic("all"))
					_subscribe(subs)
				else:
					_next("refused")
					return
			0x90:   # SUBACK
				_dbg("suback")
				sub_ok = true
				sub_ms = Time.get_ticks_msec()
				if server:
					status = MultiplayerPeer.CONNECTION_CONNECTED
				else:
					hello_t = 99.0
			0x30:
				var tl: int = (body[0] << 8) | body[1]
				var off := 2 + tl
				if h & 0x06:
					off += 2       # packet id (QoS > 0, not used)
				_on_payload(body.slice(off))

func _on_payload(p: PackedByteArray) -> void:
	if p.size() < 11:
		return
	var from := p.decode_u32(0)
	var excl := p.decode_u32(4)
	var kind: int = p[8]
	if from == my_id or excl == my_id:
		return
	if server:
		if kind == Kind.HELLO:
			if peers.has(from):
				_send(from, Kind.WELCOME)
				return
			var their_v: int = p[11] if p.size() > 11 else 0
			if their_v != VERSION or refusing or peers.size() + 1 >= max_peers:
				var why := PackedByteArray([2 if their_v != VERSION else (1 if refusing else 0)])
				_send(from, Kind.FULL, why)
				return
			peers[from] = 0.0
			_send(from, Kind.WELCOME)
			peer_connected.emit(from)
			return
		if not peers.has(from):
			return
		peers[from] = 0.0
		if kind == Kind.BYE:
			peers.erase(from)
			peer_disconnected.emit(from)
			return
	else:
		if from != 1:
			return
		if kind == Kind.WELCOME:
			if status != MultiplayerPeer.CONNECTION_CONNECTED:
				status = MultiplayerPeer.CONNECTION_CONNECTED
				peers[1] = 0.0
				peer_connected.emit(1)
			return
		if kind == Kind.FULL:
			var code: int = p[11] if p.size() > 11 else 0
			refused.emit(["full", "racing", "version"][clampi(code, 0, 2)])
			_fail()
			return
		if not peers.has(1):
			return
		peers[1] = 0.0
		if kind == Kind.BYE:
			_lost_server()
			return
	if kind == Kind.DATA:
		inbox.append([from, p[9], p[10], p.slice(11)])

var debug := false
func _dbg(t: String) -> void:
	if debug:
		print("[relay] ", t)

func _fail() -> void:
	_dbg("fail: ws state %d, mqtt_up %s, sub %s" % [ws.get_ready_state(), mqtt_up, sub_ok])
	status = MultiplayerPeer.CONNECTION_DISCONNECTED
	ws.close()
	broker_failed.emit()

func _lost_server() -> void:
	if peers.has(1):
		peers.erase(1)
		peer_disconnected.emit(1)
	status = MultiplayerPeer.CONNECTION_DISCONNECTED

# ------------------------------------------------------------------ MultiplayerPeer
func _poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not mqtt_up and keep_t == 0.0:
			keep_t = 0.001
			_dbg("socket open, protocol '%s'" % ws.get_selected_protocol())
			_mqtt_connect()
		while ws.get_available_packet_count() > 0:
			rx.append_array(ws.get_packet())
		_read_mqtt()
	elif st == WebSocketPeer.STATE_CLOSED:
		_dbg("socket closed code %d reason '%s'" % [ws.get_close_code(), ws.get_close_reason()])
		if status == MultiplayerPeer.CONNECTION_CONNECTING:
			_next("closed")
		elif status != MultiplayerPeer.CONNECTION_DISCONNECTED:
			if server:
				for id in peers.keys():
					peer_disconnected.emit(id)
				peers.clear()
				status = MultiplayerPeer.CONNECTION_DISCONNECTED
				broker_failed.emit()
			else:
				_lost_server()
		return
	if status == MultiplayerPeer.CONNECTION_CONNECTING:
		if not sub_ok and Time.get_ticks_msec() - start_ms > 6000:
			_next("timeout")
			return
		if sub_ok and not server and Time.get_ticks_msec() - sub_ms > 5500:
			_next("noroom")
			return
	var now := Time.get_ticks_msec()
	var dt := clampf((now - last_ms) / 1000.0, 0.0, 0.5) if last_ms > 0 else 0.0
	last_ms = now
	keep_t += dt
	if mqtt_up and keep_t > 30.0:
		keep_t = 0.001
		ws.put_packet(PackedByteArray([0xC0, 0]))
	if not sub_ok:
		return
	if not server and status == MultiplayerPeer.CONNECTION_CONNECTING:
		hello_t += dt
		if hello_t > 1.0:
			hello_t = 0.0
			_send(1, Kind.HELLO, PackedByteArray([VERSION]))
		return
	ping_t += dt
	if ping_t >= PING_EVERY:
		ping_t = 0.0
		if server:
			if not peers.is_empty():
				_send("all", Kind.PING)
		else:
			_send(1, Kind.PING)
	for id in peers.keys():
		peers[id] += dt
		if peers[id] > TIMEOUT:
			if server:
				peers.erase(id)
				peer_disconnected.emit(id)
			else:
				_lost_server()

func _put_packet_script(buf: PackedByteArray) -> Error:
	if status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if server:
		if target == 0:
			_send("all", Kind.DATA, buf)
		elif target < 0:
			_send("all", Kind.DATA, buf, -target)
		else:
			_send(target, Kind.DATA, buf)
	else:
		_send(1, Kind.DATA, buf)
	return OK

func _get_available_packet_count() -> int:
	return inbox.size()

func _get_packet_script() -> PackedByteArray:
	cur = inbox.pop_front()
	return cur[3]

func _get_packet_peer() -> int:
	return cur[0] if cur.size() > 0 else 0

func _get_packet_channel() -> int:
	return cur[1] if cur.size() > 0 else 0

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return cur[2] if cur.size() > 0 else MultiplayerPeer.TRANSFER_MODE_RELIABLE

func _get_max_packet_size() -> int:
	return 1 << 16

func _set_target_peer(p: int) -> void:
	target = p

func _get_unique_id() -> int:
	return my_id

func _is_server() -> bool:
	return server

func _is_server_relay_supported() -> bool:
	return true

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return status

func _set_transfer_mode(m: MultiplayerPeer.TransferMode) -> void:
	mode = m

func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return mode

func _set_transfer_channel(c: int) -> void:
	channel = c

func _get_transfer_channel() -> int:
	return channel

func _set_refuse_new_connections(on: bool) -> void:
	refusing = on

func _is_refusing_new_connections() -> bool:
	return refusing

func _disconnect_peer(id: int, _force: bool) -> void:
	if peers.has(id):
		peers.erase(id)
		peer_disconnected.emit(id)

func _close() -> void:
	if mqtt_up and status == MultiplayerPeer.CONNECTION_CONNECTED:
		_send("all" if server else 1, Kind.BYE)
		ws.put_packet(PackedByteArray([0xE0, 0]))   # DISCONNECT
	ws.close()
	mqtt_up = false
	peers.clear()
	status = MultiplayerPeer.CONNECTION_DISCONNECTED
