extends Control
## Gym and online hero selection. The host starts the battle when everyone is ready or time runs out.

const PICK_TIME := 30.0

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
var _stats: Label
var _tiles: Array[SkillTile] = []
var _skill_name: Label
var _skill_text: Label
var _hero: Hero
var _skill := 1            ## kit slot whose text is open; hovering a tile previews it without changing this
var _cards: GridContainer
var _card_group: ButtonGroup
var _card_color := "Blue"
var _konami := 0           ## how far into the Konami code the last presses got

const KONAMI_KEYS := [KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A]
const KONAMI_PAD := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT,
	JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_B, JOY_BUTTON_A]

const SEVEN_CODE := "67"   ## Six Seven
var _typed := ""           ## the last few characters typed here

## Secret codes on this screen, each unlocking a hero on this machine for good:
##  - the Konami code (arrows + B A, or the d-pad + B A): Pactknight
##  - typing "67": Six Seven
func _input(event: InputEvent) -> void:
	if ChatBox.typing:
		return
	if not PlaySettings.seven_unlocked and event is InputEventKey and event.pressed and not event.echo and event.unicode > 0:
		_typed = (_typed + char(event.unicode).to_lower()).right(SEVEN_CODE.length())
		if _typed == SEVEN_CODE:
			_typed = ""
			PlaySettings.seven_unlocked = true
			_unlock(Hero.six_seven())
			return
	if PlaySettings.pact_unlocked:
		return
	var code := -1   # this press, in the sequence's own terms; -1 = not a press we read
	var want: int
	if event is InputEventKey and event.pressed and not event.echo:
		code = event.keycode
		want = KONAMI_KEYS[_konami]
	elif event is InputEventJoypadButton and event.pressed:
		code = event.button_index
		want = KONAMI_PAD[_konami]
	if code == -1:
		return
	if code != want:
		var first: int = KONAMI_KEYS[0] if event is InputEventKey else KONAMI_PAD[0]
		_konami = 1 if code == first else 0
		return
	_konami += 1
	# the code's closing B A belong to the code: B would leave this screen, the last A would press the focused button
	if event is InputEventJoypadButton and (code == JOY_BUTTON_B or _konami == KONAMI_PAD.size()):
		get_viewport().set_input_as_handled()
	if _konami < KONAMI_KEYS.size():
		return
	_konami = 0
	PlaySettings.pact_unlocked = true
	_unlock(Hero.secret())

## A code went in: save it, add the hero's card (still two rows) and pick him.
func _unlock(hero: Hero) -> void:
	PlaySettings.save()
	Sfx.play("crown", Vector2.INF, 0.0, 0.8)
	var card := _card(hero, _card_color, _card_group, false)
	_cards.columns = ceili(Hero.pickable().size() / 2.0)   # 7 + 6 or 7 + 7: still two rows, nothing pushed off the screen
	_cards.add_child(card)
	card.button_pressed = true
	card.pressed.emit()   # picks him (Net.set_hero) and shows his card

