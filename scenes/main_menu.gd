extends Control
## Main menu (the main scene). Gym Arena | Online Match -> Host a match | Join a lobby (list + lobby ID box).
## Once a session exists (roster not empty) the screen is the waiting room instead: lobby ID, players, Start (host).

enum Screen { MAIN, ONLINE, JOIN, SOLO }
const DIFFICULTY := [["Easy", 0.3], ["Normal", 0.6], ["Hard", 0.9]]
var _difficulty := 1
const TEAM_COLORS := [Color(1, 0.4, 0.35), Color(0.4, 0.65, 1.0)]
const TIME_OPTIONS := [[180, "3 min"], [300, "5 min"], [480, "8 min"], [0, "No limit"]]
const KILL_OPTIONS := [[10, "10"], [15, "15"], [25, "25"], [0, "No limit"]]

var _screen := Screen.MAIN
var _box: VBoxContainer
var _menu_frame: PanelContainer
var _settings: MatchOverlay
var _status: Label
var _id_edit: LineEdit
var _lobbies: Array = []

func _ready() -> void:
	theme = ArenaUi.THEME
	ArenaUi.backdrop(self)
	var region := MarginContainer.new()
	region.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	region.offset_right = 522
	region.add_theme_constant_override("margin_left", 78)
	region.add_theme_constant_override("margin_right", 22)
	region.add_theme_constant_override("margin_top", 28)
	region.add_theme_constant_override("margin_bottom", 28)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	region.add_child(scroll)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(center)
	_menu_frame = PanelContainer.new()
	center.add_child(_menu_frame)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	_menu_frame.add_child(_box)
	add_child(region)
	_settings = MatchOverlay.new()
	_settings.configure("Settings", Callable())
	add_child(_settings)
	_settings.visibility_changed.connect(func() -> void: region.visible = not _settings.visible)
	Net.status.connect(func(t: String) -> void:
		if _status:
			_status.text = t
			_status.visible = not t.is_empty())
	Net.roster_changed.connect(_refresh)
	Net.lobby_list.connect(func(l: Array) -> void:
		_lobbies = l
		if _screen == Screen.JOIN and Net.roster.is_empty():
			_refresh())
	_refresh()

func _label(text: String, size := 18, color := ArenaUi.INK) -> Label:
	var node := ArenaUi.label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func _button(text: String, action: Callable, disabled := false) -> Button:
	var node := ArenaUi.button(text, action)
	node.disabled = disabled
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var caption_width := ArenaUi.BODY.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	node.custom_minimum_size.x = clampf(ceilf(caption_width) + 28, 104, 176)
	return node

func _go_back() -> void:
	if not Net.roster.is_empty():
		Net.leave()
	elif _screen == Screen.JOIN:
		_go(Screen.ONLINE)
	else:
		_go(Screen.MAIN)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_screen != Screen.MAIN or not Net.roster.is_empty()):
		get_viewport().set_input_as_handled()
		_go_back()

func _go(screen: Screen) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	_screen = screen
	if screen == Screen.JOIN:
		Net.refresh_lobbies()
	_refresh()

func _refresh() -> void:
	var previous := ArenaUi.focusable(_box).find(get_viewport().gui_get_focus_owner())
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()

	_status = _label(Net.last_status, 16, ArenaUi.MUTED)
	if _screen == Screen.MAIN and Net.roster.is_empty():
		_menu_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		_menu_frame.remove_theme_stylebox_override("panel")
	if not Net.roster.is_empty():
		_room()
	else:
		match _screen:
			Screen.MAIN:
				_main()
			Screen.ONLINE:
				_online()
			Screen.JOIN:
				_join()
			Screen.SOLO:
				_solo()

	_box.add_child(_status)
	_status.visible = not _status.text.is_empty()
	var controls := ArenaUi.focusable(_box)
	if not controls.is_empty() and not _settings.visible:
		ArenaUi.defer_focus(controls[clampi(previous, 0, controls.size() - 1)])

func _main() -> void:
	var mark := ArenaUi.picture(ArenaUi.LOGO, Vector2(376, 128))
	mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mark.stretch_mode = TextureRect.STRETCH_KEEP
	_box.add_child(mark)
	var online := ArenaUi.button("Online Match", func() -> void: _go(Screen.ONLINE), true)
	var practice := _button("Practice vs Bots", func() -> void: _go(Screen.SOLO))
	var gym := _button("Gym Arena", func() -> void: get_tree().change_scene_to_file(Net.HERO_SCENE))
	for button: Button in [online, practice, gym]:
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 52
		button.add_theme_font_size_override("font_size", 24)
		_box.add_child(button)
	var settings := _button("Settings", _settings.open)
	settings.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_box.add_child(settings)

