class_name WorldGen
extends Node3D
## Builds the whole course procedurally from a seed: spline track, terrain,
## road with kerbs, wooden picket fences, lakes (with open edges along big
## lakes), trees and distant scenery. Also answers "how high is the ground
## here?" and "how far from the road centre am I?" for the physics.

const HALF := 5.5        # half road width (asphalt + kerb)
const KERB := 0.7
const WALL_IN := 6.75    # edge of grass verge
const FENCE := 7.1       # fence line
const WALL_OUT := 7.5
const BLEND := 7.0
const WATER := 1.5
const KLIM := 6.25       # kart centre can't go further from the road centre than this where there's a fence
const SPACING := 0.5
const BK := 8.0

var N := 0
var P := PackedVector2Array()      # track centre (x, z)
var TH := PackedFloat32Array()     # road height
var T := PackedVector2Array()      # unit tangent
var open_side := PackedByteArray() # N*2: 1 = no fence on that side (beside a big lake)
var box_spots: Array[Vector3] = []
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var gn := 0
var hgrid := PackedFloat32Array()
var buckets := {}
var rng := RandomNumberGenerator.new()
var theme: Dictionary = Tracks.THEMES[0]
var seed_v := 0
var ext_x := 84.0        # terrain half-size (x)
var ext_z := 84.0        # terrain half-size (z)
var grid := 1.5
var gnx := 0
var map_half := 60.0     # half-size of the track bounds (minimap)
var rock_h := 14.0
var snow_h := 19.0
# hand-traced layouts
var lay: Dictionary = {}
var lay_c := Vector2.ZERO
var lay_s := 1.0
var forest := PackedVector2Array()
var lake_c := Vector2.ZERO
var lake_r := Vector2.ONE
const FCELL := 6.0
var fnx := 0
var fnz := 0
var f_road := PackedFloat32Array()
var f_dist := PackedFloat32Array()
var f_out := PackedFloat32Array()

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

