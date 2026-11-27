extends Control
## Main menu (the main scene). Gym Arena | Practice vs Bots | Online Match -> Host a match | Join a lobby (list + lobby ID box).
## Once a session exists (roster not empty) the screen is the waiting room instead: lobby ID, players, rules, Start (host).
## The left column holds the menu; behind it MenuBackdrop shows the picked arena, live.

enum Screen { MAIN, ONLINE, JOIN, SOLO }
const DIFFICULTY := [["Easy", 0.3], ["Normal", 0.6], ["Hard", 0.9]]
var _difficulty := 1
const BOT_COUNTS := [3, 7]
var _bot_count := 0
const TEAM_COLORS := [Color(1, 0.4, 0.35), Color(0.4, 0.65, 1.0)]
const TIME_OPTIONS := [[180, "3 min"], [300, "5 min"], [480, "8 min"], [0, "No limit"]]
const KILL_OPTIONS := [[10, "10"], [15, "15"], [25, "25"], [0, "No limit"]]
const TAGLINE := "Knock them into the water."

const MARGIN_LEFT := 64
const COLUMN := 480        ## width of the menu column, left margin included
const LOBBY_COLUMN := 960
const ENTER_TIME := 0.18

var _screen := Screen.MAIN
var _region: MarginContainer
var _box: VBoxContainer
var _menu_frame: PanelContainer
var _backdrop: MenuBackdrop
var _footer: Control
var _showing: Label
var _settings: MatchOverlay
var _status: Label
var _id_edit: LineEdit
var _lobbies: Array = []
var _shown := ""           ## the screen drawn last: a change slides the column in, a value change does not

func _ready() -> void:
	theme = ArenaUi.THEME
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_add_background()
	_region = MarginContainer.new()
	_region.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_region.add_theme_constant_override("margin_left", MARGIN_LEFT)
	_region.add_theme_constant_override("margin_right", 16)
	_region.add_theme_constant_override("margin_top", 16)
	_region.add_theme_constant_override("margin_bottom", 48)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_region.add_child(scroll)
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
	add_child(_region)
	_add_footer()
	_settings = MatchOverlay.new()
	_settings.configure("Settings", Callable())
	add_child(_settings)
	_settings.visibility_changed.connect(func() -> void:
		_region.visible = not _settings.visible
		_footer.visible = not _settings.visible)
	Net.status.connect(func(t: String) -> void:
		if _status:
			_status.text = t
			_status.visible = not t.is_empty())
	Net.roster_changed.connect(_refresh)
	Net.lobby_list.connect(func(l: Array) -> void:
		_lobbies = l
		if _screen == Screen.JOIN and Net.roster.is_empty():
			_refresh())
	resized.connect(_layout_backdrop)
	_refresh()

