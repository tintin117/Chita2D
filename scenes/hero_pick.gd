extends Control
## Hero select. Gym (no network session): pick, then Enter Gym. Online: everyone picks and presses Ready; the host sends all
## of them into the arena once everybody is ready or the timer runs out.

const PICK_TIME := 30.0

var _online := false
var _time_left := PICK_TIME
var _ready_btn: Button
var _timer_label: Label
var _status: Label
var _hero_buttons: Array[Button] = []

func _ready() -> void:
	_online = not Net.roster.is_empty()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(_label("CHOOSE YOUR HERO", 36, Color(1, 0.85, 0.3)))
	if _online:
		_timer_label = _label("", 18, Color(0.7, 0.85, 1.0))
		box.add_child(_timer_label)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cards)
	var group := ButtonGroup.new()
	var color: String = Player.COLORS[Net.roster[Net.local_id()].slot % Player.COLORS.size()] if _online else "Blue"
	for h in Hero.all():
		cards.add_child(_card(h, color, group))

	_status = _label("", 16)
	box.add_child(_status)
	if _online:
		_ready_btn = Button.new()
		_ready_btn.text = "Ready"
		_ready_btn.toggle_mode = true
		_ready_btn.pressed.connect(_on_ready_toggled)
		box.add_child(_ready_btn)
		box.add_child(_button("Leave", Net.leave))
		Net.roster_changed.connect(_refresh_status)
		if Net.dev_enet:   # dev shim: no UI clicking in automated runs
			_ready_btn.button_pressed = true
			_on_ready_toggled()
	else:
		box.add_child(_button("Enter gym", func() -> void: get_tree().change_scene_to_file("res://scenes/gym.tscn")))
		box.add_child(_button("Back", func() -> void: get_tree().change_scene_to_file(Net.MENU_SCENE)))
	_refresh_status()

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.modulate = color
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b

func _card(h: Hero, color: String, group: ButtonGroup) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(220, 0)
	v.add_theme_constant_override("separation", 6)
	var pic := TextureRect.new()
	pic.texture = h.portrait(color)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(180, 180)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(pic)
	var b := Button.new()
	b.text = h.display_name
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = h.id == Net.my_hero
	b.pressed.connect(func() -> void: Net.set_hero(h.id))
	_hero_buttons.append(b)
	v.add_child(b)
	var desc := _label(h.description, 13, Color(1, 1, 1, 0.8))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(220, 56)
	v.add_child(desc)
	v.add_child(_label("HP %d    Speed %d    Range %d" % [h.max_hp, h.speed, h.attack_range], 12, Color(1, 0.85, 0.3)))
	return v

func _on_ready_toggled() -> void:
	Net.set_ready(_ready_btn.button_pressed)
	for b in _hero_buttons:
		b.disabled = _ready_btn.button_pressed   # locked in once ready

func _refresh_status() -> void:
	if not _online:
		_status.text = ""
		return
	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	var lines: PackedStringArray = []
	for id: int in ids:
		var r: Dictionary = Net.roster[id]
		lines.append("%s   %s   %s" % [r.name, Hero.by_id(r.hero).display_name, "READY" if r.ready else "choosing..."])
	_status.text = "\n".join(lines)

func _process(delta: float) -> void:
	if not _online:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_timer_label.text = "Battle starts in %d s" % ceili(_time_left)
	if multiplayer.is_server() and (Net.all_ready() or _time_left <= 0.0):
		Net.enter_arena()