func _solo() -> void:
	_box.add_child(ArenaUi.heading("Practice vs Bots", 33))
	var mode := _button(GameMode.title(Net.mode), func() -> void: Net.set_mode(GameMode.next(Net.mode)))
	_box.add_child(_setting("Ruleset", mode))
	_box.add_child(_label(GameMode.cfg(Net.mode).blurb, 17, ArenaUi.MUTED))
	var skill := _button(DIFFICULTY[_difficulty][0], func() -> void:
		_difficulty = (_difficulty + 1) % DIFFICULTY.size()
		_refresh())
	_box.add_child(_setting("Bot skill", skill))
	_box.add_child(HSeparator.new())
	var choices := HBoxContainer.new()
	for n in [3, 7]:
		var start := ArenaUi.button("Fight %d bots" % n, func() -> void: Net.start_solo(n, DIFFICULTY[_difficulty][1]), n == 3)
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_child(start)
	_box.add_child(choices)
	var back := _button("Back", _go_back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_box.add_child(back)

func _setting(title: String, value: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(title, 18, ArenaUi.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	value.custom_minimum_size.x = 176
	row.add_child(value)
	return row

func _online() -> void:
	_box.add_child(ArenaUi.heading("Online Match", 33))
	var ok := Net.available()
	_box.add_child(_button("Host a match", Net.host, not ok))
	_box.add_child(_button("Join a lobby", func() -> void: _go(Screen.JOIN), not ok))
	_box.add_child(_button("Back", _go_back))
	if not ok:
		_box.add_child(_label("Start Steam and relaunch Chita to play online.", 16, Color("#efab88")))

func _join() -> void:
	_box.add_child(ArenaUi.heading("Open Lobbies", 33))
	if _lobbies.is_empty():
		_box.add_child(_label("No open matches found", 14, ArenaUi.MUTED))
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
	_box.add_child(_button("Back", _go_back))

func _room() -> void:
	var host := multiplayer.is_server()
	var header := HBoxContainer.new()
	var title := ArenaUi.heading("Match Lobby", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var count := ArenaUi.label("%d / %d" % [Net.roster.size(), Net.MAX_PLAYERS], 19, ArenaUi.MOSS)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(count)
	_box.add_child(header)
	if Net.lobby_id != 0:
		_box.add_child(_setting("Lobby %d" % Net.lobby_id, _button("Copy ID", func() -> void:
			DisplayServer.clipboard_set(str(Net.lobby_id)))))
	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	if Net.is_team_mode():
		for t in 2:
			_box.add_child(_label("%s team" % Net.TEAM_NAMES[t], 18, TEAM_COLORS[t]))
			for id: int in ids:
				if int(Net.roster[id].get("team", 0)) == t:
					_player_row(id, host)
	else:
		for id: int in ids:
			_player_row(id, false)
	_box.add_child(HSeparator.new())
	_settings_rows(host)
	_box.add_child(_label(GameMode.cfg(Net.mode).blurb, 16, ArenaUi.MUTED))
	if not host:
		_box.add_child(_label("Waiting for the host", 17))
	var actions := HBoxContainer.new()
	actions.add_child(_button("Leave", Net.leave))
	if not Net.dev_enet:
		actions.add_child(_button("Invite friends", Net.invite_friends))
	if host:
		var start := ArenaUi.button("Start match", Net.start_match, true)
		start.disabled = Net.roster.size() < Net.MIN_PLAYERS
		start.tooltip_text = "Needs at least %d players" % Net.MIN_PLAYERS
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(start)
	_box.add_child(actions)

## Host-editable match rules (cycle buttons); everyone else sees them read-only.
func _settings_rows(host: bool) -> void:
	var st: Dictionary = Net.settings
	var mode := "Team Deathmatch" if Net.is_team_mode() else "Free-for-all"
	var lines := [
		["Ruleset", GameMode.title(Net.mode), func() -> void: Net.set_mode(GameMode.next(Net.mode))],
		["Teams", mode, func() -> void: Net.set_setting("mode", "ffa" if Net.is_team_mode() else "tdm")],
		["Time limit", _opt_name(TIME_OPTIONS, st.time_limit), func() -> void: Net.set_setting("time_limit", _opt_next(TIME_OPTIONS, st.time_limit))],
		["Kill limit", _opt_name(KILL_OPTIONS, st.kill_limit), func() -> void: Net.set_setting("kill_limit", _opt_next(KILL_OPTIONS, st.kill_limit))],
	]
	if Net.is_team_mode():
		lines.append(["Friendly fire", "On" if st.friendly_fire else "Off", func() -> void: Net.set_setting("friendly_fire", not st.friendly_fire)])
	for line in lines:
		var value: Control = _button(line[1], line[2]) if host else _label(line[1], 17)
		_box.add_child(_setting(line[0], value))

func _opt_name(opts: Array, value: int) -> String:
	for o in opts:
		if o[0] == value:
			return o[1]
	return str(value)

func _opt_next(opts: Array, value: int) -> int:
	for i in opts.size():
		if opts[i][0] == value:
			return opts[(i + 1) % opts.size()][0]
	return opts[0][0]

func _player_row(id: int, host: bool) -> void:
	var r: Dictionary = Net.roster[id]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var color: Color = TEAM_COLORS[int(r.get("team", 0))] if Net.is_team_mode() else Player.NAME_COLORS[r.slot % Player.NAME_COLORS.size()]
	var team: int = r.get("team", 0)
	var sprite_color: String = Player.TEAM_SPRITES[team] if Net.is_team_mode() else Player.COLORS[r.slot % Player.COLORS.size()]
	row.add_child(ArenaUi.picture(ArenaUi.portrait(Hero.by_id(r.hero), sprite_color), Vector2(36, 36)))
	var name_label := _label(r.name, 18, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	if id == 1:
		var badge := ArenaUi.label("Host", 15, ArenaUi.MUTED)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
	if Net.is_team_mode() and (host or id == multiplayer.get_unique_id()):
		row.add_child(_button("Switch team", Net.switch_team.bind(id)))
	_box.add_child(row)
