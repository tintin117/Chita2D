extends Node2D
## Gym arena: a small room for trying a hero before a match (starts on Net.my_hero).
## Three dummies: one facing you (front), one facing away (its back is yours: backstabs), one off to the side so line
## and area skills (Shadow Rush, Arrow Rain, Meteor) catch more than one. Dummies slide when knocked back and say when
## a stun or freeze lands. Keys: Tab / Shift+Tab swap hero, U fills the ult, R resets the dummies and cooldowns,
## Esc opens the menu (playtest toggles, back to the main menu).

const DUMMY_SPOTS := [[Vector2(60, 0), Vector2.LEFT], [Vector2(260, -150), Vector2.RIGHT], [Vector2(230, 170), Vector2.UP]]

var _map: WorldMap
var _player: Player
var _hud: Hud
var _cam: GameCamera
var _dummies: Array[Dummy] = []
var _hero_i := 0
var _menu: MatchOverlay
var _hint: Label

func _ready() -> void:
	_map = WorldMap.new()
	add_child(_map)
	_map.generate_gym()

	for spot: Array in DUMMY_SPOTS:
		var d := Dummy.new()
		d.position = _map.spawn_point + spot[0]
		d.aim_dir = spot[1]
		_map.add_child(d)
		_dummies.append(d)

	_cam = GameCamera.new()
	add_child(_cam)
	var heroes := Hero.all()
	_hero_i = maxi(heroes.find(Hero.by_id(Net.my_hero)), 0)
	_spawn_hero(_map.spawn_point + Vector2(-260, 0))

	var ui := CanvasLayer.new()
	ui.layer = 10
	_hint = Label.new()
	_hint.modulate.a = 0.8
	_hint.position = Vector2(12, 8)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 4)
	ui.add_child(_hint)
	_menu = MatchOverlay.new()
	_menu.pause_tree = true
	_menu.configure("Gym", func() -> void: get_tree().change_scene_to_file(Net.MENU_SCENE))
	ui.add_child(_menu)
	add_child(ui)
	_update_hint()

## (Re)builds the hero at `pos` with Hero.all()[_hero_i], and its HUD.
func _spawn_hero(pos: Vector2) -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_hud):
		_hud.queue_free()
	_player = Player.new()
	_player.hero = Hero.all()[_hero_i]
	_player.display_name = Net.my_name
	_player.position = pos
	_map.add_child(_player)
	_cam.target = _player
	_cam.global_position = pos
	_hud = Hud.new()
	_hud.with_sheet = false
	_hud.online = true
	add_child(_hud)
	_hud.add_player(_player)

func _update_hint() -> void:
	_hint.text = "GYM  -  %s (%s)\nWASD move   LMB basic   RMB skill   F / E ult   Space dash\nTab / Shift+Tab: swap hero   U: fill ult   R: reset   Esc: menu (playtest toggles)" % [
		_player.hero.display_name, _player.hero.archetype]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_menu.open()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB:
			var n := Hero.all().size()
			_hero_i = (_hero_i + (n - 1 if key.shift_pressed else 1)) % n
			_spawn_hero(_player.global_position)
			_update_hint()
			get_viewport().set_input_as_handled()
		KEY_U:
			_player.ult_charge = _player.hero.ult_cost
			_player.float_text("ULT FILLED", Color(0.85, 0.5, 1.0), 20)
			get_viewport().set_input_as_handled()
		KEY_R:
			_reset()
			get_viewport().set_input_as_handled()

func _reset() -> void:
	for i in _dummies.size():
		_dummies[i].knock = Vector2.ZERO
		_dummies[i].position = _map.spawn_point + DUMMY_SPOTS[i][0]
		_dummies[i].aim_dir = DUMMY_SPOTS[i][1]
	for i in _player.cooldowns.size():
		_player.cooldowns[i] = 0.0
	_player.dash_charges = Player.MAX_DASH
	_player.heal(_player.max_hp)
	_player.float_text("RESET", Color(0.8, 0.9, 1.0), 20)
