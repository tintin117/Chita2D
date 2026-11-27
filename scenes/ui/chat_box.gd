class_name ChatBox extends Control
## Text chat. Enter opens the input, Enter sends, Esc cancels. Lines fade after LIFE seconds (all of them show while
## typing). Messages go through Net (Net.send_chat / Net.chat_received), and the log lives there, so it survives the
## lobby -> hero pick -> match scene changes. While typing, ChatBox.typing is true and the local player ignores input.

const LIFE := 9.0
const FADE := 1.0
const SHOWN := 6          ## lines shown when idle
const SHOWN_TYPING := 10  ## lines shown while typing
const WIDTH := 420.0
const LINE_H := 24.0
const FONT_PX := 16

static var typing := false

var bottom_margin := 168.0   ## px above the bottom edge (the match clears the hero panel)
var left_margin := 16.0
var online_only := true      ## hidden (and Enter does nothing) outside a real lobby: solo, or no session yet
var _field: LineEdit

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_field = LineEdit.new()
	_field.theme = ArenaUi.THEME
	_field.max_length = Net.CHAT_MAX
	_field.placeholder_text = "Say something...  (Enter: send, Esc: cancel)"
	_field.add_theme_font_override("font", ArenaUi.BODY)
	_field.add_theme_font_size_override("font_size", FONT_PX)
	_field.visible = false
	_field.text_submitted.connect(_on_submit)
	_field.focus_exited.connect(_close)
	add_child(_field)
	Net.chat_received.connect(func(_line: Dictionary) -> void: Sfx.play("emote", Vector2.INF, -10.0, 1.8))

func _exit_tree() -> void:
	typing = false

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if typing:
		if event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return   # another text field (lobby id, name) owns Enter
		_open()
		get_viewport().set_input_as_handled()

func _open() -> void:
	typing = true
	_field.text = ""
	_field.visible = true
	_field.grab_focus()

func _close() -> void:
	if not typing:
		return
	typing = false
	_field.visible = false
	_field.release_focus()

func _on_submit(text: String) -> void:
	Net.send_chat(text)
	_close()

func _process(_delta: float) -> void:
	visible = not online_only or (not Net.roster.is_empty() and not Net.solo)
	if not visible:
		_close()
		return
	var view := get_viewport_rect().size
	_field.position = Vector2(left_margin, view.y - bottom_margin)
	_field.size = Vector2(WIDTH, 32)
	queue_redraw()

func _draw() -> void:
	var lines := Net.chat_log
	var view := get_viewport_rect().size
	var shown := SHOWN_TYPING if typing else SHOWN
	var now := Time.get_ticks_msec()
	var y := view.y - bottom_margin - 6.0
	var drawn := 0
	for i in range(lines.size() - 1, -1, -1):
		if drawn >= shown:
			break
		var line: Dictionary = lines[i]
		var age := (now - int(line.at)) / 1000.0
		var alpha := 1.0 if typing else clampf((LIFE - age) / FADE, 0.0, 1.0)
		if alpha <= 0.0:
			break   # older lines are older still
		var who := "%s: " % line.name
		var who_w := ArenaUi.BODY.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
		y -= LINE_H
		draw_rect(Rect2(Vector2(left_margin, y), Vector2(WIDTH, LINE_H - 2.0)), Color(ArenaUi.SHADE, 0.85 * alpha))
		draw_string(ArenaUi.BODY, Vector2(left_margin + 8.0, y + 17), who, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, Color(name_color(line), alpha))
		draw_string(ArenaUi.BODY, Vector2(left_margin + 8.0 + who_w, y + 17), line.text, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 16 - who_w, FONT_PX, Color(ArenaUi.INK, alpha))
		drawn += 1

static func name_color(line: Dictionary) -> Color:
	var team: int = line.get("team", -1)
	if Net.is_team_mode() and team >= 0 and team < Player.TEAM_COLORS.size():
		return Player.TEAM_COLORS[team]
	return Player.NAME_COLORS[int(line.get("slot", 0)) % Player.NAME_COLORS.size()]
