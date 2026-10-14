class_name SlotMachine extends CanvasLayer
## Pauses the game and spins a one-row slot reel that lands on a global rule (see RuleSet), applied to every creature.
## Same pause/queue pattern as LevelUpPicker. Closes on any key/click/pad button after landing, or by itself after a few seconds.

const CARD := Vector2(200, 220)
const PITCH := 216.0          ## card spacing
const SPIN_TIME := 3.2
const STRIP_LEN := 30         ## the chosen rule sits at index STRIP_LEN - 3
const AUTO_CLOSE := 4.5
const GOLD := Color(0.95, 0.78, 0.35)

static var _queue: Array[int] = []   ## tension levels waiting for their turn
static var _open := false

var reel_pos := 0.0           ## strip index currently under the centre marker (tweened)
var strip: Array[String] = []
var _level := 1
var _rule_id := ""
var _landed := false
var _since_land := 0.0
var _closing := false
var _name_label: Label
var _desc_label: Label
var _prompt: Label

static func is_open() -> bool:
	return _open

## Call when a new tension level is reached.
static func request(tree: SceneTree, level: int) -> void:
	_queue.append(level)
	if not _open:
		_show_next(tree)

static func _show_next(tree: SceneTree) -> void:
	if _queue.is_empty() or tree.current_scene == null:
		return
	var m := SlotMachine.new()
	m._level = _queue.pop_front()
	_open = true
	tree.current_scene.add_child(m)

func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var last: String = RuleSet.current.active.back() if not RuleSet.current.active.is_empty() else ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_rule_id = RuleSet.roll(rng, last)
	var landing := STRIP_LEN - 3
	for i in STRIP_LEN:
		strip.append(_rule_id if i == landing else RuleSet.roll(rng, strip.back() if not strip.is_empty() else ""))
	if strip[landing - 1] == _rule_id:   # don't let the landing card sit next to a duplicate
		strip[landing - 1] = RuleSet.roll(rng, _rule_id)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	box.add_child(_label("TENSION LEVEL %d" % _level, 36, GOLD))
	var reel := Reel.new()
	reel.m = self
	reel.custom_minimum_size = Vector2(PITCH * 3.0, CARD.y + 44.0)
	reel.clip_contents = true
	box.add_child(reel)
	_name_label = _label(" ", 40, Color.WHITE)
	box.add_child(_name_label)
	_desc_label = _label(" \n ", 24, Color(0.9, 0.9, 0.9))
	box.add_child(_desc_label)
	_prompt = _label(" ", 18, Color(0.7, 0.7, 0.7))
	box.add_child(_prompt)

	var tw := create_tween()
	tw.tween_property(self, "reel_pos", float(landing), SPIN_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_land)

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	return l

func _land() -> void:
	_landed = true
	var rule: Dictionary = RuleSet.RULES[_rule_id]
	_name_label.text = rule.name
	_name_label.add_theme_color_override("font_color", rule.color)
	_desc_label.text = rule.desc
	_prompt.text = "Press any key"
	RuleSet.current.apply(_rule_id)

func _process(delta: float) -> void:
	if _landed:
		_since_land += delta
		if _since_land >= AUTO_CLOSE:
			_close()

func _unhandled_input(event: InputEvent) -> void:
	if _landed and _since_land > 0.6 and event.is_pressed() and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	if _closing:
		return
	_closing = true
	queue_free()

func _exit_tree() -> void:
	_open = false
	if not _closing:   # scene reloaded under us: drop everything
		_queue.clear()
		get_tree().paused = LevelUpPicker._open
	elif _queue.is_empty():
		get_tree().paused = LevelUpPicker._open
	else:
		_show_next.call_deferred(get_tree())

class Reel extends Control:
	var m: SlotMachine

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var top := (size.y - CARD.y) / 2.0 + 10.0
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.05, 0.08))
		var first := floori(m.reel_pos) - 2
		for i in range(first, first + 6):
			if i < 0 or i >= m.strip.size():
				continue
			var rule: Dictionary = RuleSet.RULES[m.strip[i]]
			var col: Color = rule.color
			var r := Rect2(c.x + (i - m.reel_pos) * PITCH - CARD.x / 2.0, top, CARD.x, CARD.y)
			draw_rect(r, Color(0.13, 0.12, 0.17))
			draw_rect(r, col, false, 3.0)
			draw_circle(r.get_center() + Vector2(0, -34), 44, col.darkened(0.55))
			draw_string_outline(ThemeDB.fallback_font, r.position + Vector2(0, 100), rule.name.substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 60, 6, Color.BLACK)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(0, 100), rule.name.substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 60, col)
			draw_string_outline(ThemeDB.fallback_font, r.position + Vector2(0, 182), rule.name, HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 22, 5, Color.BLACK)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(0, 182), rule.name, HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 22, Color.WHITE)
		draw_rect(Rect2(0, 0, 90, size.y), Color(0, 0, 0, 0.55))             # edge fades
		draw_rect(Rect2(size.x - 90, 0, 90, size.y), Color(0, 0, 0, 0.55))
		var lit := m._landed or int(Time.get_ticks_msec() / 150.0) % 2 == 0   # marquee lights
		for k in 13:
			draw_circle(Vector2(20 + k * (size.x - 40) / 12.0, 10), 4.0, GOLD if (k % 2 == 0) == lit else Color(0.35, 0.28, 0.12))
		var flash := 1.0 if not m._landed else 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		draw_rect(Rect2(c.x - CARD.x / 2.0 - 7, top - 7, CARD.x + 14, CARD.y + 14), Color(GOLD, flash), false, 5.0)
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - 12, top - 14), Vector2(c.x + 12, top - 14), Vector2(c.x, top - 1)]), GOLD)
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - 12, top + CARD.y + 14), Vector2(c.x + 12, top + CARD.y + 14), Vector2(c.x, top + CARD.y + 1)]), GOLD)