func _ready() -> void:
	_online = not Net.roster.is_empty()
	theme = ArenaUi.THEME
	ArenaUi.backdrop(self, 0.92)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 904
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var header := HBoxContainer.new()
	var title := ArenaUi.heading("Choose a fighter", 44)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if _online:
		_timer_label = ArenaUi.label("", 20, ArenaUi.GOLD)
		header.add_child(_timer_label)
	box.add_child(header)

	var cards := GridContainer.new()   # always two rows: 6 + 6, or 7 + 6 once the secret hero is unlocked
	cards.columns = ceili(Hero.pickable().size() / 2.0)
	cards.add_theme_constant_override("h_separation", 6)
	cards.add_theme_constant_override("v_separation", 6)
	box.add_child(cards)
	_cards = cards
	var group := ButtonGroup.new()
	_card_group = group
	var selected := Hero.by_id(Net.my_hero)
	var color := Player.COLORS[0]
	if _online and Net.roster.has(Net.local_id()):
		var info: Dictionary = Net.roster[Net.local_id()]
		color = Player.TEAM_SPRITES[info.team] if Net.is_team_mode() else Player.COLORS[info.slot % Player.COLORS.size()]
	_card_color = color
	var initial: Button
	for hero in Hero.pickable():
		var card := _card(hero, color, group, selected.id == hero.id)
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
	_role_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats = ArenaUi.label("", 18, ArenaUi.MUTED)
	_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hero_header.add_child(_name_label)
	hero_header.add_child(_role_label)
	hero_header.add_child(_stats)
	data.add_child(hero_header)
	_description = ArenaUi.label("", 19)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data.add_child(_description)
	# The kit: one icon per slot, the open one's name and text beside the row. Hover previews, click keeps it open.
	var kit := HBoxContainer.new()
	kit.add_theme_constant_override("separation", 10)
	data.add_child(kit)
	var group_skill := ButtonGroup.new()
	for slot in ArenaUi.SKILL_SLOTS:
		var tile := SkillTile.new()
		tile.slot = slot
		tile.toggle_mode = true
		tile.button_group = group_skill
		tile.button_pressed = slot == _skill
		tile.focus_mode = Control.FOCUS_NONE
		tile.custom_minimum_size = Vector2(72, 82)
		tile.pressed.connect(func() -> void:
			_skill = slot
			_show_skill(slot))
		tile.mouse_entered.connect(_show_skill.bind(slot))
		tile.mouse_exited.connect(func() -> void: _show_skill(_skill))
		kit.add_child(tile)
		_tiles.append(tile)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	kit.add_child(words)
	_skill_name = ArenaUi.label("", 19, ArenaUi.GOLD)
	words.add_child(_skill_name)
	_skill_text = ArenaUi.label("", 17)
	_skill_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skill_text.custom_minimum_size.y = 60
	words.add_child(_skill_text)
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
	var chat := ChatBox.new()   # online only (ChatBox.online_only)
	chat.bottom_margin = 48.0
	add_child(chat)

func _card(hero: Hero, color: String, group: ButtonGroup, selected: bool) -> Button:
	var card := ArenaUi.button("", func() -> void:
		Net.set_hero(hero.id)
		_show_hero(hero))
	card.toggle_mode = true
	card.button_group = group
	card.button_pressed = selected
	card.tooltip_text = hero.display_name
	card.custom_minimum_size = Vector2(120, 112)   # 7 across still fits the 904 px column
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.text = hero.display_name
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.expand_icon = false
	card.add_theme_constant_override("icon_max_width", 76)
	if hero.base_id != "":
		card.modulate = hero.tint.lerp(Color.WHITE, 0.4)   # heroes 5-8 share sprite layouts with 1-4: the tint tells them apart
	card.add_theme_font_size_override("font_size", 17)
	card.icon = ArenaUi.portrait(hero, color)
	_hero_buttons.append(card)
	return card

func _show_hero(hero: Hero) -> void:
	_name_label.text = hero.display_name
	_role_label.text = hero.archetype
	_description.text = hero.description.trim_prefix(hero.archetype + ". ")
	_stats.text = "%d HP   /   %d SPEED   /   %d RANGE" % [hero.max_hp, hero.speed, hero.attack_range]
	_hero = hero
	for tile in _tiles:
		tile.hero = hero
		tile.queue_redraw()
	_show_skill(_skill)

func _show_skill(slot: int) -> void:
	var info := ArenaUi.skill_info(_hero, slot)
	_skill_name.text = "%s  /  %s" % [ArenaUi.skill_key(slot, 0), info[0]]
	_skill_name.add_theme_color_override("font_color", ArenaUi.skill_color(slot))
	_skill_text.text = info[1]

## One kit slot as a toggle button: the icon tile on top, its key under it. The theme draws the button frame,
## the tile is drawn over it.
class SkillTile extends Button:
	var slot := 0
	var hero: Hero

	func _draw() -> void:
		if hero == null:
			return
		var r := Rect2(Vector2(roundf(size.x / 2.0 - 24.0), 8.0), Vector2(48, 48))
		ArenaUi.draw_skill(self, hero, slot, r)
		if button_pressed:
			draw_rect(r, ArenaUi.skill_color(slot), false, 3.0)
		draw_string(ArenaUi.BODY, Vector2(0, size.y - 8.0), ArenaUi.skill_key(slot, 0), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13,
			ArenaUi.INK if button_pressed else ArenaUi.MUTED)

func _go_back() -> void:
	if _online:
		Net.leave()
	else:
		get_tree().change_scene_to_file(Net.MENU_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if ArenaUi.back_pressed(event) and not ChatBox.typing:
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
