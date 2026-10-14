class_name TensionHud extends CanvasLayer
## Top-centre tension bar (fills towards the next level, heats from yellow to red) and the list of active rules.

const BAR := Vector2(320, 8)

var tension: Tension
var _canvas := Canvas.new()

func setup(t: Tension) -> void:
	tension = t
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep the bar and rule list current while the slot machine has the game paused
	_canvas.hud = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)

class Canvas extends Control:
	var hud: TensionHud

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := hud.tension
		if not is_instance_valid(t):
			return
		var f := ThemeDB.fallback_font
		var heat := clampf(t.level / 6.0, 0.0, 1.0)
		var col := Color(1.0, 0.85, 0.3).lerp(Color(0.95, 0.2, 0.15), heat)
		var r := Rect2((size.x - BAR.x) / 2.0, 8, BAR.x, BAR.y)
		draw_rect(r.grow(2), Color(0.05, 0.04, 0.04, 0.9))
		var p := t.progress()
		var blink := 1.0 if p < 0.85 else 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.02)   # about to roll
		draw_rect(Rect2(r.position, Vector2(r.size.x * p, r.size.y)), Color(col, blink))
		draw_rect(r.grow(2), Color(0.9, 0.75, 0.4, 0.8), false, 1.5)
		draw_string_outline(f, Vector2(r.end.x + 14, 17), "TENSION  %d" % t.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color.BLACK)
		draw_string(f, Vector2(r.end.x + 14, 17), "TENSION  %d" % t.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		# active rules, grouped: "Adrenaline x2"
		var counts := {}
		for id: String in RuleSet.current.active:
			counts[id] = counts.get(id, 0) + 1
		var y := 62.0
		for id: String in counts:
			var rule: Dictionary = RuleSet.RULES[id]
			var line: String = rule.name if counts[id] == 1 else "%s x%d" % [rule.name, counts[id]]
			draw_string_outline(f, Vector2(14, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color.BLACK)
			draw_string(f, Vector2(14, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, rule.color)
			y += 20.0