func _add_background() -> void:
	var night := ColorRect.new()
	night.color = ArenaUi.NIGHT
	night.z_index = -100   # the level's ground layers use negative z: they must still draw over this
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(night)
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	# dark behind the menu column, clear over the arena
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 0.55])
	fade.colors = PackedColorArray([Color(ArenaUi.NIGHT, 0.97), Color(ArenaUi.NIGHT, 0.86), Color(ArenaUi.NIGHT, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = fade
	var shade := TextureRect.new()
	shade.texture = tex
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

## Bottom strip: how to drive the menu, and which arena is behind it.
func _add_footer() -> void:
	var bar := PanelContainer.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color(ArenaUi.NIGHT, 0.85)
	back.content_margin_left = MARGIN_LEFT
	back.content_margin_right = 24
	back.content_margin_top = 6
	back.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", back)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	bar.add_child(row)
	var hints := ArenaUi.label("Arrows: select      Enter: confirm      Esc: back", 15, ArenaUi.MUTED)
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hints)
	_showing = ArenaUi.label("", 15, ArenaUi.GOLD)
	row.add_child(_showing)
	_footer = bar
	add_child(bar)

## The arena sits in what the menu column leaves free. A wide column (the lobby) tucks it partly behind the panel
## instead of shrinking it until the edge of the water shows.
func _layout_backdrop() -> void:
	var wide := maxf(size.x - _region.offset_right - 56.0, 640.0)
	_backdrop.frame = Rect2(size.x - 32.0 - wide, 56, wide, size.y - 130.0)

func _label(text: String, size_px := 18, color := ArenaUi.INK) -> Label:
	var node := ArenaUi.label(text, size_px, color)
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
	if ArenaUi.back_pressed(event) and (_screen != Screen.MAIN or not Net.roster.is_empty()):
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

func _pick_arena(index: int) -> void:
	Net.set_arena(index)   # emits roster_changed, which redraws this screen and the backdrop

func _refresh() -> void:
	var previous := ArenaUi.focusable(_box).find(get_viewport().gui_get_focus_owner())
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()

	var in_room := not Net.roster.is_empty()
	var screen := "room" if in_room else str(_screen)
	_status = _label(Net.last_status, 16, ArenaUi.MUTED)
	if _screen == Screen.MAIN and not in_room:
		_menu_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		_menu_frame.remove_theme_stylebox_override("panel")
	_region.offset_right = LOBBY_COLUMN if in_room else COLUMN
	if in_room:
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
	_layout_backdrop()
	_backdrop.show_arena(Net.arena)
	_showing.text = "Arena: %s" % Arenas.info(Net.arena).name
	if screen != _shown:
		_shown = screen
		previous = 0
		_enter()
	var controls := ArenaUi.focusable(_box)
	if not controls.is_empty() and not _settings.visible:
		ArenaUi.defer_focus(controls[clampi(previous, 0, controls.size() - 1)])

## A new screen eases in from the left.
func _enter() -> void:
	var right := _region.offset_right
	_region.modulate.a = 0.0
	_region.offset_left = -24.0
	_region.offset_right = right - 24.0
	var t := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_region, "modulate:a", 1.0, ENTER_TIME)
	t.tween_property(_region, "offset_left", 0.0, ENTER_TIME)
	t.tween_property(_region, "offset_right", right, ENTER_TIME)

func _main() -> void:
	var mark := ArenaUi.picture(ArenaUi.LOGO, Vector2(376, 128))
	mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mark.stretch_mode = TextureRect.STRETCH_KEEP
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", -32)   # the art's own padding: line the C up with the text under it
	inset.add_child(mark)
	_box.add_child(inset)
	_box.add_child(_label(TAGLINE, 20, ArenaUi.GOLD))
	_box.add_child(_gap(14))
	var online_hint := "Host or join a lobby with friends" if Net.available() else "Needs Steam running"
	_box.add_child(_item("Online Match", online_hint, func() -> void: _go(Screen.ONLINE)))
	_box.add_child(_item("Practice vs Bots", "Any arena, any ruleset, on your own", func() -> void: _go(Screen.SOLO)))
	_box.add_child(_item("Gym Arena", "Try every hero on training dummies",
		func() -> void: get_tree().change_scene_to_file(Net.HERO_SCENE)))
	_box.add_child(_gap(6))
	_box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	for item: Button in [_item("Settings", "", _settings.open), _item("Exit", "", get_tree().quit)]:
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item)
	_box.add_child(row)

func _gap(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size.y = height
	return node

## A main-menu entry: a title, an optional line under it, and a gold bar with a small slide on the one in focus.
func _item(title: String, hint: String, action: Callable) -> Button:
	var node := ArenaUi.button("", action)
	node.custom_minimum_size.y = 62 if hint != "" else 44
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(ArenaUi.SLATE, 0.35)
	idle.border_width_left = 4
	idle.border_color = ArenaUi.EDGE
	var lit := idle.duplicate() as StyleBoxFlat
	lit.bg_color = Color(ArenaUi.SLATE, 0.95)
	lit.border_width_left = 8
	lit.border_color = ArenaUi.GOLD
	node.add_theme_stylebox_override("normal", idle)
	node.add_theme_stylebox_override("hover", idle)
	node.add_theme_stylebox_override("pressed", lit)
	node.add_theme_stylebox_override("focus", lit)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", -2)
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 22
	var head := ArenaUi.heading(title, 26 if hint != "" else 20)
	text.add_child(head)
	if hint != "":
		text.add_child(ArenaUi.label(hint, 15, ArenaUi.MUTED))
	node.add_child(text)
	var slide := func(x: float, tint: Color) -> void:
		head.add_theme_color_override("font_color", tint)
		node.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).tween_property(text, "offset_left", x, 0.12)
	node.focus_entered.connect(slide.bind(32.0, ArenaUi.MOSS))
	node.focus_exited.connect(slide.bind(22.0, ArenaUi.INK))
	node.mouse_entered.connect(node.grab_focus)   # one highlight: the mouse moves the same focus the keys do
	return node

