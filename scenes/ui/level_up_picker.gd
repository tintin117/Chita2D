class_name LevelUpPicker extends CanvasLayer
## Level-up screen: pauses the game and offers 3 skill upgrades. PLACEHOLDER: choosing one only closes the screen
## (no effect yet). Click a card, press 1/2/3, or use the d-pad/stick + A. Level-ups that arrive while one is
## open (co-op) are queued and shown one after another.

static var _queue: Array = []   ## [Player, level] waiting for their turn
static var _open := false

var _player: Player
var _level := 1
var _closing := false
var _row: HBoxContainer

## Entry point: call when a player levels up.
static func request(tree: SceneTree, player: Player, level: int) -> void:
	_queue.append([player, level])
	if not _open:
		_show_next(tree)

static func _show_next(tree: SceneTree) -> void:
	if _queue.is_empty():
		return
	var job: Array = _queue.pop_front()
	var pk := LevelUpPicker.new()
	pk._player = job[0]
	pk._level = job[1]
	_open = true
	tree.current_scene.add_child(pk)

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	center.add_child(box)
	var title := Label.new()
	title.text = "LEVEL UP!   Level %d\nChoose a skill upgrade  (placeholder)" % _level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)
	var row := HBoxContainer.new()
	_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)

	var slots := range(_player.spells.size())
	slots.shuffle()
	for n in mini(3, slots.size()):
		var spell: Spell = _player.spells[slots[n]]
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 300)
		b.text = "[%d]\n\n%s\n\nUpgrade %s\n\n(placeholder,\nno effect yet)" % [n + 1, spell.display_name, "ABC"[n]]
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_close)
		row.add_child(b)
	row.get_child(0).grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.keycode - KEY_1
		if n >= 0 and n < _row.get_child_count():
			get_viewport().set_input_as_handled()
			_close()

func _close() -> void:
	_closing = true
	queue_free()

func _exit_tree() -> void:
	_open = false
	if not _closing:   # scene reloaded under us: drop everything
		_queue.clear()
		get_tree().paused = false
	elif _queue.is_empty():
		get_tree().paused = SlotMachine.is_open()
	else:
		_show_next.call_deferred(get_tree())
