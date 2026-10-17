extends Node2D
## One online deathmatch on the fixed arena. Every peer builds the same scene from Net.roster; each owns its own Player.
## Kills are counted on every peer from the same reliable Player.fragged events; only the host decides when the match ends.

const KILL_LIMIT := 15
const TIME_LIMIT := 300.0
const CAM_ZOOM := 0.65            ## <1 = camera higher; 1.0 showed only ~1/3 of the arena
const PICKUP_EVERY := 12.0
const MAX_PICKUPS := 3
const PICKUP_SPAWN_CLEAR := 600.0 ## pickups never appear this close to a player spawn (the short axis of the spawn ring is only 768 px from the centre)
const PICKUP_COVER_CLEAR := 120.0
const PICKUP_APART := 400.0
const CROWN_MIN_KILLS := 3        ## the kill leader wears the crown from here on (needs a strict lead)
const BOUNTY := 2                 ## kills toward the limit for killing the crown holder
const VERBS_HIT := ["bonked", "deleted", "humbled", "launched", "clapped", "sent to the shadow realm"]
const LINES_FALL := ["%s took a swim", "%s forgot how to walk", "%s tried to fly", "%s found the water"]
const LINES_BOMB := ["%s was blown up by the potato", "%s got the hot potato", "%s went out with a bang"]

var _map: WorldMap
var _pickups := {}          ## id -> PvpPickup
var _next_pickup := 1
var _pickup_timer := PICKUP_EVERY / 2.0
var _players := {}          ## peer_id -> Player
var _kills := {}
var _deaths := {}
var _time_left := TIME_LIMIT
var _running := false
var _over := false
var _winner := 0
var _banner: Label
var _board: Board
var _feed: KillFeed
var _crown := 0             ## peer wearing the crown, 0 = nobody
var _kill_count := 0        ## every death so far; picks the kill-feed wording the same way on every peer
var _stats := {}            ## peer -> {streak, best, falls, bombs, pickups, emotes, crown}
var _killed_by := {}        ## Vector2i(killer, victim) -> times

## The spawn point that is farthest from every living opponent (respawns land away from the fight).
static func farthest_spawn(points: Array[Vector2], others: Array[Vector2]) -> Vector2:
	var best := points[0]
	var best_d := -1.0
	for p in points:
		var d := INF
		for o in others:
			d = minf(d, p.distance_to(o))
		if d > best_d:
			best_d = d
			best = p
	return best

## The crown holder: the strict kill leader with at least CROWN_MIN_KILLS, else 0. `kills` is peer -> kills.
static func crown_holder(kills: Dictionary) -> int:
	var best := 0
	var best_k := 0
	var second := 0
	for id: int in kills:
		var k: int = kills[id]
		if k > best_k:
			second = best_k
			best_k = k
			best = id
		elif k > second:
			second = k
	return best if best_k >= CROWN_MIN_KILLS and best_k > second else 0

## One kill-feed line. `killer` is "" when nobody gets the credit; `n` picks the wording.
static func kill_line(cause: String, killer: String, victim: String, n: int) -> String:
	match cause:
		"fall":
			var text: String = LINES_FALL[n % LINES_FALL.size()] % victim
			return text if killer == "" else "%s (pushed by %s)" % [text, killer]
		"bomb":
			return LINES_BOMB[n % LINES_BOMB.size()] % victim
	return "%s %s %s" % [killer, VERBS_HIT[n % VERBS_HIT.size()], victim]

static func new_stats() -> Dictionary:
	return {"streak": 0, "best": 0, "falls": 0, "bombs": 0, "pickups": 0, "emotes": 0, "crown": 0.0}

## The peer with the highest value[key] that reaches `minimum` (ties go to the lowest peer id), or 0.
static func _top(values: Dictionary, minimum: float) -> int:
	var best := 0
	for id: int in values:
		if values[id] >= minimum and (best == 0 or values[id] > values[best] or (values[id] == values[best] and id < best)):
			best = id
	return best

