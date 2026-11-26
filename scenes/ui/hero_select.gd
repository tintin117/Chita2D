class_name HeroSelect extends CanvasLayer
## Pick a hero for every player before the run. Selections stay changeable until the run starts.
## Each player gets a strip of the screen: a 4 x 2 grid of portraits, then a detail panel for the selected hero with
## stat bars and a row of kit icons (basic / skill / passive / ult). Hover an icon to read it, click it to keep it open.
## Mouse: click a portrait to select it, click START to begin.
## Keyboard / gamepad: move with left/right/up/down, attack or dash toggles READY, the skill key cycles the icon row.
## The run starts when everyone is ready.

signal finished(heroes: Array)

const GRID_COLS := 4
const TILE_MAX := 180.0           ## portrait tile width; shrinks when several players share the screen
const PORTRAIT_MAX := 112.0
const PANEL_H := 206.0
const ICON := 48.0
const GAP := 8.0
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
	head.offset_top = 16
	add_child(head)
	var hint := Label.new()
	hint.text = "Click a hero, hover its skill icons to read them, then press START  -  or move with the stick / WASD and press attack / dash (gamepad: A) to ready up"
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
	start.offset_top = -96
	start.offset_bottom = -40
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
	var cursor := 2              ## selected hero (starts on the Mage)
	var confirmed := false       ## keyboard / gamepad "I'm happy with this"
	var skill := 1               ## kit slot whose text is open (0 basic, 1 skill, 2 passive, 3 ult); starts on the skill
	var _hover := -1             ## portrait under the mouse
	var _skill_hover := -1       ## kit icon under the mouse: previews its text without changing `skill`
	var _p := "p1_"
	var _age := 0.0
	var _portraits: Array[Texture2D] = []

	func _ready() -> void:
		_p = "p%d_" % (index + 1)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for h in Hero.all():
			_portraits.append(ArenaUi.portrait(h, HeroSelect.COLORS[index % 2]))

	## The strip of screen this player owns, between the title and the START button.
	func _area() -> Rect2:
		var vp := get_viewport_rect().size
		var w := vp.x / count
		return Rect2(index * w + 20.0, 84.0, w - 40.0, vp.y - 84.0 - 104.0)

	func _tile_size() -> Vector2:
		var a := _area()
		var tw := minf(HeroSelect.TILE_MAX, (a.size.x - (HeroSelect.GRID_COLS - 1) * HeroSelect.GAP) / HeroSelect.GRID_COLS)
		return Vector2(tw, minf(HeroSelect.PORTRAIT_MAX, tw - 16.0) + 30.0)

	func _grid_width() -> float:
		return HeroSelect.GRID_COLS * _tile_size().x + (HeroSelect.GRID_COLS - 1) * HeroSelect.GAP

	## Screen rect of portrait tile i (shared by drawing and mouse picking).
	func _tile(i: int) -> Rect2:
		var ts := _tile_size()
		var a := _area()
		var x0 := a.position.x + (a.size.x - _grid_width()) / 2.0
		@warning_ignore("integer_division")
		var row := i / HeroSelect.GRID_COLS
		var col := i % HeroSelect.GRID_COLS
		return Rect2(Vector2(x0 + col * (ts.x + HeroSelect.GAP), a.position.y + row * (ts.y + HeroSelect.GAP)), ts)

	## The detail panel under the grid.
	func _panel() -> Rect2:
		var ts := _tile_size()
		var a := _area()
		var rows := ceili(float(Hero.all().size()) / HeroSelect.GRID_COLS)
		var top := a.position.y + rows * (ts.y + HeroSelect.GAP) + 4.0
		return Rect2(a.position.x + (a.size.x - _grid_width()) / 2.0, top, _grid_width(), minf(HeroSelect.PANEL_H, a.end.y - top))

	## Screen rect of kit icon `slot` inside the detail panel.
	func _icon(slot: int) -> Rect2:
		var p := _panel()
		return Rect2(p.position + Vector2(12.0 + slot * (HeroSelect.ICON + 10.0), 110.0), Vector2(HeroSelect.ICON, HeroSelect.ICON))

	func _select(i: int) -> void:
		cursor = i
		confirmed = false        # changing your mind cancels READY

	func _input(event: InputEvent) -> void:
		if _age <= HeroSelect.INPUT_DELAY:
			return
		# Left click on a portrait selects that hero (it can be changed again until START); on a kit icon it opens its text.
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in Hero.all().size():
				if _tile(i).has_point(event.position):
					_select(i)
					get_viewport().set_input_as_handled()
					return
			for s in ArenaUi.SKILL_SLOTS:
				if _icon(s).has_point(event.position):
					skill = s
					get_viewport().set_input_as_handled()
					return

	func _process(delta: float) -> void:
		_age += delta
		var m := get_local_mouse_position()
		var n := Hero.all().size()
		_hover = -1
		for i in n:
			if _tile(i).has_point(m):
				_hover = i
		_skill_hover = -1
		for s in ArenaUi.SKILL_SLOTS:
			if _icon(s).has_point(m):
				_skill_hover = s
		if _age > HeroSelect.INPUT_DELAY:
			var d := int(Input.is_action_just_pressed(_p + "right")) - int(Input.is_action_just_pressed(_p + "left"))
			d += HeroSelect.GRID_COLS * (int(Input.is_action_just_pressed(_p + "down")) - int(Input.is_action_just_pressed(_p + "up")))
			if d != 0:
				_select(posmod(cursor + d, n))
			if Input.is_action_just_pressed(_p + "skill") and _skill_hover < 0:
				skill = (skill + 1) % ArenaUi.SKILL_SLOTS
			# Left mouse is also the P1 basic action; clicks are handled in _input, so ignore it here.
			var confirm := Input.is_action_just_pressed(_p + "dash") \
				or (Input.is_action_just_pressed(_p + "basic") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
			if confirm:
				confirmed = not confirmed
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var heroes := Hero.all()
		var first := _tile(0)
		var tag := "P%d  %s" % [index + 1, ("READY: " if confirmed else "Selected: ") + heroes[cursor].display_name]
		draw_string(font, Vector2(first.position.x, first.position.y - 10), tag, HORIZONTAL_ALIGNMENT_LEFT, _grid_width(), 20,
			Color(0.6, 1, 0.6) if confirmed else Color(1, 0.9, 0.6))
		for i in heroes.size():
			var h := heroes[i]
			var r := _tile(i)
			var sel := i == cursor
			var accent := _accent(h)
			var ps := r.size.y - 30.0
			draw_rect(r, Color(0.14, 0.12, 0.2, 0.98) if sel else Color(0.08, 0.07, 0.12, 0.96))
			# heroes 5-8 share sprite layouts with 1-4: the tint tells them apart
			var tint := h.tint.lerp(Color.WHITE, 0.4) if h.base_id != "" else Color.WHITE
			draw_texture_rect(_portraits[i], Rect2(r.position + Vector2((r.size.x - ps) / 2.0, 4), Vector2(ps, ps)), false, tint)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 26), Vector2(r.size.x, 26)), Color(accent, 0.5 if sel else 0.3))
			draw_string(font, r.position + Vector2(0, r.size.y - 8), h.display_name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, Color.WHITE)
			if sel:
				draw_rect(r, Color(0.6, 1, 0.6) if confirmed else Color(1, 0.95, 0.5), false, 4.0)
			elif i == _hover:
				draw_rect(r, Color(1, 1, 1, 0.55), false, 3.0)     # hover only previews, click to select
			else:
				draw_rect(r, Color(accent, 0.6), false, 2.0)
		_draw_panel(heroes[cursor])

	func _accent(h: Hero) -> Color:
		return Color(1.0, 0.55, 0.2) if h.attack_type == "melee" else Color(0.45, 0.75, 1.0)

	## Selected hero: name, archetype, blurb, stat bars and the kit icon row with the open icon's text beside it.
	func _draw_panel(h: Hero) -> void:
		var font := ThemeDB.fallback_font
		var p := _panel()
		var accent := _accent(h)
		var x := p.position.x + 12.0
		var y := p.position.y
		var w := p.size.x - 24.0
		draw_rect(p, Color(0.08, 0.07, 0.12, 0.96))
		draw_rect(Rect2(p.position, Vector2(p.size.x, 34)), Color(accent, 0.35))
		draw_string(font, Vector2(x, y + 24), h.display_name, HORIZONTAL_ALIGNMENT_LEFT, w, 22, Color.WHITE)
		var name_w := font.get_string_size(h.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2(x + name_w + 12, y + 24), h.archetype, HORIZONTAL_ALIGNMENT_LEFT, w - name_w - 12, 14, accent.lightened(0.3))
		draw_string(font, Vector2(x, y + 24), "READY" if confirmed else "SELECTED", HORIZONTAL_ALIGNMENT_RIGHT, w, 13,
			Color(0.6, 1, 0.6) if confirmed else Color(1, 0.95, 0.5))
		draw_multiline_string(font, Vector2(x, y + 50), h.description.trim_prefix(h.archetype + ". "), HORIZONTAL_ALIGNMENT_LEFT, w, 12, 2, Color(0.85, 0.85, 0.85))
		var col := w / 2.0
		var bar := col - 70.0
		_stat(Vector2(x, y + 76), "Range", h.attack_range / Hero.MAX_RANGE_FOR_UI, accent, bar)
		_stat(Vector2(x + col, y + 76), "Health", h.max_hp / 150.0, Color(0.9, 0.3, 0.3), bar)
		_stat(Vector2(x, y + 92), "Speed", h.speed / 300.0, Color(0.5, 0.9, 0.5), bar)
		_stat(Vector2(x + col, y + 92), "Damage", h.basic_damage / 14.0, Color(1.0, 0.8, 0.3), bar)
		var shown := _skill_hover if _skill_hover >= 0 else skill
		for s in ArenaUi.SKILL_SLOTS:
			var r := _icon(s)
			ArenaUi.draw_skill(self, h, s, r)
			if s == skill:
				draw_rect(r, ArenaUi.skill_color(s), false, 3.0)
			elif s == _skill_hover:
				draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
			draw_string(font, Vector2(r.position.x, r.end.y + 13), ArenaUi.skill_key(s, index), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10,
				Color(0.9, 0.9, 0.9) if s == shown else Color(0.6, 0.6, 0.6))
		var info := ArenaUi.skill_info(h, shown)
		var box := Rect2(_icon(ArenaUi.SKILL_SLOTS - 1).end.x + 10.0, _icon(0).position.y - 4.0, 0.0, 90.0)
		box.size.x = p.end.x - 12.0 - box.position.x
		draw_rect(box, Color(0, 0, 0, 0.35))
		draw_rect(box, Color(ArenaUi.skill_color(shown), 0.6), false, 1.0)
		draw_string(font, box.position + Vector2(8, 17), info[0], HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 16, 14, ArenaUi.skill_color(shown))
		draw_multiline_string(font, box.position + Vector2(8, 34), info[1], HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 16, 11, 4, Color(0.85, 0.85, 0.8))
		draw_rect(p, Color(accent, 0.6), false, 2.0)

	func _stat(pos: Vector2, label: String, frac: float, col: Color, bar := 112.0) -> void:
		var font := ThemeDB.fallback_font
		draw_string(font, pos + Vector2(0, 11), label, HORIZONTAL_ALIGNMENT_LEFT, 56, 12, Color(0.9, 0.9, 0.9))
		draw_rect(Rect2(pos + Vector2(58, 2), Vector2(bar, 9)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(pos + Vector2(58, 2), Vector2(bar * clampf(frac, 0.05, 1.0), 9)), col)
