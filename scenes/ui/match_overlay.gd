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
	var panel := ArenaUi.OrnatePanel.new()
	panel.custom_minimum_size.x = 480
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(ArenaUi.title(_title, 40))
	if _leave.is_valid() and not pause_tree:
		var note := ArenaUi.label("The match continues while this menu is open.", 16, ArenaUi.MUTED)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(note)
	add_settings(box)

	box.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	box.add_child(actions)
	if _leave.is_valid():
		actions.add_child(ArenaUi.button("Leave match", func() -> void:
			close()
			_leave.call()))
	_resume = ArenaUi.button("Resume" if _leave.is_valid() else "Back", close, true)
	_resume.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(_resume)

## Appends the volume, display and playtest controls to `box` (this menu, and the gym's side panel).
static func add_settings(box: Container, playtest_caption := true) -> void:
	PlaySettings.load_once()
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

	var display_controls: Container = box
	if not playtest_caption:
		display_controls = HBoxContainer.new()
		box.add_child(display_controls)

	var display := ArenaUi.button("Fullscreen [F11]", Callable())
	display.size_flags_horizontal = SIZE_EXPAND_FILL
	display.toggle_mode = true
	display.set_pressed_no_signal(ClientDisplay.is_fullscreen())
	display.toggled.connect(ClientDisplay.set_fullscreen)
	ClientDisplay.fullscreen_changed.connect(display.set_pressed_no_signal)
	display_controls.add_child(display)

	var cursor := ArenaUi.button("Cursor: Custom" if PlaySettings.custom_cursor else "Cursor: System", Callable())
	cursor.size_flags_horizontal = SIZE_EXPAND_FILL
	cursor.pressed.connect(func() -> void:
		ClientDisplay.set_custom_cursor(not PlaySettings.custom_cursor)
		cursor.text = "Cursor: Custom" if PlaySettings.custom_cursor else "Cursor: System")
	display_controls.add_child(cursor)

	# playtest feel toggles (local only, saved per machine: see PlaySettings)
	if playtest_caption:
		box.add_child(ArenaUi.label("Playtest", 18, ArenaUi.MUTED))
	var aim_btn := ArenaUi.button("", Callable())
	var aim_text := func() -> void:
		aim_btn.text = "Attack aim: Move direction" if PlaySettings.aim_facing else "Attack aim: Mouse"
	aim_btn.pressed.connect(func() -> void:
		PlaySettings.aim_facing = not PlaySettings.aim_facing
		PlaySettings.save()
		aim_text.call())
	aim_text.call()
	box.add_child(aim_btn)
	var step_btn := ArenaUi.button("", Callable())
	var step_text := func() -> void:
		step_btn.text = "Melee step-in: On" if PlaySettings.melee_step else "Melee step-in: Off"
	step_btn.pressed.connect(func() -> void:
		PlaySettings.melee_step = not PlaySettings.melee_step
		PlaySettings.save()
		step_text.call())
	step_text.call()
	box.add_child(step_btn)
	var bot_btn := ArenaUi.button("", Callable())
	var bot_text := func() -> void:
		bot_btn.text = "Bot state labels: On" if PlaySettings.bot_debug else "Bot state labels: Off"
	bot_btn.pressed.connect(func() -> void:
		PlaySettings.bot_debug = not PlaySettings.bot_debug
		PlaySettings.save()
		bot_text.call())
	bot_text.call()
	box.add_child(bot_btn)

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
	if not visible:
		return
	var pad := event as InputEventJoypadButton
	if pad and pad.button_index == JOY_BUTTON_B:   # closes on release: closing on the press would hand a held B to the skill
		get_viewport().set_input_as_handled()
		if not pad.pressed:
			close()
	elif event.is_action_pressed("ui_cancel") or (pad and pad.pressed and pad.button_index == JOY_BUTTON_START):
		get_viewport().set_input_as_handled()
		close()

func _exit_tree() -> void:
	if visible and pause_tree:
		get_tree().paused = false