# ------------------------------------------------------------------ materials
static func toon(col: Color, flat := false, outline := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("flat_shading", flat)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("width", outline)
		m.next_pass = o
	return m

# ------------------------------------------------------------------ build
func _c(key: String) -> Color:
	return Tracks.col(theme, key)

func _setup_noise(th: Dictionary) -> void:
	theme = th
	seed_v = int(th.seed)
	rng.seed = seed_v
	noise.seed = seed_v
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.014
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	detail.seed = seed_v + 7
	detail.frequency = 0.09
	lay = th.get("layout", {})

func _px(v: Vector2) -> Vector2:
	return (v - lay_c) * lay_s

func build(th: Dictionary) -> void:
	_setup_noise(th)
	_gen_track()
	if not lay.is_empty():
		_build_field()
	_gen_open_sides()
	_build_terrain()
	_build_road()
	_build_fences()
	_build_water()
	_build_trees()
	_build_scenery()
	for f: float in [0.16, 0.4, 0.62, 0.84]:
		var k := int(f * N)
		var nrm := Vector2(-T[k].y, T[k].x)
		for off: float in [-3.4, -1.1, 1.1, 3.4]:
			var q := P[k] + nrm * off
			box_spots.append(Vector3(q.x, TH[k], q.y))

func base_h(x: float, z: float) -> float:
	if not lay.is_empty():
		return _lay_h(x, z)
	var v := noise.get_noise_2d(x, z) * 0.5 + 0.5
	return (v - float(theme.h_off)) * float(theme.h_scale)

static func _cr(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _smooth(arr: PackedFloat32Array, w: int, passes: int) -> PackedFloat32Array:
	for _p in passes:
		var o := PackedFloat32Array()
		o.resize(N)
		for k in N:
			var s := 0.0
			for q in range(-w, w + 1):
				s += arr[(k + q + N) % N]
			o[k] = s / float(2 * w + 1)
		arr = o
	return arr

func _gen_track() -> void:
	if not lay.is_empty():
		_gen_track_layout()
		return
	var cps: Array[Vector2] = []
	for i in 12:
		var a := float(i) / 12.0 * TAU
		var r: float = theme.radius[0] + rng.randf() * theme.radius[1]
		cps.append(Vector2(cos(a), sin(a)) * r)
	var dense: Array[Vector2] = []
	for i in 12:
		var p0 := cps[(i + 11) % 12]
		var p1 := cps[i]
		var p2 := cps[(i + 1) % 12]
		var p3 := cps[(i + 2) % 12]
		for s in 80:
			var t := s / 80.0
			dense.append(Vector2(_cr(p0.x, p1.x, p2.x, p3.x, t), _cr(p0.y, p1.y, p2.y, p3.y, t)))
	var cum := PackedFloat32Array([0.0])
	for i in range(1, dense.size() + 1):
		cum.append(cum[i - 1] + dense[i - 1].distance_to(dense[i % dense.size()]))
	var total := cum[cum.size() - 1]
	N = int(total / SPACING)
	P.resize(N); T.resize(N); TH.resize(N)
	var j := 0
	for k in N:
		var tg := k * total / N
		while cum[j + 1] < tg:
			j += 1
		var t := (tg - cum[j]) / maxf(0.0001, cum[j + 1] - cum[j])
		P[k] = dense[j].lerp(dense[(j + 1) % dense.size()], t)
	for k in N:
		T[k] = (P[(k + 1) % N] - P[(k - 1 + N) % N]).normalized()
	var th := PackedFloat32Array()
	th.resize(N)
	for k in N:
		th[k] = base_h(P[k].x, P[k].y)
	th = _smooth(th, 22, 5)
	for k in N:
		th[k] = maxf(th[k] * 0.85, WATER + 1.0)
	th = _smooth(th, 10, 3)
	for k in N:
		TH[k] = maxf(th[k], WATER + 0.9)
	_finish_track()

func _finish_track() -> void:
	var mx := 0.0
	for k in N:
		mx = maxf(mx, maxf(absf(P[k].x), absf(P[k].y)))
	map_half = mx + 8.0
	# spatial buckets for nearest-sample queries
	for k in N:
		var key := Vector2i(floori(P[k].x / BK), floori(P[k].y / BK))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		buckets[key].append(k)

## Track from a hand-traced plan (image pixels) and a height profile along the lap.
func _gen_track_layout() -> void:
	var raw: Array = lay.points
	lay_s = float(lay.scale)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for v: Vector2 in raw:
		lo = lo.min(v)
		hi = hi.max(v)
	lay_c = (lo + hi) * 0.5
	var cps: Array[Vector2] = []
	for v: Vector2 in raw:
		cps.append(_px(v))
	var n := cps.size()
	var dense: Array[Vector2] = []
	for i in n:
		var p0 := cps[(i + n - 1) % n]
		var p1 := cps[i]
		var p2 := cps[(i + 1) % n]
		var p3 := cps[(i + 2) % n]
		for st in 60:
			var t := st / 60.0
			dense.append(Vector2(_cr(p0.x, p1.x, p2.x, p3.x, t), _cr(p0.y, p1.y, p2.y, p3.y, t)))
	var cum := PackedFloat32Array([0.0])
	for i in range(1, dense.size() + 1):
		cum.append(cum[i - 1] + dense[i - 1].distance_to(dense[i % dense.size()]))
	var total := cum[cum.size() - 1]
	N = int(total / SPACING)
	P.resize(N); T.resize(N); TH.resize(N)
	var j := 0
	for k in N:
		var tg := k * total / N
		while cum[j + 1] < tg:
			j += 1
		var t := (tg - cum[j]) / maxf(0.0001, cum[j + 1] - cum[j])
		P[k] = dense[j].lerp(dense[(j + 1) % dense.size()], t)
	# light smoothing rounds off kinks between hand-placed points
	for _p in 3:
		var o := PackedVector2Array()
		o.resize(N)
		for k in N:
			var acc := Vector2.ZERO
			for q in range(-8, 9):
				acc += P[(k + q + N) % N]
			o[k] = acc / 17.0
		P = o
	for k in N:
		T[k] = (P[(k + 1) % N] - P[(k - 1 + N) % N]).normalized()
	# heights from the elevation profile (fraction of lap -> metres)
	var prof: Array = lay.profile
	var th := PackedFloat32Array()
	th.resize(N)
	var pi := 0
	for k in N:
		var f := float(k) / N
		while pi < prof.size() - 2 and prof[pi + 1].x < f:
			pi += 1
		var a: Vector2 = prof[pi]
		var b: Vector2 = prof[pi + 1]
		th[k] = lerpf(a.y, b.y, clampf((f - a.x) / maxf(0.0001, b.x - a.x), 0.0, 1.0))
	th = _smooth(th, 16, 4)
	var top := 0.0
	for k in N:
		TH[k] = maxf(th[k], WATER + 1.0)
		top = maxf(top, TH[k])
	rock_h = top + 9.0
	snow_h = top + 22.0
	forest = PackedVector2Array()
	for v: Vector2 in lay.forest:
		forest.append(_px(v))
	lake_c = _px(lay.lake[0])
	lake_r = lay.lake[1] * lay_s
	_finish_track()
	var bx := 0.0
	var bz := 0.0
	for k in N:
		bx = maxf(bx, absf(P[k].x))
		bz = maxf(bz, absf(P[k].y))
	ext_x = ceilf(bx + 80.0)
	ext_z = ceilf(bz + 80.0)
	grid = 2.5

## Coarse height field: road height spread smoothly across the land (inverse
## distance weighting), distance to the road, and distance outside the forest.
func _build_field() -> void:
	fnx = int(2.0 * ext_x / FCELL) + 2
	fnz = int(2.0 * ext_z / FCELL) + 2
	f_road.resize(fnx * fnz)
	f_dist.resize(fnx * fnz)
	f_out.resize(fnx * fnz)
	var sp := PackedVector2Array()
	var sh := PackedFloat32Array()
	for k in range(0, N, 6):
		sp.append(P[k])
		sh.append(TH[k])
	var m := sp.size()
	var fc := forest.size()
	for iz in fnz:
		for ix in fnx:
			var q := Vector2(-ext_x + ix * FCELL, -ext_z + iz * FCELL)
			var ws := 0.0
			var hs := 0.0
			var dmin := INF
			for k in m:
				var d2 := q.distance_squared_to(sp[k])
				dmin = minf(dmin, d2)
				var w := 1.0 / ((d2 + 64.0) * (d2 + 64.0))
				ws += w
				hs += w * sh[k]
			var id := iz * fnx + ix
			f_road[id] = hs / ws
			f_dist[id] = sqrt(dmin)
			# distance outside the forest outline (0 inside)
			if fc > 2 and not Geometry2D.is_point_in_polygon(q, forest):
				var e := INF
				for k in fc:
					var a := forest[k]
					var b := forest[(k + 1) % fc]
					e = minf(e, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
				f_out[id] = e
			else:
				f_out[id] = 0.0

func _field(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x + ext_x) / FCELL
	var fz := (z + ext_z) / FCELL
	var ix := clampi(floori(fx), 0, fnx - 2)
	var iz := clampi(floori(fz), 0, fnz - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	return lerpf(lerpf(arr[iz * fnx + ix], arr[iz * fnx + ix + 1], tx),
		lerpf(arr[(iz + 1) * fnx + ix], arr[(iz + 1) * fnx + ix + 1], tx), tz)

func lake_e(x: float, z: float) -> float:
	return ((Vector2(x, z) - lake_c) / lake_r).length()

func _lay_h(x: float, z: float) -> float:
	if f_road.is_empty():
		return 8.0
	var road := _field(f_road, x, z)
	var d := _field(f_dist, x, z)
	var out := _field(f_out, x, z)
	var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
	var h := road - 0.3 + (n - 0.3) * 7.0 * smoothstep(9.0, 45.0, d)
	# mountains rising past the edge of the forest
	h += smoothstep(0.0, 75.0, out) * (26.0 + 26.0 * n)
	h = maxf(h, WATER + 0.9)
	var bowl := 1.0 - smoothstep(0.75, 1.7, lake_e(x, z))
	return lerpf(h, WATER - 2.6, bowl)

func _gen_open_sides() -> void:
	# Leave the fence off only along long stretches beside big lakes.
	open_side.resize(N * 2)
	var cand := PackedByteArray()
	cand.resize(N * 2)
	for k in N:
		for sd in 2:
			var sg := 1.0 if sd == 1 else -1.0
			var nrm := Vector2(-T[k].y, T[k].x) * sg
			var w := 0
			for dd: float in [WALL_OUT + 0.5, WALL_OUT + 1.5, WALL_OUT + 3.0, WALL_OUT + 5.0, WALL_OUT + 7.5]:
				var q := P[k] + nrm * dd
				if base_h(q.x, q.y) < WATER - 0.15:
					w += 1
			cand[k * 2 + sd] = 1 if w >= 4 else 0
	for k in N:
		for sd in 2:
			var c := 0
			for q in range(-6, 7):
				c += cand[((k + q + N) % N) * 2 + sd]
			open_side[k * 2 + sd] = 1 if c >= 8 else 0
	var run_len := PackedInt32Array()
	run_len.resize(N * 2)
	for sd in 2:
		for k in N:
			if open_side[k * 2 + sd] == 0 or run_len[k * 2 + sd] != 0:
				continue
			var a := k
			var b := k
			while open_side[((a - 1 + N) % N) * 2 + sd] == 1 and b - a < N:
				a -= 1
			while open_side[((b + 1) % N) * 2 + sd] == 1 and b - a < N:
				b += 1
			for q in range(a, b + 1):
				run_len[((q + N) % N) * 2 + sd] = b - a + 1
	for k in N:
		if open_side[k * 2] == 1 and open_side[k * 2 + 1] == 1:
			open_side[k * 2 + (1 if run_len[k * 2] >= run_len[k * 2 + 1] else 0)] = 0
	for k in N:
		for sd in 2:
			if open_side[k * 2 + sd] == 1 and run_len[k * 2 + sd] < 36:
				open_side[k * 2 + sd] = 0
	for k in 6:
		for sd in 2:
			open_side[k * 2 + sd] = 0
			open_side[(N - 1 - k) * 2 + sd] = 0

# ------------------------------------------------------------------ queries
## Returns Vector3(nearest index, signed lateral distance, t along segment)
func nearest_local(p: Vector2, hint: int, window := 30) -> Vector3:
	var best := hint
	var bd := INF
	for o in range(-window, window + 1):
		var i := (hint + o + N) % N
		var d := p.distance_squared_to(P[i])
		if d < bd:
			bd = d
			best = i
	return _refine(p, best)

func nearest_global(p: Vector2, radius := 16.0) -> Vector3:
	var best := -1
	var bd := radius * radius
	var cx := floori(p.x / BK)
	var cz := floori(p.y / BK)
	var rr := int(ceil(radius / BK))
	for dx in range(-rr, rr + 1):
		for dz in range(-rr, rr + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if buckets.has(key):
				for i in buckets[key]:
					var d := p.distance_squared_to(P[i])
					if d < bd:
						bd = d
						best = i
	if best < 0:
		return Vector3(-1, INF, 0)
	return _refine(p, best)

func _refine(p: Vector2, i: int) -> Vector3:
	var a := P[i]
	var b := P[(i + 1) % N]
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
	var idx := i
	if t <= 0.0:
		var c := P[(i - 1 + N) % N]
		var ca := a - c
		var t2 := clampf((p - c).dot(ca) / maxf(0.0001, ca.length_squared()), 0.0, 1.0)
		idx = (i - 1 + N) % N
		t = t2
		a = c
		ab = ca
	var foot := a + ab * t
	var tg := ab.normalized()
	var lat := tg.x * (p - foot).y - tg.y * (p - foot).x
	return Vector3(idx, lat, t)

func road_h(idx: int, t: float) -> float:
	return lerpf(TH[idx], TH[(idx + 1) % N], t)

func is_open(idx: int, lat: float) -> bool:
	return open_side[idx * 2 + (1 if lat > 0.0 else 0)] == 1

func terrain_h(x: float, z: float) -> float:
	var fx := (x + ext_x) / grid
	var fz := (z + ext_z) / grid
	var ix := clampi(floori(fx), 0, gnx - 2)
	var iz := clampi(floori(fz), 0, gn - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var a := hgrid[iz * gnx + ix]
	var b := hgrid[iz * gnx + ix + 1]
	var c := hgrid[(iz + 1) * gnx + ix]
	var d := hgrid[(iz + 1) * gnx + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

## Ground under a point given its nearest-track info: Vector2(height, surface)
## surface: 0 grass, 1 road, 2 water, 3 kerb
func ground(p: Vector2, nr: Vector3) -> Vector2:
	var idx := int(nr.x)
	var lat := absf(nr.y)
	if lat <= WALL_IN or (lat <= WALL_OUT and not is_open(idx, nr.y)):
		var h := road_h(idx, nr.z)
		if lat <= HALF - KERB:
			return Vector2(h, 1)
		if lat <= HALF:
			return Vector2(h + 0.06, 3)
		return Vector2(h, 0)
	var th := terrain_h(p.x, p.y)
	if th < WATER - 0.05:
		return Vector2(WATER, 2)
	return Vector2(th, 0)

# ------------------------------------------------------------------ terrain
func _terrain_vertex_h(x: float, z: float) -> float:
	var h := base_h(x, z)
	var nr := nearest_global(Vector2(x, z), WALL_OUT + BLEND + 1.0)
	if nr.x < 0:
		return h
	var idx := int(nr.x)
	var lat := absf(nr.y)
	var t0 := road_h(idx, nr.z) - 0.25
	if lat <= WALL_IN:
		return t0
	if is_open(idx, nr.y):
		var t := smoothstep(0.0, 2.5, lat - WALL_IN)
		return lerpf(t0, minf(h, WATER - 1.4), t)
	if lat <= WALL_OUT + 0.4:
		return t0
	return lerpf(t0, h, smoothstep(0.0, BLEND, lat - WALL_OUT - 0.4))

func _build_terrain() -> void:
	gnx = int(2.0 * ext_x / grid) + 1
	gn = int(2.0 * ext_z / grid) + 1
	hgrid.resize(gnx * gn)
	for iz in gn:
		for ix in gnx:
			hgrid[iz * gnx + ix] = _terrain_vertex_h(-ext_x + ix * grid, -ext_z + iz * grid)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_a := _c("grass_a")
	var grass_b := _c("grass_b")
	var sand := _c("sand")
	var rock := _c("rock")
	var snow := _c("snow")
	for iz in gn - 1:
		for ix in gnx - 1:
			var x0 := -ext_x + ix * grid
			var z0 := -ext_z + iz * grid
			var v00 := Vector3(x0, hgrid[iz * gnx + ix], z0)
			var v10 := Vector3(x0 + grid, hgrid[iz * gnx + ix + 1], z0)
			var v01 := Vector3(x0, hgrid[(iz + 1) * gnx + ix], z0 + grid)
			var v11 := Vector3(x0 + grid, hgrid[(iz + 1) * gnx + ix + 1], z0 + grid)
			for tri in [[v00, v10, v11], [v00, v11, v01]]:
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var c: Vector3 = tri[2]
				var avg := (a.y + b.y + c.y) / 3.0
				var nrm := (b - a).cross(c - a).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				var cx := (a.x + b.x + c.x) / 3.0
				var cz := (a.z + b.z + c.z) / 3.0
				var col: Color
				if avg < WATER + 0.5:
					col = sand
				elif avg > snow_h:
					col = snow
				elif avg > rock_h or nrm.y < 0.66:
					col = rock.lerp(snow, clampf((avg - rock_h) / 10.0, 0.0, 0.5))
				else:
					col = grass_a if detail.get_noise_2d(cx, cz) < 0.1 else grass_b
				_tri_up(st, a, b, c, col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var tm := toon(Color.WHITE, true)
	tm.set_shader_parameter("rim_ink", 0.16)
	mi.material_override = tm
	mi.name = "Terrain"
	add_child(mi)
	# far ground so there's no void past the terrain edge
	var far := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1) * maxf(900.0, maxf(ext_x, ext_z) * 4.0)
	far.mesh = pm
	far.position.y = -2.0
	far.material_override = toon(_c("far"))
	add_child(far)

## Adds a triangle whose front face points up (Godot uses clockwise front faces).
func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).y > 0.0:
		var tmp := b
		b = c
		c = tmp
	var n := (b - a).cross(c - a).normalized() * -1.0
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)

func _quad_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri_up(st, a, b, c, col)
	_tri_up(st, a, c, d, col)

# ------------------------------------------------------------------ road
func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var asphalt := _c("asphalt")
	var asphalt2 := asphalt.lightened(0.06)
	var red := Color("eb4060")
	var white := Color("faf6ff")
	var verge := _c("verge")
	var ink := Color("2a1830")
	var yellow := Color("ffd640")
	var dark := Color("2e2638")
	for i in N:
		var j := (i + 1) % N
		var na := Vector2(-T[i].y, T[i].x)
		var nb := Vector2(-T[j].y, T[j].x)
		for sd: float in [-1.0, 1.0]:
			var side := 1 if sd > 0.0 else 0
			var open := open_side[i * 2 + side] == 1
			var sections := [
				[0.0, HALF - KERB, 0.0, asphalt if (i >> 3) & 1 else asphalt2],
				[HALF - KERB - 0.05, HALF - KERB + 0.03, 0.075, ink],
				[HALF - KERB, HALF, 0.06, red if (i >> 2) & 1 else white],
				[HALF - 0.02, HALF + 0.07, 0.075, ink],
				[HALF, WALL_IN, 0.0, verge],
			]
			if open:
				sections.append([WALL_IN - 0.45, WALL_IN, 0.02, yellow if (i >> 1) & 1 else dark])
			else:
				sections.append([WALL_IN, WALL_OUT + 0.4, 0.0, verge])
			if i < 3 or i > N - 3:
				sections[0][3] = white if ((i >> 1) + int(side)) & 1 else Color("2a2234")
			for s in sections:
				var o0: float = s[0]
				var o1: float = s[1]
				var y: float = s[2]
				var c: Color = s[3]
				var a := P[i] + na * o0 * sd
				var b := P[i] + na * o1 * sd
				var cc := P[j] + nb * o1 * sd
				var d := P[j] + nb * o0 * sd
				_quad_up(st, Vector3(a.x, TH[i] + y, a.y), Vector3(b.x, TH[i] + y, b.y),
					Vector3(cc.x, TH[j] + y, cc.y), Vector3(d.x, TH[j] + y, d.y), c)
		# centre dashes
		if (i >> 3) & 1 and i > 4 and i < N - 4:
			var a2 := P[i] + na * -0.12
			var b2 := P[i] + na * 0.12
			var c2 := P[j] + nb * 0.12
			var d2 := P[j] + nb * -0.12
			_quad_up(st, Vector3(a2.x, TH[i] + 0.02, a2.y), Vector3(b2.x, TH[i] + 0.02, b2.y),
				Vector3(c2.x, TH[j] + 0.02, c2.y), Vector3(d2.x, TH[j] + 0.02, d2.y), yellow)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = toon(Color.WHITE)
	mi.name = "Road"
	add_child(mi)

# ------------------------------------------------------------------ fences
func _multimesh(mesh: Mesh, xforms: Array[Transform3D], mat: Material, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.name = nm
	add_child(mmi)
	return mmi

func _basis_along(t: Vector2) -> Basis:
	var x := Vector3(t.x, 0, t.y)
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))

func _build_fences() -> void:
	var pickets: Array[Transform3D] = []
	var tips: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for i in N:
		var j := (i + 1) % N
		for sd: float in [-1.0, 1.0]:
			var side := 1 if sd > 0.0 else 0
			if open_side[i * 2 + side] == 1:
				continue
			var nrm := Vector2(-T[i].y, T[i].x) * sd
			var q := P[i] + nrm * FENCE
			if _in_other_road(q, i):
				continue
			var bas := _basis_along(T[i])
			var hh := 0.95 + rng.randf() * 0.08
			pickets.append(Transform3D(Basis(bas.x, bas.y * hh, bas.z), Vector3(q.x, TH[i] + hh * 0.5, q.y)))
			tips.append(Transform3D(bas, Vector3(q.x, TH[i] + hh + 0.09, q.y)))
			if i % 12 == 0:
				posts.append(Transform3D(bas, Vector3(q.x, TH[i] + 0.68, q.y)))
			if open_side[j * 2 + side] == 0 and not _in_other_road(P[j] + Vector2(-T[j].y, T[j].x) * sd * FENCE, j):
				var q2 := P[j] + Vector2(-T[j].y, T[j].x) * sd * FENCE
				var mid := (q + q2) * 0.5 + nrm * 0.07
				var seg := q2 - q
				var sb := _basis_along(seg.normalized())
				var rb := Basis(sb.x * (seg.length() + 0.02), sb.y, sb.z)
				for ry: float in [0.28, 0.72]:
					rails.append(Transform3D(rb, Vector3(mid.x, lerpf(TH[i], TH[j], 0.5) + ry, mid.y)))
	var pm := BoxMesh.new()
	pm.size = Vector3(0.24, 1.0, 0.07)
	var tm := PrismMesh.new()
	tm.size = Vector3(0.24, 0.18, 0.07)
	var postm := BoxMesh.new()
	postm.size = Vector3(0.24, 1.36, 0.24)
	var railm := BoxMesh.new()
	railm.size = Vector3(1.0, 0.1, 0.05)
	_multimesh(pm, pickets, toon(_c("fence"), false, 0.02), "FencePickets")
	_multimesh(tm, tips, toon(_c("fence").lightened(0.12), false, 0.02), "FenceTips")
	_multimesh(postm, posts, toon(_c("post"), false, 0.025), "FencePosts")
	_multimesh(railm, rails, toon(_c("fence").lerp(_c("post"), 0.45)), "FenceRails")

## True if a point sits on the verge of a different stretch of track (tight
## hairpins and close parallel sections), so no fence should go there.
func _in_other_road(q: Vector2, i: int) -> bool:
	var ng := nearest_global(q, WALL_IN + 0.3)
	if ng.x < 0:
		return false
	var gap := absi(int(ng.x) - i)
	gap = mini(gap, N - gap)
	return gap > 30 and absf(ng.y) < WALL_IN + 0.2

# ------------------------------------------------------------------ water
func _build_water() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ext_x * 2.0 + 40.0, ext_z * 2.0 + 40.0)
	pm.subdivide_width = 0
	w.mesh = pm
	w.position.y = WATER
	var m := toon(_c("water"))
	m.set_shader_parameter("shadow_band", 0.9)
	w.material_override = m
	w.name = "Water"
	add_child(w)

# ------------------------------------------------------------------ trees
func _build_trees() -> void:
	var trunks: Array[Transform3D] = []
	var pines: Array[Transform3D] = []
	var rounds: Array[Transform3D] = []
	var candy: Array[Transform3D] = []
	var sticks: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var placed := 0
	var tries := 0
	var want := 520
	var lo := Vector2(-ext_x + 3.0, -ext_z + 3.0)
	var hi := -lo
	if not lay.is_empty():
		want = int(lay.get("trees", 1500))
		lo = Vector2(INF, INF)
		hi = -lo
		for v in forest:
			lo = lo.min(v)
			hi = hi.max(v)
	while placed < want and tries < want * 14:
		tries += 1
		var x := rng.randf_range(lo.x, hi.x)
		var z := rng.randf_range(lo.y, hi.y)
		if not lay.is_empty():
			if not Geometry2D.is_point_in_polygon(Vector2(x, z), forest) or lake_e(x, z) < 1.35:
				continue
		var nr := nearest_global(Vector2(x, z), WALL_OUT + (1.6 if not lay.is_empty() else 3.0))
		if nr.x >= 0:
			continue
		var h := terrain_h(x, z)
		if h < WATER + 0.6 or h > rock_h + 4.0:
			continue
		placed += 1
		var s := rng.randf_range(0.8, 1.35)
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		var kind := rng.randf()
		var tw: Dictionary = theme.trees
		var c1: float = tw.pine
		var c2: float = c1 + float(tw.round)
		var c3: float = c2 + float(tw.candy)
		if kind < c1:
			trunks.append(Transform3D(yaw.scaled(Vector3(s, s, s)), Vector3(x, h + 0.6 * s, z)))
			pines.append(Transform3D(yaw.scaled(Vector3(s, s, s)), Vector3(x, h + 2.2 * s, z)))
		elif kind < c2:
			trunks.append(Transform3D(yaw.scaled(Vector3(s, s, s)), Vector3(x, h + 0.6 * s, z)))
			rounds.append(Transform3D(yaw.scaled(Vector3(s, s * 0.9, s)), Vector3(x, h + 2.0 * s, z)))
		elif kind < c3:
			sticks.append(Transform3D(yaw.scaled(Vector3(s, s, s)), Vector3(x, h + 0.9 * s, z)))
			candy.append(Transform3D(yaw.scaled(Vector3(s, s, s)), Vector3(x, h + 2.1 * s, z)))
		else:
			bushes.append(Transform3D(yaw.scaled(Vector3(s * 1.3, s * 0.8, s * 1.3)), Vector3(x, h + 0.35 * s, z)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16; trunk.bottom_radius = 0.22; trunk.height = 1.2; trunk.radial_segments = 6
	var pine := CylinderMesh.new()
	pine.top_radius = 0.0; pine.bottom_radius = 1.25; pine.height = 3.0; pine.radial_segments = 7; pine.rings = 1
	var ball := SphereMesh.new()
	ball.radius = 1.2; ball.height = 2.3; ball.radial_segments = 8; ball.rings = 5
	var cball := SphereMesh.new()
	cball.radius = 1.0; cball.height = 1.9; cball.radial_segments = 8; cball.rings = 5
	var stick := CylinderMesh.new()
	stick.top_radius = 0.1; stick.bottom_radius = 0.12; stick.height = 1.8; stick.radial_segments = 6
	var bush := SphereMesh.new()
	bush.radius = 0.8; bush.height = 1.4; bush.radial_segments = 7; bush.rings = 4
	_multimesh(trunk, trunks, toon(_c("trunk"), true, 0.03), "Trunks")
	_multimesh(pine, pines, toon(_c("pine_col"), true, 0.05), "Pines")
	_multimesh(ball, rounds, toon(_c("round_col"), true, 0.05), "RoundTrees")
	_multimesh(stick, sticks, toon(Color("fff4fa"), true, 0.03), "CandySticks")
	_multimesh(cball, candy, toon(_c("candy_col"), true, 0.05), "CandyTrees")
	_multimesh(bush, bushes, toon(_c("bush_col"), true, 0.04), "Bushes")

# ------------------------------------------------------------------ distant scenery
func _build_scenery() -> void:
	var hills: Array[Transform3D] = []
	var hills2: Array[Transform3D] = []
	var clouds: Array[Transform3D] = []
	for i in 46:
		var a := float(i) / 46.0 * TAU + rng.randf() * 0.1
		var r0 := maxf(118.0, maxf(ext_x, ext_z) + 25.0)
		var r := rng.randf_range(r0, r0 + 57.0)
		var s := rng.randf_range(16.0, 34.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.3), s)), Vector3(cos(a) * r, -4.0, sin(a) * r))
		if i % 3 == 0:
			hills2.append(xf)
		else:
			hills.append(xf)
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(90.0, maxf(170.0, maxf(ext_x, ext_z) + 40.0))
		var y := rng.randf_range(32.0, 52.0)
		for b in 4:
			var s := rng.randf_range(4.0, 8.0)
			clouds.append(Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), Vector3(cos(a) * r + (b - 1.5) * 6.0, y + sin(b * 1.7) * 1.5, sin(a) * r + rng.randf_range(-3, 3))))
	var hm := SphereMesh.new()
	hm.radius = 1.0; hm.height = 2.0; hm.radial_segments = 9; hm.rings = 5
	var fh := toon(Color(String(theme.hills[0])), true)
	fh.set_shader_parameter("rim_ink", 0.2)
	_multimesh(hm, hills, fh, "FarHills")
	_multimesh(hm, hills2, toon(Color(String(theme.hills[1])), true), "FarHills2")
	var cm := SphereMesh.new()
	cm.radius = 1.0; cm.height = 2.0; cm.radial_segments = 8; cm.rings = 5
	var cmat := toon(Color("ffffff"), true)
	cmat.set_shader_parameter("shadow_band", 0.92)
	cmat.set_shader_parameter("shadow_tint", Color("e8dcff"))
	_multimesh(cm, clouds, cmat, "Clouds")

## Track shape only (no meshes), for menu previews.
static func preview(th: Dictionary) -> PackedVector2Array:
	var w := WorldGen.new()
	w._setup_noise(th)
	w._gen_track()
	var pts := w.P.duplicate()
	w.free()
	return pts