## End-of-match awards, at most 6: [{title, who, detail}]. stats: peer -> new_stats(); kills/deaths: peer -> int;
## killed_by: Vector2i(killer, victim) -> int; names: peer -> String. Only awards somebody actually earned.
static func awards(stats: Dictionary, kills: Dictionary, deaths: Dictionary, killed_by: Dictionary, names: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by := func(key: String) -> Dictionary:
		var d := {}
		for id: int in stats:
			d[id] = stats[id][key]
		return d
	var add := func(title: String, id: int, detail: String) -> void:
		if id != 0:
			out.append({"title": title, "who": names.get(id, "?"), "detail": detail})
	var id := _top(kills, 1)
	add.call("Top Fragger", id, "%d kills" % kills.get(id, 0))
	id = _top(by.call("best"), 3)
	add.call("Killing Spree", id, "%d in a row" % stats.get(id, {}).get("best", 0))
	var pair := Vector2i.ZERO
	var pair_n := 2
	for k: Vector2i in killed_by:
		if killed_by[k] > pair_n or (killed_by[k] == pair_n and pair != Vector2i.ZERO and k.x < pair.x):
			pair = k
			pair_n = killed_by[k]
	if pair != Vector2i.ZERO:
		add.call("Nemesis", pair.x, "killed %s %d times" % [names.get(pair.y, "?"), pair_n])
	id = _top(by.call("crown"), 10.0)
	add.call("Long Live the King", id, "%d s on the throne" % int(stats.get(id, {}).get("crown", 0.0)))
	id = _top(deaths, 3)
	add.call("Punching Bag", id, "%d deaths" % deaths.get(id, 0))
	id = _top(by.call("falls"), 1)
	add.call("Aquaman", id, "%d swims" % stats.get(id, {}).get("falls", 0))
	id = _top(by.call("bombs"), 1)
	add.call("Well Done", id, "blown up %d times" % stats.get(id, {}).get("bombs", 0))
	id = _top(by.call("pickups"), 3)
	add.call("Hoarder", id, "%d pickups" % stats.get(id, {}).get("pickups", 0))
	id = _top(by.call("emotes"), 4)
	add.call("Chatterbox", id, "%d emotes" % stats.get(id, {}).get("emotes", 0))
	var top: Array[Dictionary] = []
	for i in mini(6, out.size()):
		top.append(out[i])
	return top

func _ready() -> void:
	_map = WorldMap.new()
	_map.name = "Arena"   # fixed names: RPC and replication paths must match on every peer
	add_child(_map)
	_map.generate_arena()

	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	for id: int in ids:
		_spawn(id, Net.roster[id])

	var cam := GameCamera.new()
	cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	add_child(cam)
	var me: Player = _players.get(Net.local_id())
	if me:
		cam.target = me
		cam.global_position = me.global_position
		var hud := Hud.new()
		hud.with_sheet = false
		hud.online = true
		add_child(hud)
		hud.add_player(me)

	var ui := CanvasLayer.new()
	ui.layer = 10
	_board = Board.new()
	_board.arena = self
	ui.add_child(_board)
	var radar := Radar.new()
	radar.arena = self
	ui.add_child(radar)
	_feed = KillFeed.new()
	ui.add_child(_feed)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.text = "Waiting for players..."
	ui.add_child(_banner)
	add_child(ui)

	_set_players_active(false)
	Net.match_go.connect(_on_go, CONNECT_ONE_SHOT)
	Net.player_left.connect(_on_player_left)
	Net.report_loaded()

func _spawn(id: int, info: Dictionary) -> void:
	var p := Player.new()
	p.name = str(id)
	p.online = true
	p.player_index = info.slot
	p.hero = Hero.by_id(info.hero)
	p.display_name = info.name
	p.position = _map.spawn_points[info.slot % _map.spawn_points.size()]
	p.peer_id = id
	if info.get("bot", false):
		p.ai = BotBrain.new()
		p.ai.setup(p, self, info.get("skill", 0.6))   # a bot keeps the local peer's authority, so every RPC and hit runs here
	else:
		p.set_multiplayer_authority(id)
	p.respawn_point = _pick_spawn.bind(id)
	p.water_check = _map.is_water
	p.fragged.connect(_on_fragged)
	p.bomb_touch.connect(_on_bomb_touch.bind(p))
	_map.add_child(p)
	_players[id] = p
	_kills[id] = 0
	_deaths[id] = 0
	_stats[id] = new_stats()
	p.emoted.connect(_on_emoted)

func _pick_spawn(id: int) -> Vector2:
	var others: Array[Vector2] = []
	for k: int in _players:
		if k != id and not _players[k].down:
			others.append(_players[k].global_position)
	return farthest_spawn(_map.spawn_points, others) if not others.is_empty() else _map.spawn_points[0]

func _set_players_active(on: bool) -> void:
	for p: Player in _players.values():
		p.set_physics_process(on)

func _on_go() -> void:
	_running = true
	_set_players_active(true)
	Sfx.play("fight")
	_say("FIGHT!   (1-4: emotes)", 1.6)

func _on_fragged(victim: Player, killer_peer: int, cause: String) -> void:
	var vid := victim.peer_id
	if victim.ai:
		victim.ai.on_death(cause)
	var killer_player: Player = _players.get(killer_peer)
	if killer_player and killer_player.ai and killer_peer != vid:
		killer_player.ai.on_kill()
	if multiplayer.is_server() and victim.has_bomb:
		var killer: Player = _players.get(killer_peer)
		if killer != null and killer != victim and not killer.down and not killer.has_bomb:
			_net_bomb_move.rpc(vid, killer_peer, victim.bomb_left)   # revenge potato
		else:
			_net_bomb_boom.rpc(vid)
	_deaths[vid] = _deaths.get(vid, 0) + 1
	var vs: Dictionary = _stats[vid]
	vs.streak = 0
	if cause == "fall":
		vs.falls += 1
	elif cause == "bomb":
		vs.bombs += 1
	var credited := killer_peer != 0 and killer_peer != vid and _kills.has(killer_peer)
	var killer_name := _name_of(killer_peer) if credited else ""
	var line := kill_line(cause, killer_name, _name_of(vid), _kill_count)
	_kill_count += 1
	if credited:
		var reign := vid == _crown   # decided before the credit: killing the king pays a bounty
		_kills[killer_peer] += BOUNTY if reign else 1
		_killed_by[Vector2i(killer_peer, vid)] = _killed_by.get(Vector2i(killer_peer, vid), 0) + 1
		var ks: Dictionary = _stats[killer_peer]
		ks.streak += 1
		ks.best = maxi(ks.best, ks.streak)
		Sfx.play("kill")
		if reign:
			line += "   (+%d bounty!)" % BOUNTY
			_say("%s ended %s's reign!" % [killer_name, _name_of(vid)], 1.8)
		if multiplayer.is_server() and _kills[killer_peer] >= KILL_LIMIT:
			_end.rpc(killer_peer)
	_feed.add(line, _color_of(killer_peer if credited else vid))
	_update_crown()

func _name_of(id: int) -> String:
	var p: Player = _players.get(id)
	return p.display_name if p else str(Net.roster.get(id, {}).get("name", "?"))

func _color_of(id: int) -> Color:
	var p: Player = _players.get(id)
	return Player.NAME_COLORS[p.player_index % Player.NAME_COLORS.size()] if p else Color.WHITE

## Recomputed from the replicated kill counts, so every peer agrees without extra messages.
func _update_crown() -> void:
	var present := {}   # a player who left cannot keep the crown
	for id: int in _kills:
		if _players.has(id):
			present[id] = _kills[id]
	var holder := crown_holder(present)
	if holder == _crown:
		return
	_crown = holder
	for id: int in _players:
		_players[id].crowned = id == _crown
	if _crown != 0:
		Sfx.play("crown")
		_say("%s took the crown!" % _name_of(_crown), 1.8)

func _on_emoted(p: Player) -> void:
	var id := p.peer_id
	if _stats.has(id):
		_stats[id].emotes += 1

func _on_player_left(id: int) -> void:
	var p: Player = _players.get(id)
	if p:
		if p.has_bomb and multiplayer.is_server():
			_net_bomb_boom.rpc(id)
		p.queue_free()
		_players.erase(id)
	if multiplayer.is_server() and _players.size() < 2 and not _over:
		_end.rpc(_players.keys()[0] if not _players.is_empty() else 0)

func _process(delta: float) -> void:
	if _running and not _over:
		_time_left = maxf(_time_left - delta, 0.0)
		if _crown != 0 and _stats.has(_crown):
			_stats[_crown].crown += delta
		if _time_left <= 0.0 and multiplayer.is_server():
			_end.rpc(_leader())
		if multiplayer.is_server():
			for id: int in _players:
				var carrier: Player = _players[id]
				if carrier.has_bomb and carrier.bomb_left <= 0.0:
					_net_bomb_boom.rpc(id)
			_pickup_timer -= delta
			if _pickup_timer <= 0.0:
				_pickup_timer = PICKUP_EVERY
				if _pickups.size() < MAX_PICKUPS:
					_net_spawn_pickup.rpc(_next_pickup, PvpPickup.roll(randf()), _pickup_pos())

## A spot on open ground near the middle: away from every player spawn, the cover and other pickups.
## Only the host calls this; the result travels in the spawn RPC, so peers never touch the map's RNG.
func _pickup_pos() -> Vector2:
	var taken: Array[Vector2] = []
	for pk: PvpPickup in _pickups.values():
		taken.append(pk.position)
	return pick_pickup_pos(_map, taken)

static func pick_pickup_pos(map: WorldMap, taken: Array[Vector2]) -> Vector2:
	for i in 150:
		var p := map.random_open_point()
		if _clear_of(p, map.spawn_points, PICKUP_SPAWN_CLEAR) and _clear_of(p, map.cover, PICKUP_COVER_CLEAR) and _clear_of(p, taken, PICKUP_APART):
			return p
	return map.spawn_point   # arena centre

static func _clear_of(p: Vector2, points: Array[Vector2], dist: float) -> bool:
	for q in points:
		if p.distance_to(q) < dist:
			return false
	return true

@rpc("authority", "call_local", "reliable")
func _net_spawn_pickup(id: int, kind: String, pos: Vector2) -> void:
	var pk := PvpPickup.new()
	pk.name = "pk%d" % id
	pk.id = id
	pk.kind = kind
	pk.position = pos
	pk.touched.connect(_on_pickup_touched)
	_map.add_child(pk)
	_pickups[id] = pk
	_next_pickup = maxi(_next_pickup, id + 1)
	_say("%s appeared!" % PvpPickup.LABELS[kind], 1.5)

func _on_pickup_touched(id: int, peer: int) -> void:
	_claim.rpc_id(1, id, peer)

## The host serialises claims: the first one for an id wins, later ones find it already gone.
@rpc("any_peer", "call_local", "reliable")
func _claim(id: int, taker: int) -> void:
	if not multiplayer.is_server() or not _pickups.has(id):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != taker and not Net.solo:
		return   # a peer can only claim for its own player (a solo match has the one peer claiming for its bots too)
	var outcome: String = _pickups[id].kind
	if outcome == "mystery":
		outcome = PvpPickup.mystery_outcome(randf())   # the host rolls it so every peer sees the same result
	var p: Player = _players.get(taker)
	if outcome == "bomb" and (p == null or p.has_bomb):
		outcome = "damage"   # one potato per player
	_net_take.rpc(id, taker, outcome)

@rpc("authority", "call_local", "reliable")
func _net_take(id: int, peer: int, outcome: String) -> void:
	var pk: PvpPickup = _pickups.get(id)
	if pk == null:
		return
	_pickups.erase(id)
	pk.queue_free()
	Sfx.play("pickup", pk.position)
	if _stats.has(peer):
		_stats[peer].pickups += 1
	var p: Player = _players.get(peer)
	if p:
		if pk.kind == "mystery":
			p.float_text("Mystery box!", PvpPickup.COLORS["mystery"])
		p.apply_pickup(outcome)

# --- hot potato: touching another player passes it on; the host runs the fuse and decides when it blows

func _on_bomb_touch(other: Player, carrier: Player) -> void:
	_bomb_pass.rpc_id(1, carrier.peer_id, other.peer_id)

@rpc("any_peer", "call_local", "reliable")
func _bomb_pass(from_peer: int, to_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != from_peer and not Net.solo:
		return
	var a: Player = _players.get(from_peer)
	var b: Player = _players.get(to_peer)
	if a == null or b == null or not a.has_bomb or b.has_bomb or b.down:
		return
	_net_bomb_move.rpc(from_peer, to_peer, a.bomb_left)

@rpc("authority", "call_local", "reliable")
func _net_bomb_move(from_peer: int, to_peer: int, fuse: float) -> void:
	var a: Player = _players.get(from_peer)
	var b: Player = _players.get(to_peer)
	if a:
		a.clear_bomb()
	if b:
		b.give_bomb(fuse)
		b.float_text("HOT POTATO!", PvpPickup.COLORS["bomb"])

@rpc("authority", "call_local", "reliable")
func _net_bomb_boom(peer: int) -> void:
	var p: Player = _players.get(peer)
	if p == null:
		return
	p.clear_bomb()
	Sfx.play("bomb_boom", p.global_position)
	# no source: it hurts the carrier too, and anyone it kills is a "blown up", not a kill for somebody
	_map.add_child(Explosion.new().setup(p.global_position, 150.0, 70, 0.05, null))

func _leader() -> int:
	var best := 0
	for id: int in _players:
		if best == 0 or _kills[id] > _kills[best] or (_kills[id] == _kills[best] and _deaths[id] < _deaths[best]):
			best = id
	return best

@rpc("authority", "call_local", "reliable")
func _end(winner: int) -> void:
	_over = true
	_winner = winner
	Sfx.play("win")
	_set_players_active(false)
	var who: String = Net.roster[winner].name if Net.roster.has(winner) else "nobody"
	var hint := "Enter: play again" if Net.solo else ("Enter: back to lobby" if multiplayer.is_server() else "Waiting for the host...")
	var names := {}
	for id: int in _stats:
		names[id] = _name_of(id)
	var results := Results.new()
	results.title = "%s wins!" % who
	results.rows = awards(_stats, _kills, _deaths, _killed_by, names)
	results.hint = "%s     Esc: leave" % hint
	_banner.get_parent().add_child(results)
	_banner.modulate.a = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Net.leave()
	elif _over and event.is_action_pressed("ui_accept"):
		if Net.solo:
			get_tree().reload_current_scene()
		else:
			Net.back_to_lobby()

func _say(text: String, seconds: float) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	create_tween().tween_property(_banner, "modulate:a", 0.0, 0.5).set_delay(seconds)

## Top-right scoreboard: time left and kills / deaths, best first.
class Board extends Control:
	var arena: Node

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var w := get_viewport_rect().size.x
		var t := int(ceil(arena._time_left))
		draw_string(font, Vector2(0, 30), "%d:%02d    first to %d" % [t / 60, t % 60, KILL_LIMIT], HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color.WHITE)
		var me: Player = arena._players.get(Net.local_id())
		if me:
			var line := ""
			for kind: String in ["damage", "speed", "giant", "chicken"]:
				if me.buffed(kind):
					line += "%s %ds   " % [PvpPickup.LABELS[kind], ceili(me.buff_left(kind))]
			draw_string(font, Vector2(0, 56), line, HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(1.0, 0.9, 0.4))
		var ids: Array = arena._players.keys()
		ids.sort_custom(func(a: int, b: int) -> bool: return arena._kills[a] > arena._kills[b])
		for i in ids.size():
			var id: int = ids[i]
			var p: Player = arena._players[id]
			var col: Color = Player.NAME_COLORS[p.player_index % Player.NAME_COLORS.size()]
			var y := 24.0 + i * 22.0
			draw_string(font, Vector2(w - 260, y), p.display_name, HORIZONTAL_ALIGNMENT_LEFT, 150, 16, col)
			draw_string(font, Vector2(w - 100, y), "%d / %d" % [arena._kills[id], arena._deaths[id]], HORIZONTAL_ALIGNMENT_RIGHT, 80, 16, Color.WHITE)

## Top-left list of the last few deaths; each line fades out after LIFE seconds.
class KillFeed extends Control:
	const LIFE := 6.0
	const MAX := 5
	var _lines: Array[Dictionary] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add(text: String, color: Color) -> void:
		_lines.append({"text": text, "color": color, "age": 0.0})
		if _lines.size() > MAX:
			_lines.pop_front()

	func _process(delta: float) -> void:
		for l in _lines:
			l.age += delta
		_lines = _lines.filter(func(l: Dictionary) -> bool: return l.age < LIFE)
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for i in _lines.size():
			var l: Dictionary = _lines[i]
			var a := clampf((LIFE - l.age) / 1.0, 0.0, 1.0)
			var pos := Vector2(16, 44 + i * 24)
			draw_string_outline(font, pos, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, a))
			draw_string(font, pos, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(l.color, a))

## End-of-match screen: winner, the awards, and how to leave.
class Results extends Control:
	var title := ""
	var rows: Array[Dictionary] = []
	var hint := ""

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var vp := get_viewport_rect().size
		var h := 150.0 + rows.size() * 36.0
		var panel := Rect2((vp.x - 640.0) / 2.0, (vp.y - h) / 2.0, 640.0, h)
		draw_rect(panel, Color(0.04, 0.04, 0.07, 0.88))
		draw_rect(panel, Color(1.0, 0.85, 0.3), false, 3.0)
		draw_string_outline(font, panel.position + Vector2(0, 58), title, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 44, 8, Color.BLACK)
		draw_string(font, panel.position + Vector2(0, 58), title, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 44, Color(1.0, 0.85, 0.3))
		for i in rows.size():
			var r: Dictionary = rows[i]
			var y := 108.0 + i * 36.0
			draw_string(font, panel.position + Vector2(28, y), r.title, HORIZONTAL_ALIGNMENT_LEFT, 240, 22, Color(1.0, 0.85, 0.3))
			draw_string(font, panel.position + Vector2(280, y), "%s   %s" % [r.who, r.detail], HORIZONTAL_ALIGNMENT_LEFT, 340, 20, Color.WHITE)
		draw_string(font, panel.position + Vector2(0, h - 22), hint, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 18, Color(0.75, 0.85, 1.0))

## Bottom-right radar of the whole plateau: cover, pickups, living enemies (red) and you (white ring).
class Radar extends Control:
	const WIDTH := 220.0
	const MARGIN := 20.0
	var arena: Node
	var _scale := WIDTH / (WorldMap.ARENA_HALF.x * 2.0 * WorldMap.TILE)

	func _ready() -> void:
		size = Vector2(WIDTH, WorldMap.ARENA_HALF.y * 2.0 * WorldMap.TILE * _scale)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		position = get_viewport_rect().size - size - Vector2(MARGIN, MARGIN)
		queue_redraw()

	func _to_radar(world: Vector2) -> Vector2:
		return size / 2.0 + (world - arena._map.spawn_point) * _scale

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.05, 0.6))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.75, 0.55, 0.8), false, 2.0)
		for c: Vector2 in arena._map.cover:
			draw_circle(_to_radar(c), 2.5, Color(0.55, 0.55, 0.5))
		for pk: PvpPickup in arena._pickups.values():
			var p := _to_radar(pk.position)
			var col: Color = PvpPickup.COLORS[pk.kind]
			var pts := PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)])
			draw_colored_polygon(pts, col)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.BLACK, 1.5)
		var me_id := Net.local_id()
		for id: int in arena._players:
			var pl: Player = arena._players[id]
			if pl.down:
				continue
			var p := _to_radar(pl.global_position)
			if id == me_id:
				draw_arc(p, 5.0, 0.0, TAU, 20, Color.BLACK, 3.5)
				draw_arc(p, 5.0, 0.0, TAU, 20, Color.WHITE, 1.8)
			else:
				draw_circle(p, 3.5, Color(1.0, 0.25, 0.2))
			if id == arena._crown:
				draw_arc(p, 8.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3), 2.5)
