class_name MatchOverlay extends Control

var pause_tree := false
var _title: String
var _leave: Callable
var _resume: Button
var _previous_focus: Control

func configure(title: String, leave: Callable) -> void:
	_title = title
	_leave = leave

func _ready() -> void:
	theme = ArenaUi.THEME
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	hide()
	ArenaUi.scrim(self, 0.83)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 440
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(ArenaUi.heading(_title, 33))
	if _leave.is_valid() and not pause_tree:
		box.add_child(ArenaUi.label("The match continues while this menu is open.", 17, ArenaUi.MUTED))

	var bus := AudioServer.get_bus_index("Master")
	var volume := HSlider.new()
	var value := ArenaUi.label("", 18, ArenaUi.MUTED)
	var set_volume := func(level: float) -> void:
		value.text = "Master volume   %d%%" % roundi(level * 100)
		AudioServer.set_bus_mute(bus, is_zero_approx(level))
		if level > 0.0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(level))
	volume.max_value = 1.0
	volume.step = 0.05
	volume.custom_minimum_size.y = 30
	volume.value = 0.0 if AudioServer.is_bus_mute(bus) else db_to_linear(AudioServer.get_bus_volume_db(bus))
	set_volume.call(volume.value)
	volume.value_changed.connect(set_volume)
	box.add_child(value)
	box.add_child(volume)

	var display := ArenaUi.button("", Callable())
	var update_display := func() -> void:
		var mode := get_window().mode
		var full := mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		display.text = "Display: Fullscreen" if full else "Display: Windowed"
	display.pressed.connect(func() -> void:
		var mode := get_window().mode
		var full := mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		get_window().mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
		update_display.call())
	update_display.call()
	box.add_child(display)

	_resume = ArenaUi.button("Resume" if _leave.is_valid() else "Back", close, true)
	box.add_child(_resume)
	if _leave.is_valid():
		box.add_child(ArenaUi.button("Leave match", func() -> void:
			close()
			_leave.call()))

func open() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	_resume.grab_focus()
	if pause_tree:
		get_tree().paused = true

func close() -> void:
	if not visible:
		return
	hide()
	if pause_tree:
		get_tree().paused = false
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START)):
		get_viewport().set_input_as_handled()
		close()

func _exit_tree() -> void:
	if visible and pause_tree:
		get_tree().paused = false
