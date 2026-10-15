extends Node2D
## Gym arena: a small room with a training dummy in the middle, for trying the picked hero (Net.my_hero) before a match.

var _map: WorldMap

func _ready() -> void:
	_map = WorldMap.new()
	add_child(_map)
	_map.generate_gym()

	var dummy := Dummy.new()
	dummy.position = _map.spawn_point
	_map.add_child(dummy)

	var player := Player.new()
	player.hero = Hero.by_id(Net.my_hero)
	player.display_name = Net.my_name
	player.position = _map.spawn_point + Vector2(-260, 0)
	_map.add_child(player)

	var cam := GameCamera.new()
	cam.target = player
	add_child(cam)
	cam.global_position = player.global_position
	var hud := Hud.new()
	hud.with_sheet = false
	hud.online = true
	add_child(hud)
	hud.add_player(player)

	var ui := CanvasLayer.new()
	var hint := Label.new()
	hint.text = "GYM   WASD move   LMB / RMB / Q / R skills   Space dash   Esc: back to menu"
	hint.modulate.a = 0.7
	hint.position = Vector2(12, 8)
	ui.add_child(hint)
	add_child(ui)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(Net.MENU_SCENE)