func _caption(text: String) -> Label:
	return ArenaUi.label(text, 15, ArenaUi.GOLD)

## A fixed two-line slot, so changing a value does not make the panel jump.
func _blurb(text: String) -> Label:
	var node := _label(text, 16, ArenaUi.MUTED)
	node.custom_minimum_size.y = 40
	return node

func _arena_stepper() -> Stepper:
	return Stepper.new(Arenas.info(Net.arena).name, func(d: int) -> void: _pick_arena(Net.arena + d))

func _mode_stepper() -> Stepper:
	return Stepper.new(GameMode.title(Net.mode), func(d: int) -> void:
		Net.set_mode(GameMode.MODES[posmod(GameMode.MODES.find(Net.mode) + d, GameMode.MODES.size())]))

func _solo() -> void:
	_box.add_child(ArenaUi.heading("Practice vs Bots", 33))
	_box.add_child(_caption("ARENA  %d / %d" % [Net.arena + 1, Arenas.LIST.size()]))
	_box.add_child(_arena_stepper())
	_box.add_child(_blurb(Arenas.info(Net.arena).blurb))
	_box.add_child(_caption("RULESET"))
	_box.add_child(_mode_stepper())
	_box.add_child(_blurb(GameMode.cfg(Net.mode).blurb))
	var skill := Stepper.new(DIFFICULTY[_difficulty][0], func(d: int) -> void:
		_difficulty = posmod(_difficulty + d, DIFFICULTY.size())
		_refresh())
	_box.add_child(_setting("Bot skill", skill))
	var count := Stepper.new(str(BOT_COUNTS[_bot_count]), func(d: int) -> void:
		_bot_count = posmod(_bot_count + d, BOT_COUNTS.size())
		_refresh())
	_box.add_child(_setting("Bots", count))
	_box.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_child(_button("Back", _go_back))
	var play := ArenaUi.button("Play", func() -> void: Net.start_solo(BOT_COUNTS[_bot_count], DIFFICULTY[_difficulty][1]), true)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.custom_minimum_size.y = 52
	play.add_theme_font_size_override("font_size", 26)
	actions.add_child(play)
	_box.add_child(actions)

