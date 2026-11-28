extends Control
## Gym and online hero selection. The host starts the battle when everyone is ready or time runs out.

const PICK_TIME := 30.0

var _online := false
var _solo_match := false
var _has_roster := false
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
	var card := _card(hero, _card_group, false)
	_cards.columns = ceili(Hero.pickable().size() / 2.0)   # 7 + 6 or 7 + 7: still two rows, nothing pushed off the screen
	_cards.add_child(card)
	card.button_pressed = true
	card.pressed.emit()   # picks him (Net.set_hero) and shows his card

func _ready() -> void:
	_solo_match = Net.solo
	_online = not Net.roster.is_empty() and not _solo_match
	_has_roster = not Net.roster.is_empty()
	theme = ArenaUi.THEME
	ArenaUi.backdrop(self, 0.92)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 904
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	# the title pill in the middle; online, the countdown on the right with an equal blank on the left
	var header := HBoxContainer.new()
	var title := ArenaUi.title("Choose a fighter", 40, not _online)   # online needs the height for the roster
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if _online:
		var blank := Control.new()
		blank.custom_minimum_size.x = 220
		header.add_child(blank)
		header.move_child(blank, 0)
		_timer_label = ArenaUi.label("", 20, ArenaUi.SUN)
		_timer_label.custom_minimum_size.x = 220
		_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_timer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	var initial: Button
	for hero in Hero.pickable():
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
	_name_label = ArenaUi.heading("", 24)
	_role_label = ArenaUi.label("", 20, ArenaUi.MOSS)
	_role_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats = ArenaUi.label("", 18, ArenaUi.MUTED)
	_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hero_header.add_child(_name_label)
	hero_header.add_child(_role_label)
	hero_header.add_child(_stats)
	data.add_child(hero_header)
	_description = ArenaUi.label("", 18)
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
		tile.theme_type_variation = &"CardButton"
		tile.toggle_mode = true
		tile.button_group = group_skill
		tile.button_pressed = slot == _skill
		tile.focus_mode = Control.FOCUS_ALL
		tile.custom_minimum_size = Vector2(72, 82)
		tile.pressed.connect(_select_skill.bind(slot))
		tile.focus_entered.connect(_select_skill.bind(slot))
		tile.mouse_entered.connect(_show_skill.bind(slot))
		tile.mouse_exited.connect(func() -> void: _show_skill(_skill))
		kit.add_child(tile)
		_tiles.append(tile)
	for i in _tiles.size():
		_tiles[i].focus_neighbor_left = _tiles[i].get_path_to(_tiles[posmod(i - 1, _tiles.size())])
		_tiles[i].focus_neighbor_right = _tiles[i].get_path_to(_tiles[posmod(i + 1, _tiles.size())])
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	kit.add_child(words)
	_skill_name = ArenaUi.label("", 24, ArenaUi.SUN)
	words.add_child(_skill_name)
	_skill_text = ArenaUi.label("", 17)
	_skill_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_text.custom_minimum_size.y = 56
	words.add_child(_skill_text)
	words.add_child(ArenaUi.label("Browse skills with Q / E or LB / RB", 14, ArenaUi.MUTED))
	_show_hero(selected)

	if _has_roster:
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
	elif _solo_match:
		_status = ArenaUi.label("", 16, ArenaUi.MUTED)
		_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(_status)
		actions.add_child(ArenaUi.button("Back to menu", Net.leave))
		var start := ArenaUi.button("Start match", _start_solo_match, true)
		start.custom_minimum_size.x = 152
		actions.add_child(start)
	else:
		actions.add_child(ArenaUi.button("Back", _go_back))
		var enter := ArenaUi.button("Enter Gym", func() -> void:
			get_tree().change_scene_to_file("res://scenes/gym.tscn"), true)
		enter.custom_minimum_size.x = 152
		actions.add_child(enter)
	if _has_roster:
		Net.roster_changed.connect(_refresh_status)
		_refresh_status()
	if _online and (Net.dev_enet or Net.solo_auto):
		_ready_btn.button_pressed = true
		_on_ready_toggled()
	elif _solo_match and Net.solo_auto:
		call_deferred("_start_solo_match")
	if is_instance_valid(initial) and not initial.disabled:
		ArenaUi.defer_focus(initial)
	var chat := ChatBox.new()   # online only (ChatBox.online_only)
	chat.bottom_margin = 48.0
	add_child(chat)

