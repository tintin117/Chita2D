class_name HeroSelect extends CanvasLayer
## Pick a hero for every player before the run. Move with that player's left/right, confirm with basic or dash.

signal finished(heroes: Array)

const CARD := Vector2(190, 412)
const GAP := 12.0
const INPUT_DELAY := 0.4
const COLORS := ["Blue", "Yellow"]

var _pickers: Array[Picker] = []
var _age := 0.0

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
	for i in player_count:
		var pk := Picker.new()
		pk.index = i
		pk.count = player_count
		pk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pk)
		_pickers.append(pk)

func _process(delta: float) -> void:
	_age += delta
	if _age > INPUT_DELAY and _pickers.all(func(p: Picker) -> bool: return p.done):
		var out := []
		for p in _pickers:
			out.append(Hero.all()[p.cursor])
		finished.emit(out)
		queue_free()

class Picker extends Control:
	var index := 0
	var count := 1
	var cursor := 1          ## starts on the Wizard
	var done := false
	var _p := "p1_"
	var _age := 0.0

	func _ready() -> void:
		_p = "p%d_" % (index + 1)

	func _process(delta: float) -> void:
		_age += delta
		if not done and _age > HeroSelect.INPUT_DELAY:
			var d := int(Input.is_action_just_pressed(_p + "right")) - int(Input.is_action_just_pressed(_p + "left"))
			if d != 0:
				cursor = posmod(cursor + d, Hero.all().size())
			if Input.is_action_just_pressed(_p + "basic") or Input.is_action_just_pressed(_p + "dash"):
				done = true
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var font := ThemeDB.fallback_font
		var heroes := Hero.all()
		var w := heroes.size() * CARD.x + (heroes.size() - 1) * GAP
		var cx := vp.x * (index + 0.5) / count
		var top := (vp.y - CARD.y) / 2.0 + 20.0
		var tag := "P%d  %s" % [index + 1, "READY" if done else "Choose one"]
		draw_string(font, Vector2(cx - w / 2.0, top - 16), tag, HORIZONTAL_ALIGNMENT_LEFT, w, 22, Color(0.6, 1, 0.6) if done else Color(1, 0.9, 0.6))
		for i in heroes.size():
			var h := heroes[i]
			var r := Rect2(Vector2(cx - w / 2.0 + i * (CARD.x + GAP), top), CARD)
			var sel := i == cursor
			var accent := Color(1.0, 0.55, 0.2) if h.attack_type == "melee" else Color(0.45, 0.75, 1.0)
			draw_rect(r, Color(0.08, 0.07, 0.12, 0.96))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 40)), Color(accent, 0.5))
			draw_string(font, r.position + Vector2(10, 28), h.display_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 24, Color.WHITE)
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
			draw_rect(r, Color(1, 0.95, 0.5) if sel else Color(accent, 0.6), false, 5.0 if sel else 2.0)

	func _stat(pos: Vector2, label: String, frac: float, col: Color) -> void:
		var font := ThemeDB.fallback_font
		draw_string(font, pos + Vector2(0, 11), label, HORIZONTAL_ALIGNMENT_LEFT, 56, 12, Color(0.9, 0.9, 0.9))
		draw_rect(Rect2(pos + Vector2(58, 2), Vector2(112, 9)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(pos + Vector2(58, 2), Vector2(112.0 * clampf(frac, 0.05, 1.0), 9)), col)
