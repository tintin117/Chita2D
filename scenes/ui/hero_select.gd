class_name HeroSelect extends CanvasLayer
## Pick a hero for every player before the run. Selections stay changeable until the run starts.
## Mouse: click a card to select it, click START to begin.
## Keyboard / gamepad: left/right to move, attack or dash toggles READY; the run starts when everyone is ready.

signal finished(heroes: Array)

const CARD := Vector2(190, 412)
const GAP := 12.0
const INPUT_DELAY := 0.4
const COLORS := ["Blue", "Yellow"]

var _pickers: Array[Picker] = []
var _age := 0.0
var _started := false

func open(player_count: int) -> void:
	layer = 20
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var head := Label.new()
	head.text = "Choose your hero"
	head.add_theme_font_size_override("font_size", 36)
	head.add_theme_color_override("font_outline_color", Color.BLACK)
	head.add_theme_constant_override("outline_size", 10)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 28
	add_child(head)
	var hint := Label.new()
	hint.text = "Click a hero to select, then press START  -  or move left/right and press attack / dash (gamepad: stick + A) to ready up"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	hint.offset_bottom = -8
	add_child(hint)
	var start := Button.new()
	start.text = "START"
	start.focus_mode = Control.FOCUS_NONE       # keeps Space / Enter from clicking it by accident
	start.add_theme_font_size_override("font_size", 28)
	start.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	start.offset_left = -120
	start.offset_right = 120
	start.offset_top = -100
	start.offset_bottom = -42
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.2, 0.55, 0.25), "hover": Color(0.28, 0.7, 0.33), "pressed": Color(0.15, 0.42, 0.2)}[state]
		sb.border_color = Color(0.85, 1.0, 0.8)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(8)
		start.add_theme_stylebox_override(state, sb)
	start.add_theme_color_override("font_color", Color.WHITE)
	start.add_theme_color_override("font_hover_color", Color.WHITE)
	start.add_theme_color_override("font_pressed_color", Color.WHITE)
	start.pressed.connect(_start)
	add_child(start)
	for i in player_count:
		var pk := Picker.new()
		pk.index = i
		pk.count = player_count
		pk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pk)
		_pickers.append(pk)

func _start() -> void:
	if _started or _age < INPUT_DELAY:
		return
	_started = true
	var out := []
	for p in _pickers:
		out.append(Hero.all()[p.cursor])
	finished.emit(out)
	queue_free()

func _process(delta: float) -> void:
	_age += delta
	if _pickers.all(func(p: Picker) -> bool: return p.confirmed):
		_start()