func _card(hero: Hero, group: ButtonGroup, selected: bool) -> Button:
	var card := FighterCard.new()
	card.pressed.connect(func() -> void:
		Net.set_hero(hero.id)
		_show_hero(hero))
	card.hero_name = hero.display_name
	card.portrait = ArenaUi.selection_portrait(hero)
	card.theme_type_variation = &"CardButton"
	card.toggle_mode = true
	card.button_group = group
	card.button_pressed = selected
	card.accessibility_name = hero.display_name
	card.tooltip_text = hero.display_name
	card.custom_minimum_size = Vector2(120, 124)   # 7 across still fits the 904 px column
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_skill_name.text = info[0]
	_skill_name.add_theme_color_override("font_color", ArenaUi.skill_color(slot))
	_skill_text.text = info[1]

func _select_skill(slot: int) -> void:
	_skill = slot
	for tile in _tiles:
		tile.button_pressed = tile.slot == slot
	_show_skill(slot)

func _step_skill(direction: int) -> void:
	_select_skill(posmod(_skill + direction, ArenaUi.SKILL_SLOTS))

class FighterCard extends Button:
	var hero_name := ""
	var portrait: Texture2D

	func _draw() -> void:
		const INSET := 7.0
		const NAME_HEIGHT := 25.0
		var art := Rect2(INSET, INSET, size.x - INSET * 2.0, size.y - INSET * 2.0 - NAME_HEIGHT)
		var name_strip := Rect2(art.position.x, art.end.y, art.size.x, NAME_HEIGHT)
		var art_bg := ArenaUi.SLATE if is_hovered() and not disabled else ArenaUi.SHADE
		draw_rect(art, art_bg)
		ArenaUi.draw_selection_portrait(self, portrait, art)
		draw_rect(name_strip, ArenaUi.SUN if button_pressed else ArenaUi.NIGHT)
		var ink := ArenaUi.NIGHT if button_pressed else ArenaUi.INK
		var font := ArenaUi.BODY
		const NAME_SIZE := 18
		var baseline := name_strip.get_center().y + (font.get_ascent(NAME_SIZE) - font.get_descent(NAME_SIZE)) * 0.5
		draw_string(font, Vector2(name_strip.position.x, roundf(baseline)), hero_name, HORIZONTAL_ALIGNMENT_CENTER, name_strip.size.x, NAME_SIZE, ink)

## One kit slot as a toggle button (lit while its text is open): the icon tile on top, its key under it. The theme
## draws the button frame, the tile is drawn over it.
class SkillTile extends Button:
	var slot := 0
	var hero: Hero

	func _draw() -> void:
		if hero == null:
			return
		var r := Rect2(Vector2(roundf(size.x / 2.0 - 22.0), 9.0), Vector2(44, 44))
		ArenaUi.draw_skill(self, hero, slot, r)
		if button_pressed:
			draw_rect(r, ArenaUi.skill_color(slot), false, 3.0)
		draw_string(ArenaUi.BODY, Vector2(0, size.y - 14.0), ArenaUi.skill_key(slot, 0), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16,
			ArenaUi.SHADE if button_pressed else ArenaUi.INK)   # a pressed tile is gold

func _go_back() -> void:
	if _has_roster:
		Net.leave()
	else:
		get_tree().change_scene_to_file(Net.MENU_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if ChatBox.typing:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode in [KEY_Q, KEY_E]:
		_step_skill(-1 if key.keycode == KEY_Q else 1)
		get_viewport().set_input_as_handled()
		return
	var pad := event as InputEventJoypadButton
	if pad and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_step_skill(-1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
		get_viewport().set_input_as_handled()
		return
	if ArenaUi.back_pressed(event) and not ChatBox.typing:
		get_viewport().set_input_as_handled()
		_go_back()

func _start_solo_match() -> void:
	Net.enter_arena()

func _on_ready_toggled() -> void:
	Net.set_ready(_ready_btn.button_pressed)
	_ready_btn.text = "Unready" if _ready_btn.button_pressed else "Ready"
	for card in _hero_buttons:
		card.disabled = _ready_btn.button_pressed

func _refresh_status() -> void:
	if not is_instance_valid(_roster) or not is_instance_valid(_status):
		return
	for child in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	var ready := 0
	var bots := 0
	for id: int in ids:
		var member: Dictionary = Net.roster[id]
		if _solo_match and id == Net.local_id():
			continue
		if _solo_match:
			bots += 1
		if member.ready:
			ready += 1
		var player := ArenaUi.label("%s / %s" % [member.name, Hero.by_id(member.hero).display_name], 16, ArenaUi.MOSS if member.ready else ArenaUi.MUTED)
		player.custom_minimum_size.x = 195
		player.size_flags_horizontal = SIZE_EXPAND_FILL
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_roster.add_child(player)
	_status.text = "%d bot opponents" % bots if _solo_match else "%d of %d players ready" % [ready, Net.roster.size()]

func _process(delta: float) -> void:
	if not _online:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_timer_label.text = "Battle starts in %d s" % ceili(_time_left)
	if multiplayer.is_server() and (Net.all_ready() or _time_left <= 0.0):
		Net.enter_arena()
