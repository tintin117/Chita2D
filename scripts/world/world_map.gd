@tool  # ponytail: only so the in-editor test runner can instantiate it; it does nothing in the editor
class_name WorldMap extends Node2D
## Procedural level for the open-map run: a 4x3 grid of round-ish chambers joined by corridors, plus small
## dead-end alcoves. Everything is water outside the chambers; the ring of land right at the shore is a solid
## tree line, so trees are the border and the inside is open ground. Origin = top-left of the map.
## Add players/enemies as children of this node so they y-sort with the trees.

const TILE := 64
const GRID := Vector2i(4, 3)            ## chamber zones
const ZONE := Vector2i(32, 26)          ## cells per zone
const SIZE := Vector2i(128, 78)         ## cells = GRID * ZONE (8192 x 4992 px)
const INSET := 64.0                     ## shore collider reaches this far onto the land: the tree-line cell is solid
const TILESET := "res://assets/tiny_swords/terrain/Tilemap_color1.png"
const WATER := "res://assets/tiny_swords/terrain/Water Background color.png"
const TERRAIN := "res://assets/tiny_swords/terrain/"

const CHAMBER_R := Vector2(7.0, 9.5)    ## chamber radius range (cells)
const SPAWN_R := 8.5
const GATE_R := 10.0
const ALCOVE_R := Vector2(4.0, 5.0)
const CORRIDOR_R := 3.0                 ## half width (cells): 7 wide, 5 walkable between the tree lines
const EXTRA_LOOPS := 3                  ## corridors beyond the spanning tree
const DECOR_BUSH := 0.03                ## per open cell
const DECOR_ROCK := 0.012

var seed_value := 0
var bounds := Rect2(Vector2.ZERO, Vector2(SIZE * TILE))
var spawn_point := Vector2.ZERO
var gate_pos := Vector2.ZERO            ## centre of the far-east gate chamber (boss gate site)
var boss_arena := Rect2()               ## open ground around the gate
var camps: Array[Dictionary] = []       ## {pos: Vector2, tier: int 1..3, radius: float}, one per camp chamber
var objective_sites: Array[Vector2] = [] ## one per alcove
var chambers: Array[Dictionary] = []    ## {c: Vector2 (cells), r: float, kind: spawn|gate|camp|alcove}

var _land := PackedByteArray()
var _core := PackedByteArray()          ## land with land on all 8 sides: the walkable inside, the rest is the tree line
var _dist := PackedInt32Array()         ## walking distance (cells) from spawn over _core, -1 = unreachable
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _edges: Array[Vector2i] = []        ## chamber index pairs joined by a corridor
var _decor: Array[Dictionary] = []      ## {kind: tree|rock|bush, variant: int, pos: Vector2}
var _free: Array[Vector2i] = []         ## reachable cells with room around them
var _owned: Array[Node] = []

func _ready() -> void:
	y_sort_enabled = true

func generate(new_seed: int, build_visuals := true) -> void:
	seed_value = new_seed
	_rng.seed = new_seed
	_noise.seed = new_seed
	_noise.frequency = 0.35
	for n in _owned:
		n.queue_free()
	_owned.clear()
	_layout()
	_carve()
	_pick_points()
	_scatter_decor()
	if build_visuals:
		_build()

func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / TILE).floor())

func center_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE

