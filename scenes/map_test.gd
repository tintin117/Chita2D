extends Node2D
## Playground for WorldMap: one hero, enemy camps by tier, roamers. F2 = new map, F3 = overview. Doesn't touch Game.

const CAMP_KINDS := {
	1: ["grunt", "grunt", "grunt"],
	2: ["grunt", "grunt", "archer", "archer", "grunt"],
	3: ["grunt", "archer", "archer", "lancer", "lancer", "grunt"],
}
const ROAMERS := 8
const WAKE_RANGE := 650.0   ## ponytail: stand-in for aggro; enemies sleep until a player is near, never go back to sleep

@export var hero_id := "wizard"

var _map: WorldMap
var _player: Player
var _cam: GameCamera
var _disc: MapDiscovery
var _tension: Tension
var _sleepers: Array[Enemy] = []

func _ready() -> void:
	var seed_value: int = Engine.get_meta("map_seed") if Engine.has_meta("map_seed") else randi()
	Engine.remove_meta("map_seed")
	print("map seed: ", seed_value)
	_map = WorldMap.new()
	add_child(_map)
	_map.generate(seed_value)

	var hud := Hud.new()
	add_child(hud)
	_cam = GameCamera.new()
	_cam.limit_left = int(_map.bounds.position.x)
	_cam.limit_top = int(_map.bounds.position.y)
	_cam.limit_right = int(_map.bounds.end.x)
	_cam.limit_bottom = int(_map.bounds.end.y)
	add_child(_cam)
	_cam.global_position = _map.spawn_point

	_player = Player.new()
	_player.hero = Hero.by_id(hero_id)
	_player.position = _map.spawn_point
	_map.add_child(_player)
	hud.add_player(_player)

	_disc = MapDiscovery.new()
	add_child(_disc)
	_disc.setup()
	var minimap := Minimap.new()
	add_child(minimap)
	minimap.setup(_map, _disc)
	_tension = Tension.new()
	add_child(_tension)
	_tension.level_reached.connect(func(lv: int) -> void: SlotMachine.request(get_tree(), lv))
	var tension_hud := TensionHud.new()
	add_child(tension_hud)
	tension_hud.setup(_tension)
	var hint := Label.new()
	hint.text = "F2 new map   F3 overview   F4 +20 XP   F5 hurt hero   F6 next tension level"
	hint.modulate.a = 0.6
	hint.position = Vector2(12, 8)
	var hint_layer := CanvasLayer.new()
	hint_layer.add_child(hint)
	add_child(hint_layer)

	for camp: Dictionary in _map.camps:
		var kinds: Array = CAMP_KINDS[camp.tier]
		for k: String in kinds:
			_spawn(k, camp.pos + Vector2.from_angle(randf() * TAU) * randf_range(30.0, camp.radius * 0.8))
	for i in ROAMERS:
		_spawn("grunt", _map.random_open_point(_map.spawn_point, 900.0))

func _spawn(kind: String, pos: Vector2) -> void:
	var e := Enemy.new()
	e.kind = kind
	e.position = pos
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e.died.connect(_on_enemy_died)
	_map.add_child(e)
	_sleepers.append(e)

func _on_enemy_died(e: Enemy) -> void:
	var xp := Progression.xp_for(e.kind)
	_player.prog.add_xp(xp)
	_player.float_text("+%d XP" % xp, Color(0.55, 0.8, 1.0))

func _process(_delta: float) -> void:
	for e in _sleepers.duplicate():
		if not is_instance_valid(e):
			_sleepers.erase(e)
		elif _player.global_position.distance_to(e.global_position) < WAKE_RANGE:
			e.process_mode = Node.PROCESS_MODE_INHERIT
			_sleepers.erase(e)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F2:   # not R: that's the signature skill
		Engine.set_meta("map_seed", randi())
		get_tree().reload_current_scene()
	elif event.keycode == KEY_F4:   # debug
		_player.prog.add_xp(20)
	elif event.keycode == KEY_F6:   # debug
		_tension.skip_level()
	elif event.keycode == KEY_F5:   # debug
		_player.take_damage(30, _player.global_position + Vector2(100, 0))
	elif event.keycode == KEY_F3:   # whole-map overview
		var overview := _cam.is_processing()
		_cam.set_process(not overview)
		var far := 100000 if overview else 0
		_cam.limit_left = int(_map.bounds.position.x) - far
		_cam.limit_top = int(_map.bounds.position.y) - far
		_cam.limit_right = int(_map.bounds.end.x) + far
		_cam.limit_bottom = int(_map.bounds.end.y) + far
		if overview:
			_cam.zoom = Vector2.ONE * 0.19
			_cam.global_position = _map.bounds.get_center()
