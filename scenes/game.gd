extends Node2D
## Demo flow: Arena -> Room 2 -> Room 3 -> Boss. Waves per room, revive + heal on clear, exit gate to advance.

const ROOMS := [
	{"title": "The Arena", "size": Vector2i(22, 13),
		"waves": [["grunt", "grunt"], ["grunt", "grunt", "archer"]]},
	{"title": "Archers' Meadow", "size": Vector2i(24, 14),
		"waves": [["archer", "archer", "grunt"], ["grunt", "grunt", "grunt", "archer"], ["lancer", "archer", "archer"]]},
	{"title": "Lancer Pass", "size": Vector2i(24, 14),
		"waves": [["lancer", "grunt", "grunt"], ["lancer", "lancer", "archer"], ["lancer", "grunt", "grunt", "archer", "archer"]]},
	{"title": "The Black Lancer", "size": Vector2i(26, 15), "waves": [], "boss": true},
]

@export var num_players := 2
@export var start_room := 0   ## dev: first room index (3 = boss)

var _room: Room
var _players: Array[Player] = []
var _hud: Hud
var _cam: GameCamera
var _banner: Label
var _over := false
var _over_msec := 0
var _selecting := false
var _index := -1  # set from start_room in _ready

func _ready() -> void:
	y_sort_enabled = true
	_hud = Hud.new()
	add_child(_hud)
	_cam = GameCamera.new()
	add_child(_cam)
	var ui := CanvasLayer.new()
	ui.layer = 10
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 48)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.modulate.a = 0.0
	ui.add_child(_banner)
	add_child(ui)
	_room = Room.new()  # backdrop for the title screen; replaced by _next_room()
	add_child(_room)
	_cam.global_position = _room.center()
	_show("WIZARDS OF CHITA\n\n1 / A - Solo      2 / X - Co-op", 0.0, true)

func _unhandled_input(event: InputEvent) -> void:
	if _over:
		# Enter / Space / pad A or Start. Short delay so button-mashing at the moment of death doesn't skip the screen.
		if Time.get_ticks_msec() - _over_msec > 800 and event.is_pressed() and not event.is_echo() and (event.is_action("ui_accept") or (event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START])):
			get_tree().reload_current_scene()
		return
	if _players.is_empty() and not _selecting and event.is_pressed() and not event.is_echo():
		var solo: bool = (event is InputEventKey and event.keycode == KEY_1) or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A)
		var coop: bool = (event is InputEventKey and event.keycode == KEY_2) or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_X)
		if not (solo or coop):
			return
		num_players = 1 if solo else 2
		_selecting = true
		_banner.modulate.a = 0.0
		var select := HeroSelect.new()
		add_child(select)
		select.open(num_players)
		_begin(await select.finished)

func _begin(heroes: Array) -> void:
	for i in num_players:
		var p := Player.new()
		p.player_index = i
		p.hero = heroes[i]
		add_child(p)
		_hud.add_player(p)
		_players.append(p)
	_index = start_room - 1
	_next_room()

func _process(_delta: float) -> void:
	if _over:
		return
	if not _players.is_empty() and _players.all(func(p: Player) -> bool: return p.down):
		_end("DEFEATED")

func _show(text: String, seconds := 2.0, hold := false) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	if not hold:
		create_tween().tween_property(_banner, "modulate:a", 0.0, 0.6).set_delay(seconds)

func _end(text: String) -> void:
	_over = true
	_over_msec = Time.get_ticks_msec()
	_show(text + "\n\nPress Enter / A to restart", 0.0, true)

func _next_room() -> void:
	_index += 1
	if is_instance_valid(_room):
		_room.queue_free()
	var def: Dictionary = ROOMS[_index]
	_room = Room.new()
	_room.size_tiles = def["size"]
	add_child(_room)
	for i in _players.size():
		var p := _players[i]
		p.position = Vector2(150, _room.center().y + (i - (_players.size() - 1) * 0.5) * 90.0)
		if p.down:
			p.revive(0.5)
	_cam.global_position = _room.center()
	_run_room(def)

func _run_room(def: Dictionary) -> void:
	_show(def.title)
	await get_tree().create_timer(1.8).timeout
	for wave: Array in def.waves:
		await _spawn_wave(wave)
		await _wait_clear()
		if _over:
			return
		await get_tree().create_timer(0.8).timeout
	if def.get("boss", false):
		await _spawn_wave(["boss"])
		await _wait_clear()
		if not _over:
			_end("VICTORY!")
		return
	_room_cleared()

func _wait_clear() -> void:
	while not _over and not get_tree().get_nodes_in_group("enemies").is_empty():
		await get_tree().create_timer(0.3).timeout

func _spawn_wave(kinds: Array) -> void:
	var inner := Rect2(Vector2.ZERO, _room.pixel_size()).grow(-Room.INSET - 60.0)
	var spawned: Array = []
	for k: String in kinds:
		var pos := inner.get_center()
		for attempt in 20:
			pos = Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
			if k == "boss":
				pos = Vector2(inner.end.x - 200.0, inner.get_center().y)
			if _players.all(func(p: Player) -> bool: return p.global_position.distance_to(pos) > 380.0):
				break
		SheetFrames.play_once(self, pos, "res://assets/tiny_swords/fx/Dust_02.png", 10, 14.0, 2.0 if k == "boss" else 1.2)
		spawned.append([k, pos])
	await get_tree().create_timer(0.7).timeout
	for s in spawned:
		var e := Enemy.new()
		e.kind = s[0]
		e.hp_mult = 1.0 + 0.6 * (num_players - 1)
		e.position = s[1]
		add_child(e)

func _room_cleared() -> void:
	for p in _players:
		if p.down:
			p.revive(0.5)
		p.heal(30)
	_show("Room cleared!  Head right  >>>", 2.5)
	var gate := Gate.new()
	gate.position = Vector2(_room.pixel_size().x - Room.INSET - 50.0, _room.center().y)
	gate.entered.connect(_next_room, CONNECT_ONE_SHOT | CONNECT_DEFERRED)  # deferred: rooms can't be built inside a physics callback
	_room.add_child(gate)

class Gate extends Area2D:
	signal entered
	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(70, 220)
		cs.shape = rs
		add_child(cs)
		body_entered.connect(func(_b: Node) -> void: entered.emit())
	func _draw() -> void:
		draw_rect(Rect2(-35, -110, 70, 220), Color(1, 0.85, 0.3, 0.28))
		draw_rect(Rect2(-35, -110, 70, 220), Color(1, 0.85, 0.3, 0.9), false, 3.0)
