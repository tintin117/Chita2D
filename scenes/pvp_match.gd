extends Node2D
## One online deathmatch on the fixed arena. Every peer builds the same scene from Net.roster; each owns its own Player.
## Kills are counted on every peer from the same reliable Player.fragged events; only the host decides when the match ends.

const KILL_LIMIT := 15
const TIME_LIMIT := 300.0

var _map: WorldMap
var _players := {}          ## peer_id -> Player
var _kills := {}
var _deaths := {}
var _time_left := TIME_LIMIT
var _running := false
var _over := false
var _winner := 0
var _banner: Label
var _board: Board

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
	p.set_multiplayer_authority(id)
	p.respawn_point = _pick_spawn.bind(id)
	p.fragged.connect(_on_fragged)
	_map.add_child(p)
	_players[id] = p
	_kills[id] = 0
	_deaths[id] = 0

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
	_say("FIGHT!", 1.2)

func _on_fragged(victim: Player, killer_peer: int) -> void:
	var vid := victim.get_multiplayer_authority()
	_deaths[vid] = _deaths.get(vid, 0) + 1
	if killer_peer != 0 and killer_peer != vid and _kills.has(killer_peer):
		_kills[killer_peer] += 1
		if multiplayer.is_server() and _kills[killer_peer] >= KILL_LIMIT:
			_end.rpc(killer_peer)

func _on_player_left(id: int) -> void:
	var p: Player = _players.get(id)
	if p:
		p.queue_free()
		_players.erase(id)
	if multiplayer.is_server() and _players.size() < 2 and not _over:
		_end.rpc(_players.keys()[0] if not _players.is_empty() else 0)

func _process(delta: float) -> void:
	if _running and not _over:
		_time_left = maxf(_time_left - delta, 0.0)
		if _time_left <= 0.0 and multiplayer.is_server():
			_end.rpc(_leader())

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
	_set_players_active(false)
	var who: String = Net.roster[winner].name if Net.roster.has(winner) else "nobody"
	var hint := "Enter: back to lobby" if multiplayer.is_server() else "Waiting for the host..."
	_banner.text = "%s wins!\n\n%s     Esc: leave" % [who, hint]
	_banner.modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Net.leave()
	elif _over and event.is_action_pressed("ui_accept"):
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
		var ids: Array = arena._players.keys()
		ids.sort_custom(func(a: int, b: int) -> bool: return arena._kills[a] > arena._kills[b])
		for i in ids.size():
			var id: int = ids[i]
			var p: Player = arena._players[id]
			var col: Color = Player.NAME_COLORS[p.player_index % Player.NAME_COLORS.size()]
			var y := 24.0 + i * 22.0
			draw_string(font, Vector2(w - 260, y), p.display_name, HORIZONTAL_ALIGNMENT_LEFT, 150, 16, col)
			draw_string(font, Vector2(w - 100, y), "%d / %d" % [arena._kills[id], arena._deaths[id]], HORIZONTAL_ALIGNMENT_RIGHT, 80, 16, Color.WHITE)
