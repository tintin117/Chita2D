extends Control
## Gym and online hero selection. The host starts the battle when everyone is ready or time runs out.

const PICK_TIME := 30.0
const ROLE := {"knight": "Bruiser", "rogue": "Assassin", "wizard": "Zoner", "ranger": "Marksman"}

var _online := false
var _time_left := PICK_TIME
var _ready_btn: Button
var _timer_label: Label
var _status: Label
var _roster: GridContainer
var _hero_buttons: Array[Button] = []
var _name_label: Label
var _role_label: Label
var _description: Label
var _signature: Label
var _stats: Label

func _ready() -> void:
	_online = not Net.roster.is_empty()
	theme = ArenaUi.THEME
	ArenaUi.backdrop(self, 0.76)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 866
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var header := HBoxContainer.new()
	var title := ArenaUi.heading("Choose Your Hero", 38)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if _online:
		_timer_label = ArenaUi.label("", 20, ArenaUi.GOLD)
		header.add_child(_timer_label)
	box.add_child(header)

	var cards := HBoxContainer.new()
	box.add_child(cards)
	var group := ButtonGroup.new()
	var selected := Hero.by_id(Net.my_hero)
	var initial: Button
	for hero in Hero.all():
		var card := _card(hero, group, selected.id == hero.id)
		cards.add_child(card)
		if selected.id == hero.id:
			initial = card

	var details := PanelContainer.new()
	box.add_child(details)
	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", 4)
	details.add_child(data)
	var hero_header := HBoxContainer.new()
	_name_label = ArenaUi.heading("", 26)
	_role_label = ArenaUi.label("", 19, ArenaUi.MOSS)
	_stats = ArenaUi.label("", 18, ArenaUi.MUTED)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hero_header.add_child(_name_label)
	hero_header.add_child(_role_label)
	hero_header.add_child(_stats)
	data.add_child(hero_header)
	_description = ArenaUi.label("", 19)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data.add_child(_description)
	_signature = ArenaUi.label("", 18, ArenaUi.GOLD)
	_signature.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data.add_child(_signature)
	_show_hero(selected)

	if _online:
		_roster = GridContainer.new()
		_roster.columns = 4
		_roster.add_theme_constant_override("v_separation", 3)
		box.add_child(_roster)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(actions)
	if _online:
		_status = ArenaUi.label("", 16, ArenaUi.MUTED)
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(_status)
		actions.add_child(ArenaUi.button("Leave", Net.leave))
		_ready_btn = ArenaUi.button("Ready", _on_ready_toggled, true)
		_ready_btn.toggle_mode = true
		_ready_btn.custom_minimum_size.x = 152
		actions.add_child(_ready_btn)
		Net.roster_changed.connect(_refresh_status)
		_refresh_status()
		if Net.dev_enet or Net.solo_auto:
			_ready_btn.button_pressed = true
			_on_ready_toggled()
	else:
		actions.add_child(ArenaUi.button("Back", _go_back))
		var enter := ArenaUi.button("Enter Gym", func() -> void:
			get_tree().change_scene_to_file("res://scenes/gym.tscn"), true)
		enter.custom_minimum_size.x = 152
		actions.add_child(enter)
	if is_instance_valid(initial) and not initial.disabled:
		ArenaUi.defer_focus(initial)

func _card(hero: Hero, group: ButtonGroup, selected: bool) -> Button:
	var card := ArenaUi.button("", func() -> void:
		Net.set_hero(hero.id)
		_show_hero(hero))
	card.toggle_mode = true
	card.button_group = group
	card.button_pressed = selected
	card.tooltip_text = hero.display_name
	card.custom_minimum_size = Vector2(186, 188)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.text = hero.display_name
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.expand_icon = true
	card.add_theme_constant_override("icon_max_width", 138)
	card.add_theme_font_size_override("font_size", 22)
	card.icon = ArenaUi.portrait(hero.id)
	_hero_buttons.append(card)
	return card

func _show_hero(hero: Hero) -> void:
	_name_label.text = hero.display_name
	_role_label.text = ROLE[hero.id]
	_description.text = hero.description.trim_prefix(ROLE[hero.id] + ". ")
	_stats.text = "%d HP   /   %d SPEED   /   %d RANGE" % [hero.max_hp, hero.speed, hero.attack_range]
	_signature.text = "%s  /  %s" % [Hero.make_skill(hero.rmb_skill).display_name, hero.rmb_text]

func _go_back() -> void:
	if _online:
		Net.leave()
	else:
		get_tree().change_scene_to_file(Net.MENU_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()

func _on_ready_toggled() -> void:
	Net.set_ready(_ready_btn.button_pressed)
	_ready_btn.text = "Unready" if _ready_btn.button_pressed else "Ready"
	for card in _hero_buttons:
		card.disabled = _ready_btn.button_pressed

func _refresh_status() -> void:
	for child in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	var ready := 0
	for id: int in ids:
		var member: Dictionary = Net.roster[id]
		if member.ready:
			ready += 1
		var player := ArenaUi.label("%s / %s" % [member.name, Hero.by_id(member.hero).display_name], 16, ArenaUi.MOSS if member.ready else ArenaUi.MUTED)
		player.custom_minimum_size.x = 195
		player.size_flags_horizontal = SIZE_EXPAND_FILL
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_roster.add_child(player)
	_status.text = "%d of %d players ready" % [ready, Net.roster.size()]

func _process(delta: float) -> void:
	if not _online:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_timer_label.text = "Battle starts in %d s" % ceili(_time_left)
	if multiplayer.is_server() and (Net.all_ready() or _time_left <= 0.0):
		Net.enter_arena()