class Picker extends Control:
	var index := 0
	var count := 1
	var cursor := 1          ## selected hero (starts on the Wizard)
	var confirmed := false       ## keyboard / gamepad "I'm happy with this"
	var _hover := -1
	var _p := "p1_"
	var _age := 0.0

	func _ready() -> void:
		_p = "p%d_" % (index + 1)

	## Screen rect of hero card i (shared by drawing and mouse picking).
	func _card(i: int) -> Rect2:
		var n := Hero.all().size()
		var w := n * HeroSelect.CARD.x + (n - 1) * HeroSelect.GAP
		var cx := get_viewport_rect().size.x * (index + 0.5) / count
		var top := (get_viewport_rect().size.y - HeroSelect.CARD.y) / 2.0 + 20.0
		return Rect2(Vector2(cx - w / 2.0 + i * (HeroSelect.CARD.x + HeroSelect.GAP), top), HeroSelect.CARD)

	func _select(i: int) -> void:
		cursor = i
		confirmed = false        # changing your mind cancels READY

	func _input(event: InputEvent) -> void:
		if _age <= HeroSelect.INPUT_DELAY:
			return
		# Left click on a card selects that hero (it can be changed again until START).
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in Hero.all().size():
				if _card(i).has_point(event.position):
					_select(i)
					get_viewport().set_input_as_handled()
					return

	func _process(delta: float) -> void:
		_age += delta
		var m := get_local_mouse_position()
		_hover = -1
		for i in Hero.all().size():
			if _card(i).has_point(m):
				_hover = i
		if _age > HeroSelect.INPUT_DELAY:
			var d := int(Input.is_action_just_pressed(_p + "right")) - int(Input.is_action_just_pressed(_p + "left"))
			if d != 0:
				_select(posmod(cursor + d, Hero.all().size()))
			# Left mouse is also the P1 basic action; clicks are handled in _input, so ignore it here.
			var confirm := Input.is_action_just_pressed(_p + "dash") \
				or (Input.is_action_just_pressed(_p + "basic") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
			if confirm:
				confirmed = not confirmed
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var heroes := Hero.all()
		var first := _card(0)
		var w := heroes.size() * HeroSelect.CARD.x + (heroes.size() - 1) * HeroSelect.GAP
		var tag := "P%d  %s" % [index + 1, ("READY: " if confirmed else "Selected: ") + heroes[cursor].display_name]
		draw_string(font, Vector2(first.position.x, first.position.y - 16), tag, HORIZONTAL_ALIGNMENT_LEFT, w, 22, Color(0.6, 1, 0.6) if confirmed else Color(1, 0.9, 0.6))
		for i in heroes.size():
			var h := heroes[i]
			var r := _card(i)
			var sel := i == cursor
			var accent := Color(1.0, 0.55, 0.2) if h.attack_type == "melee" else Color(0.45, 0.75, 1.0)
			draw_rect(r, Color(0.08, 0.07, 0.12, 0.96) if not sel else Color(0.14, 0.12, 0.2, 0.98))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 40)), Color(accent, 0.5))
			draw_string(font, r.position + Vector2(10, 28), h.display_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 24, Color.WHITE)
			if sel:
				draw_string(font, r.position + Vector2(0, 28), "READY" if confirmed else "SELECTED", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10, 13, Color(0.6, 1, 0.6) if confirmed else Color(1, 0.95, 0.5))
			var tex := h.portrait(HeroSelect.COLORS[index % 2])
			draw_texture_rect(tex, Rect2(r.position + Vector2(r.size.x / 2.0 - 80, 42), Vector2(160, 160)), false)
			var kind := "Melee" if h.attack_type == "melee" else ("Mid range" if h.attack_range < 500.0 else "Long range")
			draw_string(font, r.position + Vector2(10, 220), "%s: %s" % [kind, h.basic_name], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 13, accent.lightened(0.3))
			_stat(r.position + Vector2(10, 232), "Range", h.attack_range / Hero.MAX_RANGE_FOR_UI, accent)
			_stat(r.position + Vector2(10, 252), "Health", h.max_hp / 150.0, Color(0.9, 0.3, 0.3))
			_stat(r.position + Vector2(10, 272), "Speed", h.speed / 300.0, Color(0.5, 0.9, 0.5))
			_stat(r.position + Vector2(10, 292), "Damage", h.basic_damage / 14.0, Color(1.0, 0.8, 0.3))
			draw_multiline_string(font, r.position + Vector2(10, 326), h.description, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 12, 3, Color(0.85, 0.85, 0.85))
			var kit := h.make_kit()
			draw_string(font, r.position + Vector2(10, 376), "Right click: " + kit[1].display_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 13, Color(1, 0.9, 0.6))
			draw_string(font, r.position + Vector2(10, 396), "Special: " + kit[3].display_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 13, Color(1, 0.9, 0.6))
			if sel:
				draw_rect(r, Color(0.6, 1, 0.6) if confirmed else Color(1, 0.95, 0.5), false, 5.0)
			elif i == _hover:
				draw_rect(r, Color(1, 1, 1, 0.55), false, 3.0)     # hover only previews, click to select
			else:
				draw_rect(r, Color(accent, 0.6), false, 2.0)

	func _stat(pos: Vector2, label: String, frac: float, col: Color) -> void:
		var font := ThemeDB.fallback_font
		draw_string(font, pos + Vector2(0, 11), label, HORIZONTAL_ALIGNMENT_LEFT, 56, 12, Color(0.9, 0.9, 0.9))
		draw_rect(Rect2(pos + Vector2(58, 2), Vector2(112, 9)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(pos + Vector2(58, 2), Vector2(112.0 * clampf(frac, 0.05, 1.0), 9)), col)
