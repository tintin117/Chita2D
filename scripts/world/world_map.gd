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
const ISO := "res://assets/isometric_tileset/separated_images/tile_%03d.png"
const ISO_SCALE := 2.0                  ## 32 px tiles drawn as 64 x 32 px diamonds
const GRASS := [22, 24, 37, 38, 39, 22, 24, 23]
const WATER_TILES := [104, 105, 106, 107, 108]
const TREE_TILES := [29, 31, 33, 35]   ## leafy blocks: the tree line
const BUSH_TILES := [41, 42, 43, 44]
const ROCK_TILES := [53, 54, 55, 58]
const COVER_TILES := [64, 65, 68, 61]

const CHAMBER_R := Vector2(7.0, 9.5)    ## chamber radius range (cells)
const SPAWN_R := 8.5
const GATE_R := 10.0
const ALCOVE_R := Vector2(4.0, 5.0)
const CORRIDOR_R := 3.0                 ## half width (cells): 7 wide, 5 walkable between the tree lines
const EXTRA_LOOPS := 3                  ## corridors beyond the spanning tree
const DECOR_BUSH := 0.03                ## per open cell
const DECOR_ROCK := 0.012
const ARENA_SEED := 1337                ## the fixed PvP map: every peer builds the identical arena from this
const ARENA_HALF := Vector2(19.2, 11.3) ## cells; the Colosseum's floor is about this big (2450 x 1450 px): the radar sizes itself from it
const ISLAND_HALF := Vector2(16.0, 11.5) ## cells; the old island arena (generate_island): a superellipse plateau, 2048 x 1472 px
const COVER_R := 50.0
const GYM_HALF := Vector2(11.0, 8.0)  ## cells; the training room

var seed_value := 0
var bounds := Rect2(Vector2.ZERO, Vector2(SIZE * TILE))
var spawn_point := Vector2.ZERO
var gate_pos := Vector2.ZERO            ## centre of the far-east gate chamber (boss gate site)
var boss_arena := Rect2()               ## open ground around the gate
var camps: Array[Dictionary] = []       ## {pos: Vector2, tier: int 1..3, radius: float}, one per camp chamber
var objective_sites: Array[Vector2] = [] ## one per alcove
var spawn_points: Array[Vector2] = []   ## arena only: respawn spots round the rim
var cover: Array[Vector2] = []          ## arena only: solid rocks (COVER_R) to fight around
var open_shore := false                 ## arena only: no shore walls, so the water is deadly (see is_water)
var chambers: Array[Dictionary] = []    ## {c: Vector2 (cells), r: float, kind: spawn|gate|camp|alcove}
var colosseum: Colosseum = null         ## the main arena's exact shapes (is_water reads them); null on every other map
var rails: Array[PackedVector2Array] = []   ## Colosseum: low rails [a, b] (block walking on Player.LOW_MASK, not shots)
var water_spots: Array[Vector2] = []    ## Colosseum: centres of the deadly-water cells inside the stands (for the radar)
var _wall_inset := INSET
var cover_r := COVER_R                  ## collision radius of the cover (the Colosseum's braziers are bigger)
var nav: AStarGrid2D = null             ## Colosseum: walking grid for bots (water, rails and braziers are solid); null elsewhere
var _nav_origin := Vector2.ZERO
const NAV_CELL := 32.0
const NAV_MARGIN := 16.0                ## a cell this close to water, a rail or a brazier is solid: paths keep a body's width off

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

## The main PvP map: the Colosseum (see Colosseum). Walls round the stands, deadly pools and moat inside, a centre circle
## reached by bridges, rails, braziers. Same result on every call, so all peers build it independently.
func generate_arena(build_visuals := true) -> void:
	open_shore = false
	_begin_fixed(ARENA_HALF)
	colosseum = Colosseum.new(spawn_point)
	_wall_inset = 6.0   # the wall sits on the stands' edge, not a cell into the sand
	water_spots.clear()
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			var at := center_of(c)
			_land[y * SIZE.x + x] = 1 if colosseum.floor_at(at) else 0
			if colosseum.water_at(at):
				water_spots.append(at)
	_core = _land.duplicate()   # the walls are exact here (no tree-line ring): every floor cell is walkable
	spawn_points = colosseum.spawns()
	cover = colosseum.braziers()
	cover_r = Colosseum.BRAZIER_HALF * Colosseum.S
	rails = colosseum.rails()
	_bfs(cell_of(spawn_point))
	_decor.clear()
	_free.clear()
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			if _is_core(c) and _dist[y * SIZE.x + x] >= 0 and _open2(c):
				_free.append(c)
	_build_nav()
	if build_visuals:
		_build()