func _setting(title: String, value: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := ArenaUi.label(title, 18, ArenaUi.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	value.custom_minimum_size.x = 232
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

## The waiting room: players on the left, match rules on the right, the actions under both (always on screen).
func _room() -> void:
	var host := multiplayer.is_server()
	var header := HBoxContainer.new()
	var title := ArenaUi.heading("Match Lobby", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if Net.lobby_id != 0:
		var copy := _button("Copy ID", func() -> void: DisplayServer.clipboard_set(str(Net.lobby_id)))
		copy.tooltip_text = "Lobby %d" % Net.lobby_id
		header.add_child(copy)
	var count := ArenaUi.label("%d / %d" % [Net.roster.size(), Net.MAX_PLAYERS], 19, ArenaUi.MOSS)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(count)
	_box.add_child(header)
	_box.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	_box.add_child(columns)
	var players := VBoxContainer.new()
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players.add_theme_constant_override("separation", 4)
	columns.add_child(players)
	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	if Net.is_team_mode():
		for t in 2:
			players.add_child(_label("%s team" % Net.TEAM_NAMES[t], 18, TEAM_COLORS[t]))
			for id: int in ids:
				if int(Net.roster[id].get("team", 0)) == t:
					players.add_child(_player_row(id, host))
	else:
		players.add_child(_caption("PLAYERS"))
		for id: int in ids:
			players.add_child(_player_row(id, false))
	var rules := VBoxContainer.new()
	rules.custom_minimum_size.x = 420
	columns.add_child(rules)
	_settings_rows(rules, host)
	rules.add_child(_blurb(Arenas.info(Net.arena).blurb))
	rules.add_child(_blurb(GameMode.cfg(Net.mode).blurb))

	_box.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_child(_button("Leave", Net.leave))
	if not Net.dev_enet:
		actions.add_child(_button("Invite friends", Net.invite_friends))
	if host:
		var start := ArenaUi.button("Start match", Net.start_match, true)
		start.disabled = Net.roster.size() < Net.MIN_PLAYERS
		start.tooltip_text = "Needs at least %d players" % Net.MIN_PLAYERS
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start.custom_minimum_size.y = 48
		actions.add_child(start)
	else:
		var waiting := ArenaUi.label("Waiting for the host", 18, ArenaUi.MUTED)
		waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		actions.add_child(waiting)
	_box.add_child(actions)

## Host-editable match rules (steppers); everyone else sees them read-only.
func _settings_rows(into: VBoxContainer, host: bool) -> void:
	var st: Dictionary = Net.settings
	var teams := "Team Deathmatch" if Net.is_team_mode() else "Free-for-all"
	var lines := [
		["Arena", Arenas.info(Net.arena).name, func(d: int) -> void: _pick_arena(Net.arena + d)],
		["Ruleset", GameMode.title(Net.mode), func(d: int) -> void:
			Net.set_mode(GameMode.MODES[posmod(GameMode.MODES.find(Net.mode) + d, GameMode.MODES.size())])],
		["Teams", teams, func(_d: int) -> void: Net.set_setting("mode", "ffa" if Net.is_team_mode() else "tdm")],
		["Time limit", _opt_name(TIME_OPTIONS, st.time_limit), func(d: int) -> void:
			Net.set_setting("time_limit", _opt_step(TIME_OPTIONS, st.time_limit, d))],
		["Kill limit", _opt_name(KILL_OPTIONS, st.kill_limit), func(d: int) -> void:
			Net.set_setting("kill_limit", _opt_step(KILL_OPTIONS, st.kill_limit, d))],
	]
	if Net.is_team_mode():
		lines.append(["Friendly fire", "On" if st.friendly_fire else "Off",
			func(_d: int) -> void: Net.set_setting("friendly_fire", not st.friendly_fire)])
	for line in lines:
		var value: Control = Stepper.new(line[1], line[2]) if host else ArenaUi.label(line[1], 18)
		into.add_child(_setting(line[0], value))

func _opt_name(opts: Array, value: int) -> String:
	for o in opts:
		if o[0] == value:
			return o[1]
	return str(value)

## The option `d` places from `value` (wrapping); an unknown value starts over at the first.
func _opt_step(opts: Array, value: int, d: int) -> int:
	for i in opts.size():
		if opts[i][0] == value:
			return opts[posmod(i + d, opts.size())][0]
	return opts[0][0]

func _player_row(id: int, host: bool) -> HBoxContainer:
	var r: Dictionary = Net.roster[id]
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 38
	var color: Color = TEAM_COLORS[int(r.get("team", 0))] if Net.is_team_mode() else Player.NAME_COLORS[r.slot % Player.NAME_COLORS.size()]
	var team: int = r.get("team", 0)
	var sprite_color: String = Player.TEAM_SPRITES[team] if Net.is_team_mode() else Player.COLORS[r.slot % Player.COLORS.size()]
	row.add_child(ArenaUi.picture(ArenaUi.portrait(Hero.by_id(r.hero), sprite_color), Vector2(36, 36)))
	var name_label := ArenaUi.label(r.name, 18, color)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	if id == 1:
		var badge := ArenaUi.label("Host", 15, ArenaUi.MUTED)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
	if Net.is_team_mode() and (host or id == multiplayer.get_unique_id()):
		var swap := _button("Swap", Net.switch_team.bind(id))
		swap.custom_minimum_size.y = 34
		row.add_child(swap)
	return row

## A "< value >" button: Right / Enter / a click go forward; Left, or a click on the left arrow, go back.
class Stepper extends Button:
	var _step: Callable
	var _back := false

	func _init(value: String, step: Callable) -> void:
		text = value
		_step = step
		custom_minimum_size.y = 42
		clip_text = true
		for side in 2:
			var arrow := ArenaUi.label("<" if side == 0 else ">", 20, ArenaUi.GOLD)
			arrow.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE if side == 0 else Control.PRESET_RIGHT_WIDE)
			arrow.offset_left = 14.0 if side == 0 else -28.0
			arrow.offset_right = 28.0 if side == 0 else -14.0
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			add_child(arrow)
		pressed.connect(func() -> void: _step.call(-1 if _back else 1))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.pressed:
				_back = event.position.x < 48.0
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			accept_event()
			_step.call(-1 if event.is_action_pressed("ui_left") else 1)
		else:
			_back = false