func is_land(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < SIZE.x and c.y < SIZE.y and _land[c.y * SIZE.x + c.x] == 1

## True if pos is walkable ground connected to the spawn.
func is_reachable(pos: Vector2) -> bool:
	var c := cell_of(pos)
	return _is_core(c) and _dist[c.y * SIZE.x + c.x] >= 0

## A free spot on reachable open ground, at least min_dist px from `from`.
func random_open_point(from := Vector2.ZERO, min_dist := 0.0) -> Vector2:
	var p := spawn_point
	for i in 40:
		p = center_of(_free[_rng.randi() % _free.size()]) + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
		if p.distance_to(from) >= min_dist:
			break
	return p

# --- layout: chambers + corridors ---------------------------------------------

func _layout() -> void:
	chambers.clear()
	_edges.clear()
	var spawn_row := _rng.randi_range(0, GRID.y - 1)
	var gate_row := _rng.randi_range(0, GRID.y - 1)
	for gy in GRID.y:
		for gx in GRID.x:
			var kind := "camp"
			var r := _rng.randf_range(CHAMBER_R.x, CHAMBER_R.y)
			if gx == 0 and gy == spawn_row:
				kind = "spawn"
				r = SPAWN_R
			elif gx == GRID.x - 1 and gy == gate_row:
				kind = "gate"
				r = GATE_R
			var c := (Vector2(gx, gy) + Vector2(0.5, 0.5)) * Vector2(ZONE) + Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
			chambers.append({"c": c, "r": r, "kind": kind})

	# Spanning tree over the grid (random Kruskal) so every chamber is reachable, plus a few loops.
	var all: Array[Vector2i] = []
	for gy in GRID.y:
		for gx in GRID.x:
			if gx + 1 < GRID.x:
				all.append(Vector2i(gy * GRID.x + gx, gy * GRID.x + gx + 1))
			if gy + 1 < GRID.y:
				all.append(Vector2i(gy * GRID.x + gx, (gy + 1) * GRID.x + gx))
	var order := _shuffled_pairs(all)
	var parent: Array[int] = []
	for i in chambers.size():
		parent.append(i)
	var left: Array[Vector2i] = []
	for e in order:
		var a := _find(parent, e.x)
		var b := _find(parent, e.y)
		if a != b:
			parent[a] = b
			_edges.append(e)
		else:
			left.append(e)
	for i in mini(EXTRA_LOOPS, left.size()):
		_edges.append(left[i])

	# Alcoves: small dead ends in the empty middle of each four-chamber crossing, reached from the nearest chamber.
	for gy in range(1, GRID.y):
		for gx in range(1, GRID.x):
			var c := Vector2(gx, gy) * Vector2(ZONE) + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
			var parent_i := 0
			for i in GRID.x * GRID.y:
				if c.distance_to(chambers[i].c) < c.distance_to(chambers[parent_i].c):
					parent_i = i
			chambers.append({"c": c, "r": _rng.randf_range(ALCOVE_R.x, ALCOVE_R.y), "kind": "alcove"})
			_edges.append(Vector2i(parent_i, chambers.size() - 1))

## Seeded Fisher-Yates (Array.shuffle would use the global RNG and break per-seed determinism).
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t

func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i

func _shuffled_pairs(a: Array[Vector2i]) -> Array[Vector2i]:
	var out := a.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Vector2i = out[i]
		out[i] = out[j]
		out[j] = t
	return out

func _carve() -> void:
	_land.resize(SIZE.x * SIZE.y)
	_land.fill(0)
	for i in chambers.size():
		var ch: Dictionary = chambers[i]
		var cc: Vector2 = ch.c
		var rr: float = ch.r
		var reach := rr * 1.35
		for y in range(maxi(int(cc.y - reach), 0), mini(int(cc.y + reach) + 1, SIZE.y)):
			for x in range(maxi(int(cc.x - reach), 0), mini(int(cc.x + reach) + 1, SIZE.x)):
				var v := Vector2(x + 0.5, y + 0.5) - cc
				var d := v.length()
				if d > reach:
					continue
				# wobbly outline: radius modulated by noise sampled around the circle
				var n := _noise.get_noise_2d(i * 17.0 + v.x / maxf(d, 0.01) * 2.5, v.y / maxf(d, 0.01) * 2.5)
				if d <= rr * (1.0 + 0.25 * n):
					_land[y * SIZE.x + x] = 1
	for ei in _edges.size():
		var a: Vector2 = chambers[_edges[ei].x].c
		var b: Vector2 = chambers[_edges[ei].y].c
		var rc := CORRIDOR_R if chambers[_edges[ei].y].kind != "alcove" else CORRIDOR_R - 0.5
		var side := (b - a).orthogonal().normalized()
		var steps := ceili(a.distance_to(b))
		for s in steps + 1:
			var t := float(s) / steps
			var p := a.lerp(b, t) + side * _noise.get_noise_2d(ei * 31.0, t * steps * 0.15) * 2.5 * sin(PI * t)
			for y in range(maxi(int(p.y - rc) - 1, 0), mini(int(p.y + rc) + 2, SIZE.y)):
				for x in range(maxi(int(p.x - rc) - 1, 0), mini(int(p.x + rc) + 2, SIZE.x)):
					if Vector2(x + 0.5, y + 0.5).distance_to(p) <= rc:
						_land[y * SIZE.x + x] = 1
	_keep_largest()
	_core.resize(SIZE.x * SIZE.y)
	_core.fill(0)
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			var all_land := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					all_land = all_land and is_land(c + Vector2i(dx, dy))
			if all_land:
				_core[y * SIZE.x + x] = 1

func _keep_largest() -> void:
	var label := PackedInt32Array()
	label.resize(SIZE.x * SIZE.y)
	var best := 0
	var best_size := 0
	var next := 0
	for start in SIZE.x * SIZE.y:
		if _land[start] == 0 or label[start] != 0:
			continue
		next += 1
		var stack: Array[int] = [start]
		label[start] = next
		var count := 0
		while not stack.is_empty():
			var i: int = stack.pop_back()
			count += 1
			var c := Vector2i(i % SIZE.x, floori(float(i) / SIZE.x))
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var nc: Vector2i = c + dir
				if is_land(nc) and label[nc.y * SIZE.x + nc.x] == 0:
					label[nc.y * SIZE.x + nc.x] = next
					stack.append(nc.y * SIZE.x + nc.x)
		if count > best_size:
			best = next
			best_size = count
	for i in label.size():
		_land[i] = 1 if label[i] == best else 0

# --- spawn, gate, camps, sites ----------------------------------------------

func _is_core(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < SIZE.x and c.y < SIZE.y and _core[c.y * SIZE.x + c.x] == 1

## Land in the whole 5x5 around c.
func _open2(c: Vector2i) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if not is_land(c + Vector2i(dx, dy)):
				return false
	return true

func _pick_points() -> void:
	camps.clear()
	objective_sites.clear()
	var camp_chambers: Array[Dictionary] = []
	for ch in chambers:
		var at := center_of(cell_of(ch.c * TILE))
		match ch.kind:
			"spawn":
				spawn_point = at
			"gate":
				gate_pos = at
				boss_arena = Rect2(at - Vector2.ONE * ch.r * TILE * 0.7, Vector2.ONE * ch.r * TILE * 1.4)
			"camp":
				camp_chambers.append({"pos": at, "r": ch.r * TILE * 0.5})
			"alcove":
				objective_sites.append(at)
	_bfs(cell_of(spawn_point))
	# tier by how far you have to walk: nearest third = 1, middle = 2, farthest = 3
	camp_chambers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _walk(a.pos) < _walk(b.pos))
	for i in camp_chambers.size():
		camps.append({"pos": camp_chambers[i].pos, "tier": 1 + floori(i * 3.0 / camp_chambers.size()), "radius": camp_chambers[i].r})

func _walk(pos: Vector2) -> int:
	var c := cell_of(pos)
	return _dist[c.y * SIZE.x + c.x]

func _bfs(start: Vector2i) -> void:
	_dist.resize(SIZE.x * SIZE.y)
	_dist.fill(-1)
	var queue: Array[Vector2i] = [start]
	_dist[start.y * SIZE.x + start.x] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nc: Vector2i = c + dir
			if _is_core(nc) and _dist[nc.y * SIZE.x + nc.x] < 0:
				_dist[nc.y * SIZE.x + nc.x] = _dist[c.y * SIZE.x + c.x] + 1
				queue.append(nc)

# --- decor --------------------------------------------------------------------

## Trees fill the shore ring completely (that is the border); the inside only gets a few non-solid bushes and rocks.
func _scatter_decor() -> void:
	_decor.clear()
	_free.clear()
	var keep_clear: Array[Vector2] = [spawn_point, gate_pos]
	keep_clear.append_array(objective_sites)
	for k in camps:
		keep_clear.append(k.pos)
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			if not is_land(c):
				continue
			var pos := center_of(c)
			if not _is_core(c):
				for i in 2:   # two trees per ring cell, jittered, so the line reads as dense forest
					_decor.append({"kind": "tree", "variant": _rng.randi_range(1, 4), "pos": pos + Vector2(_rng.randf_range(-22, 22), _rng.randf_range(-22, 22))})
				continue
			if _dist[y * SIZE.x + x] < 0:
				continue
			if _open2(c):
				_free.append(c)
			var roll := _rng.randf()
			if (roll < DECOR_BUSH + DECOR_ROCK) and keep_clear.all(func(k: Vector2) -> bool: return pos.distance_to(k) > 200.0):
				_decor.append({"kind": "bush" if roll < DECOR_BUSH else "rock", "variant": _rng.randi_range(1, 4), "pos": pos + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))})

