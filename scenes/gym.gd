extends Node2D
## Gym arena: a small room for trying a hero before a match (starts on Net.my_hero).
## Three dummies: one facing you (front), one facing away (its back is yours: backstabs), one off to the side so line
## and area skills (Shadow Rush, Arrow Rain, Meteor) catch more than one. Dummies slide when knocked back and say when
## a stun or freeze lands. The side panel (GymPanel) swaps heroes and holds the tools and settings. Keys: Tab /
## Shift+Tab swap hero, R resets the dummies and cooldowns and fills the ult, Esc shows / hides the panel. A gamepad's
## Start goes back to the menu.
## Free spells (panel toggle): the skill is ready again after FREE_CD and the ult is always full. The basic keeps its pace.

const FREE_CD := 0.4   ## not 0: a button held for a few frames would cast once per frame
const DUMMY_SPOTS := [[Vector2(60, 0), Vector2.LEFT], [Vector2(260, -150), Vector2.RIGHT], [Vector2(230, 170), Vector2.UP]]

var _map: WorldMap
var _player: Player
var _hud: Hud
var _cam: GameCamera
var _dummies: Array[Dummy] = []
var _hero_i := 0
var _panel: GymPanel
var _free_spells := false

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
	var heroes := Hero.pickable()
	_hero_i = maxi(heroes.find(Hero.by_id(Net.my_hero)), 0)
	_spawn_hero(_map.spawn_point + Vector2(-260, 0))

	var ui := CanvasLayer.new()
	ui.layer = 10
	var hint := Label.new()
	hint.text = "WASD move   LMB basic   RMB skill   F / E ult   Space dash   Esc: panel"
	hint.modulate.a = 0.8
	hint.position = Vector2(GymPanel.WIDTH + 40.0, 12)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	ui.add_child(hint)
	_panel = GymPanel.new()
	_panel.hero_picked.connect(_swap_hero)
	_panel.free_spells.connect(func(on: bool) -> void: _free_spells = on)
	_panel.reset.connect(_reset)
	_panel.quit.connect(_quit)
	ui.add_child(_panel)
	add_child(ui)
	_panel.show_hero(_hero_i)

## A mouse button over the panel is a click on it, not an attack.
func _physics_process(_delta: float) -> void:
	_player.pointer_on_ui = _panel.get_global_rect().has_point(_panel.get_global_mouse_position())
	if _free_spells:
		_apply_free_spells()

func _apply_free_spells() -> void:
	for i in range(1, _player.cooldowns.size()):
		_player.cooldowns[i] = minf(_player.cooldowns[i], FREE_CD)
	_player.ult_charge = _player.hero.ult_cost

## (Re)builds the hero at `pos` with Hero.pickable()[_hero_i], and its HUD.
func _spawn_hero(pos: Vector2) -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_hud):
		_hud.queue_free()
	_player = Player.new()
	_player.hero = Hero.pickable()[_hero_i]
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

func _swap_hero(i: int) -> void:
	_hero_i = i
	_spawn_hero(_player.global_position)
	_panel.show_hero(i)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_panel.toggle()
		return
	var pad := event as InputEventJoypadButton
	if pad and pad.pressed and pad.button_index == JOY_BUTTON_START:   # the panel takes no focus: a gamepad's way out
		get_viewport().set_input_as_handled()
		_quit()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB:
			var n := Hero.pickable().size()
			_swap_hero((_hero_i + (n - 1 if key.shift_pressed else 1)) % n)
			get_viewport().set_input_as_handled()
		KEY_U:
			_player.ult_charge = _player.hero.ult_cost
			_player.float_text("ULT FILLED", Color(0.85, 0.5, 1.0), 20)
			get_viewport().set_input_as_handled()
		KEY_R:
			_reset()
			get_viewport().set_input_as_handled()

func _quit() -> void:
	get_tree().change_scene_to_file(Net.MENU_SCENE)

func _reset() -> void:
	for i in _dummies.size():
		_dummies[i].knock = Vector2.ZERO
		_dummies[i].position = _map.spawn_point + DUMMY_SPOTS[i][0]
		_dummies[i].aim_dir = DUMMY_SPOTS[i][1]
	for i in _player.cooldowns.size():
		_player.cooldowns[i] = 0.0
	_player.dash_charges = Player.MAX_DASH
	_player.ult_charge = _player.hero.ult_cost
	_player.heal(_player.max_hp)
	_player.float_text("RESET", Color(0.8, 0.9, 1.0), 20)
