extends Control
## Main menu (the main scene). Gym Arena | Online Match -> Host a match | Join a lobby (list + lobby ID box).
## Once a session exists (roster not empty) the screen is the waiting room instead: lobby ID, players, Start (host).

enum Screen { MAIN, ONLINE, JOIN }

var _screen := Screen.MAIN
var _box: VBoxContainer       ## centre column, rebuilt by _refresh()
var _corner: Control          ## bottom-right (Start match), rebuilt by _refresh()
var _status: Label
var _id_edit: LineEdit
var _lobbies: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(460, 0)
	_box.add_theme_constant_override("separation", 10)
	center.add_child(_box)
	Net.status.connect(func(t: String) -> void:
		if _status:
			_status.text = t)
	Net.roster_changed.connect(_refresh)
	Net.lobby_list.connect(func(l: Array) -> void:
		_lobbies = l
		if _screen == Screen.JOIN and Net.roster.is_empty():
			_refresh())
	_refresh()

func _label(text: String, size := 18, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = color
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, action: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(action)
	return b

func _go(screen: Screen) -> void:
	_screen = screen
	if screen == Screen.JOIN:
		Net.refresh_lobbies()
	_refresh()

func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()
	if _corner:
		_corner.queue_free()
		_corner = null
	_box.add_child(_label("CHITA ARENA", 44, Color(1, 0.85, 0.3)))
	_status = _label(Net.last_status, 16, Color(0.7, 0.85, 1.0))
	if not Net.roster.is_empty():
		_room()
		return
	match _screen:
		Screen.MAIN:
			_main()
		Screen.ONLINE:
			_online()
		Screen.JOIN:
			_join()

func _main() -> void:
	_box.add_child(_button("Gym Arena", func() -> void: get_tree().change_scene_to_file(Net.HERO_SCENE)))
	_box.add_child(_button("Online Match", func() -> void: _go(Screen.ONLINE)))
	_box.add_child(_status)

func _online() -> void:
	var ok := Net.available()
	_box.add_child(_button("Host a match", Net.host, not ok))
	_box.add_child(_button("Join a lobby", func() -> void: _go(Screen.JOIN), not ok))
	_box.add_child(_button("Back", func() -> void: _go(Screen.MAIN)))
	if not ok:
		_box.add_child(_label("Steam is not running. Start Steam and relaunch the game.", 15, Color(1, 0.5, 0.4)))
	_box.add_child(_status)

func _join() -> void:
	_box.add_child(_label("Open lobbies", 20))
	if _lobbies.is_empty():
		_box.add_child(_label("No open matches found", 14, Color(1, 1, 1, 0.5)))
	for l: Dictionary in _lobbies:
		_box.add_child(_button("%s   (%d/%d)" % [l.name, l.members, Net.MAX_PLAYERS], Net.join.bind(l.id)))
	_box.add_child(_button("Refresh", Net.refresh_lobbies))
	var row := HBoxContainer.new()
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "Lobby ID"
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_edit.text_submitted.connect(func(t: String) -> void: Net.join_by_id(t))
	row.add_child(_id_edit)
	row.add_child(_button("Join", func() -> void: Net.join_by_id(_id_edit.text)))
	_box.add_child(row)
	_box.add_child(_status)
	_box.add_child(_button("Back", func() -> void: _go(Screen.ONLINE)))

func _room() -> void:
	var host := multiplayer.is_server()
	_box.add_child(_label("LOBBY", 22))
	if Net.lobby_id != 0:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(_label("Lobby ID: %d" % Net.lobby_id, 16, Color(0.7, 0.85, 1.0)))
		row.add_child(_button("Copy", func() -> void: DisplayServer.clipboard_set(str(Net.lobby_id))))
		_box.add_child(row)
	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	for id: int in ids:
		var r: Dictionary = Net.roster[id]
		_box.add_child(_label("%s%s" % [r.name, "   (host)" if id == 1 else ""], 22, Player.NAME_COLORS[r.slot % Player.NAME_COLORS.size()]))
	_box.add_child(_label("%d / %d players" % [Net.roster.size(), Net.MAX_PLAYERS], 14, Color(1, 1, 1, 0.6)))
	_box.add_child(_status)
	if not host:
		_box.add_child(_label("Waiting for the host to start...", 16))
	if not Net.dev_enet:
		_box.add_child(_button("Invite friends", Net.invite_friends))
	_box.add_child(_button("Leave", Net.leave))
	if host:
		_corner = MarginContainer.new()
		_corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_corner.add_theme_constant_override("margin_right", 24)
		_corner.add_theme_constant_override("margin_bottom", 24)
		var start := _button("Start match", Net.start_match, Net.roster.size() < Net.MIN_PLAYERS)
		start.custom_minimum_size = Vector2(200, 54)
		start.tooltip_text = "Needs at least %d players" % Net.MIN_PLAYERS
		_corner.add_child(start)
		add_child(_corner)