# --- visuals & collision ------------------------------------------------------

func _build() -> void:
	var ground := Node2D.new()
	ground.z_index = -10
	add_child(ground)
	_owned.append(ground)

	var water := Sprite2D.new()
	water.texture = load(WATER)
	water.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	water.centered = false
	water.region_enabled = true
	water.region_rect = Rect2(0, 0, bounds.size.x + 2400, bounds.size.y + 1600)
	water.position = Vector2(-1200, -800)
	ground.add_child(water)

	var src := TileSetAtlasSource.new()
	src.texture = load(TILESET)
	src.texture_region_size = Vector2i(TILE, TILE)
	for x in 3:
		for y in 3:
			src.create_tile(Vector2i(x, y))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			if not is_land(c):
				continue
			# nine-patch: edge tile on the sides that face water; concave corners just use the fill tile
			var cx := 0 if not is_land(c + Vector2i.LEFT) else (2 if not is_land(c + Vector2i.RIGHT) else 1)
			var cy := 0 if not is_land(c + Vector2i.UP) else (2 if not is_land(c + Vector2i.DOWN) else 1)
			layer.set_cell(c, 0, Vector2i(cx, cy))
	ground.add_child(layer)

	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	ground.add_child(walls)
	for y in SIZE.y:   # water touching land, merged into horizontal runs; INSET makes the tree-line cell solid
		var x := 0
		while x < SIZE.x:
			if not _shore_water(Vector2i(x, y)):
				x += 1
				continue
			var x0 := x
			while x < SIZE.x and _shore_water(Vector2i(x, y)):
				x += 1
			_add_rect(walls, Rect2(x0 * TILE - INSET, y * TILE - INSET, (x - x0) * TILE + 2 * INSET, TILE + 2 * INSET))

	for d in _decor:
		var s := Sprite2D.new()
		match d.kind:
			"tree":
				s.texture = load(TERRAIN + "Tree%d.png" % d.variant)
				s.hframes = 8
			"bush":
				s.texture = load(TERRAIN + "Bushes/Bushe%d.png" % d.variant)
				s.hframes = 8
			_:
				s.texture = load(TERRAIN + "Rocks/Rock%d.png" % d.variant)
		s.offset.y = -0.36 * s.texture.get_height() if d.kind != "bush" else -0.3 * s.texture.get_height()
		s.position = d.pos
		add_child(s)
		_owned.append(s)

func _shore_water(c: Vector2i) -> bool:
	if is_land(c):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if is_land(c + Vector2i(dx, dy)):
				return true
	return false

func _add_rect(body: StaticBody2D, r: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = r.size
	cs.shape = rs
	cs.position = r.get_center()
	body.add_child(cs)