## The old fixed arena (Overthrow-style island): a rounded-rectangle plateau in deadly water, 8 rim spawns, a pillar
## ring in the middle and symmetric rock cover. Kept for comparison; no mode uses it.
func generate_island(build_visuals := true) -> void:
	open_shore = true
	var mid := _begin_fixed(ISLAND_HALF)
	spawn_points.clear()
	for k in 8:
		spawn_points.append(center_of(Vector2i(mid + Vector2.from_angle(k * TAU / 8.0) * Vector2(13.0, 8.5))))
	var offsets: Array[Vector2] = [Vector2(4, 0), Vector2(0, 3), Vector2(-4, 0), Vector2(0, -3)]   # pillar ring
	for q: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		offsets.append(Vector2(7, 4) * q)
		offsets.append(Vector2(3, 6) * q)
	for o in offsets:
		cover.append(center_of(Vector2i(mid + o)))
	_finish_fixed(build_visuals)

## Small training room: open ground, one spawn in the middle (the training dummy goes there, the hero beside it).
func generate_gym(build_visuals := true) -> void:
	_begin_fixed(GYM_HALF)
	_finish_fixed(build_visuals)

## Shared start of the fixed maps: reset, fill a rounded-rectangle plateau of `half` cells round the grid centre.
func _begin_fixed(half: Vector2) -> Vector2:
	seed_value = ARENA_SEED
	_rng.seed = ARENA_SEED
	_noise.seed = ARENA_SEED
	for n in _owned:
		n.queue_free()
	_owned.clear()
	chambers.clear()
	camps.clear()
	objective_sites.clear()
	spawn_points.clear()
	cover.clear()
	colosseum = null
	rails.clear()
	water_spots.clear()
	_wall_inset = INSET
	cover_r = COVER_R
	nav = null
	_land.resize(SIZE.x * SIZE.y)
	_land.fill(0)
	var mid := Vector2(SIZE) / 2.0
	for y in SIZE.y:
		for x in SIZE.x:
			var d := (Vector2(x + 0.5, y + 0.5) - mid).abs() / half
			if pow(d.x, 4.0) + pow(d.y, 4.0) <= 1.0:
				_land[y * SIZE.x + x] = 1
	_compute_core()
	spawn_point = center_of(Vector2i(mid))
	gate_pos = spawn_point
	return mid

func _finish_fixed(build_visuals: bool) -> void:
	_bfs(cell_of(spawn_point))
	_scatter_decor()
	if build_visuals:
		_build()

func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / TILE).floor())

func center_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE

## True over water (outside the plateau; in the Colosseum: the pools and the moat, exactly). Position is in world px.
func is_water(pos: Vector2) -> bool:
	if colosseum:   # the deadly water only (pools, moat); beyond the stands is wall, see off_ground
		return colosseum.water_at(pos)
	return not is_land(cell_of(pos))

## No standing ground: deadly water, or (Colosseum) beyond the stands. Where a dash or a leap must not end: a dash at a
## pool by the wall is cut short on the sand instead of being stopped by the wall in the middle of the pool.
func off_ground(pos: Vector2) -> bool:
	if colosseum:
		return not colosseum.inside(pos) or colosseum.water_at(pos)
	return is_water(pos)

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
	_compute_core()

