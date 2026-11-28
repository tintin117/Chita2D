extends Node
## Local display controls shared by the menus and matches.

signal fullscreen_changed(enabled: bool)

const CURSOR := preload("res://assets/ui/mouse-cursor.png")
const CURSOR_TIP := Vector2(4, 3)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlaySettings.load_once()
	_apply_cursor()

func _exit_tree() -> void:
	if PlaySettings.custom_cursor:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F11:
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()

func is_fullscreen() -> bool:
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

func set_fullscreen(enabled: bool) -> void:
	if is_fullscreen() == enabled:
		return
	get_window().mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
	fullscreen_changed.emit(is_fullscreen())

func set_custom_cursor(enabled: bool) -> void:
	PlaySettings.custom_cursor = enabled
	PlaySettings.save()
	_apply_cursor()

func _apply_cursor() -> void:
	if PlaySettings.custom_cursor:
		Input.set_custom_mouse_cursor(CURSOR, Input.CURSOR_ARROW, CURSOR_TIP)
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