func _compute_core() -> void:
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
	keep_clear.append_array(spawn_points)
	keep_clear.append_array(cover)
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

	var lo := Vector2i(SIZE)
	var hi := Vector2i.ZERO
	for y in SIZE.y:
		for x in SIZE.x:
			if is_land(Vector2i(x, y)):
				lo = lo.min(Vector2i(x, y))
				hi = hi.max(Vector2i(x + 1, y + 1))
	var area := Rect2(Vector2(lo * TILE), Vector2((hi - lo) * TILE)).grow_individual(1200, 800, 1200, 800)
	if colosseum:
		var art := ColosseumArt.new()
		art.shape = colosseum
		art.position = colosseum.center
		ground.add_child(art)
	else:
		iso_ground(ground, area, func(p: Vector2) -> bool: return not is_water(p))

	var walls := StaticBody2D.new()
	walls.collision_layer = 1 | Player.WALL_MASK   # walls also sit on the wall layer: a dash passes rocks but never these
	walls.collision_mask = 0
	if not open_shore:
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
			_add_rect(walls, Rect2(x0 * TILE - _wall_inset, y * TILE - _wall_inset, (x - x0) * TILE + 2 * _wall_inset, TILE + 2 * _wall_inset))

	for d in _decor:
		var tiles: Array = {"tree": TREE_TILES, "bush": BUSH_TILES}.get(d.kind, ROCK_TILES)
		var s := _iso_sprite(tiles[d.variant - 1], ISO_SCALE)
		s.position = d.pos
		add_child(s)
		_owned.append(s)
	_build_cover()
	_build_rails()

## Colosseum rails: thin solid bars on Player.LOW_MASK only. Players bump into them; projectiles (mask 1 | 2) fly over,
## and a dash or a leap (collision mask = WALL_MASK only) goes across.
func _build_rails() -> void:
	if rails.is_empty():
		return
	var body := StaticBody2D.new()
	body.collision_layer = Player.LOW_MASK
	body.collision_mask = 0
	for seg in rails:
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(seg[0].distance_to(seg[1]) + Colosseum.RAIL_W, Colosseum.RAIL_W)
		cs.shape = rs
		cs.position = (seg[0] + seg[1]) / 2.0
		cs.rotation = (seg[1] - seg[0]).angle()
		body.add_child(cs)
	add_child(body)
	_owned.append(body)

func _build_cover() -> void:
	for i in cover.size():
		var rock := StaticBody2D.new()
		rock.collision_layer = 1
		rock.collision_mask = 0
		rock.position = cover[i]
		var cs := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = cover_r
		cs.shape = circle
		rock.add_child(cs)
		if colosseum == null:   # the Colosseum draws its braziers itself (ColosseumArt)
			rock.add_child(_iso_sprite(COVER_TILES[i % 4], 4.0))
		add_child(rock)
		_owned.append(rock)

func _shore_water(c: Vector2i) -> bool:
	if colosseum:   # only the stands are wall: every cell outside them that touches the inside (sand or water)
		if colosseum.inside(center_of(c)):
			return false   # the pools and the moat are open water you can be knocked into
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if colosseum.inside(center_of(c + Vector2i(dx, dy))):
					return true
		return false
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

## A tileset piece standing on its node's position (the tile's ground diamond sits 4-20 px down a 32 px image).
static func _iso_sprite(tile: int, sc: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(ISO % tile)
	s.scale = Vector2.ONE * sc
	s.offset.y = -8.0
	return s

## Isometric ground over `area` (world px): grass where land.call(pos) is true, water elsewhere. Land is its own
## y-sorted layer above the water, so the shore shows the cliff faces. Visual only: is_water() still decides ring-outs.
static func iso_ground(parent: Node, area: Rect2, land: Callable) -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_size = Vector2i(32, 16)
	for id: int in GRASS + WATER_TILES:
		if ts.has_source(id):
			continue
		var src := TileSetAtlasSource.new()
		src.texture = load(ISO % id)
		src.texture_region_size = Vector2i(32, 32)
		src.create_tile(Vector2i.ZERO)
		ts.add_source(src, id)
		src.get_tile_data(Vector2i.ZERO, 0).texture_origin = Vector2i(0, -4)   # top diamond (y 4..20) on the cell
	var water := TileMapLayer.new()
	var ground := TileMapLayer.new()
	for l: TileMapLayer in [water, ground]:
		l.tile_set = ts
		l.scale = Vector2.ONE * ISO_SCALE
		l.position = area.position
		parent.add_child(l)
	ground.y_sort_enabled = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for cy in int(area.size.y / (8.0 * ISO_SCALE)) + 2:
		for cx in int(area.size.x / (32.0 * ISO_SCALE)) + 2:
			var c := Vector2i(cx, cy)
			var on_land: bool = land.call(area.position + ground.map_to_local(c) * ISO_SCALE)
			var pick: Array = GRASS if on_land else WATER_TILES
			(ground if on_land else water).set_cell(c, pick[rng.randi() % pick.size()], Vector2i.ZERO)

# --- bot navigation (Colosseum) ---------------------------------------------------------------------------------

## A 32 px grid over the floor. A cell is solid when its middle, or any point NAV_MARGIN round it, is not standing
## ground, or it is within NAV_MARGIN of a rail or a brazier. Bots walk it with nav_step(); a dash or a leap still
## goes over rails, which the grid does not model.
func _build_nav() -> void:
	if colosseum == null:
		return
	var lo := colosseum.to_world(Colosseum.FLOOR.position)
	var hi := colosseum.to_world(Colosseum.FLOOR.end)
	_nav_origin = lo
	var cells := Vector2i(ceili((hi.x - lo.x) / NAV_CELL), ceili((hi.y - lo.y) / NAV_CELL))
	nav = AStarGrid2D.new()
	nav.region = Rect2i(Vector2i.ZERO, cells)
	nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
	nav.offset = lo + Vector2(NAV_CELL, NAV_CELL) / 2.0
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	var probes: Array[Vector2] = [Vector2.ZERO, Vector2(NAV_MARGIN, 0), Vector2(-NAV_MARGIN, 0), Vector2(0, NAV_MARGIN), Vector2(0, -NAV_MARGIN)]
	for y in cells.y:
		for x in cells.x:
			var at := nav_point(Vector2i(x, y))
			var solid := false
			for o in probes:
				if not colosseum.floor_at(at + o):
					solid = true
					break
			if not solid:
				for c in cover:
					if at.distance_to(c) < cover_r + NAV_MARGIN:
						solid = true
						break
			if not solid:
				for seg in rails:
					if Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1]).distance_to(at) < Colosseum.RAIL_W / 2.0 + NAV_MARGIN:
						solid = true
						break
			nav.set_point_solid(Vector2i(x, y), solid)

func nav_point(c: Vector2i) -> Vector2:
	return _nav_origin + (Vector2(c) + Vector2(0.5, 0.5)) * NAV_CELL

func nav_cell(at: Vector2) -> Vector2i:
	return Vector2i(((at - _nav_origin) / NAV_CELL).floor())

func nav_open(c: Vector2i) -> bool:
	return nav != null and nav.is_in_boundsv(c) and not nav.is_point_solid(c)

## The open cell nearest `at` (searching outward a few rings), or (-1, -1).
func _nav_nearest_open(at: Vector2) -> Vector2i:
	var c := nav_cell(at)
	if nav_open(c):
		return c
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and nav_open(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return Vector2i(-1, -1)

const NAV_BODY := 12.0   ## half the width of the strip a straight walk must keep clear (a body, not a thin line)

## True if walking straight from a to b stays on open cells, for the whole width of a body: the centre line and both
## edges (NAV_BODY either side), so a shortcut never clips a rail end or a brazier corner and grinds against it.
func nav_clear(a: Vector2, b: Vector2) -> bool:
	if nav == null:
		return true
	var d := b - a
	var side := d.orthogonal().normalized() * NAV_BODY if d.length() > 1.0 else Vector2.ZERO
	var n := maxi(int(a.distance_to(b) / (NAV_CELL * 0.5)), 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		for q in [p, p + side, p - side]:
			if not nav_open(nav_cell(q)):
				return false
	return true

## The next step along the route, no shortcuts: toward the first waypoint at least half a cell away. For unsticking.
func nav_next(from: Vector2, to: Vector2) -> Vector2:
	var path := nav_path(from, to)
	for p in path:
		if p.distance_to(from) > NAV_CELL * 0.5:
			return (p - from).normalized()
	return (to - from).normalized() if to.distance_to(from) > 1.0 else Vector2.ZERO

## Walking path from `from` to `to` (world points, nearest open cells at both ends); empty if none.
func nav_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if nav == null:
		return PackedVector2Array()
	var a := _nav_nearest_open(from)
	var b := _nav_nearest_open(to)
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	return nav.get_point_path(a, b, true)

## Which way to walk from `from` to reach `to`: straight if the line is clear, else toward the farthest waypoint of the
## path that can be walked to in a straight line. Maps without a grid (and unreachable goals): straight.
func nav_step(from: Vector2, to: Vector2) -> Vector2:
	var straight := (to - from).normalized() if to.distance_to(from) > 1.0 else Vector2.ZERO
	if nav == null or nav_clear(from, to):
		return straight
	var path := nav_path(from, to)
	if path.size() < 2:
		return straight
	if not nav_open(nav_cell(from)) and path[0].distance_to(from) > 4.0:
		return (path[0] - from).normalized()   # pushed against a rail or the shore: step back onto the route first
	var goal := path[1]
	for i in range(mini(path.size() - 1, 6), 0, -1):
		if nav_clear(from, path[i]):
			goal = path[i]
			break
	return (goal - from).normalized() if goal.distance_to(from) > 1.0 else straight

## The direction to the nearest dry ground round `feet` (a knocked-in or sliding bot's way out); zero if all dry or none found.
func dry_dir(feet: Vector2) -> Vector2:
	for r in [40.0, 90.0, 160.0, 260.0]:
		for k in 16:
			var d := Vector2.from_angle(k * TAU / 16.0)
			if not is_water(feet + d * r) and (colosseum == null or colosseum.inside(feet + d * r)):
				return d
	return Vector2.ZERO

## Length of the walking route from `from` to `to` (straight if the line is clear; INF if there is none).
func nav_length(from: Vector2, to: Vector2) -> float:
	if nav == null or nav_clear(from, to):
		return from.distance_to(to)
	var path := nav_path(from, to)
	if path.size() < 2:
		return INF
	var total := from.distance_to(path[0])
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total + path[path.size() - 1].distance_to(to)

## A dash that saves a long walk: the direction to dash from `from` toward `to`, or zero. A dash goes through rails
## and braziers (its mask is the room walls only) and can jump a water channel as long as it lands dry, so this covers
## hopping a rail onto a platform, cutting past a brazier, and jumping the moat (plus its rail) onto the crown circle.
## Conditions: the straight walk is blocked; the dash (up to `dash_px`) lands on an open nav cell; every point of it is
## inside the stands (walls stop dashes) and its water stretch is jumped, not landed in; and it cuts the walk to `to` by a
## third or more (or the walk has no route at all and the landing is closer).
func dash_shortcut(from: Vector2, to: Vector2, dash_px := 220.0) -> Vector2:
	if nav == null or nav_clear(from, to):
		return Vector2.ZERO
	var d := (to - from).normalized()
	var land := from + d * minf(dash_px, from.distance_to(to))
	if not nav_open(nav_cell(land)) or is_water(land + Vector2(0, 14)) or is_water(from + Vector2(0, 14)):
		return Vector2.ZERO
	if colosseum:
		for i in 9:
			if not colosseum.inside(from.lerp(land, i / 8.0) + Vector2(0, 14)):
				return Vector2.ZERO   # would hit the wall mid-dash
	var walk := nav_length(from, to)
	var hop := from.distance_to(land) + nav_length(land, to)
	if walk == INF:
		return d if land.distance_to(to) < from.distance_to(to) - 60.0 else Vector2.ZERO
	return d if hop < walk * 0.67 else Vector2.ZERO

## Old name (rails were the first shortcut): see dash_shortcut.
func rail_hop(from: Vector2, to: Vector2, dash_px := 220.0) -> Vector2:
	return dash_shortcut(from, to, dash_px)

## Crown holder's zone: the Colosseum's centre circle (inside its rail, off the moat), elsewhere a circle round the middle.
func hold_radius() -> float:
	if colosseum:
		return (Colosseum.MOAT.x - 45.0) * Colosseum.S
	return 300.0
