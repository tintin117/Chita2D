class_name MatchHud extends RefCounted

class Board extends Control:
	const WIDTH := 253.0
	var arena: Node

	func _ready() -> void:
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var viewport_width := get_viewport_rect().size.x
		var clock := "--:--"
		if arena._time_left != INF:
			var t := int(ceil(arena._time_left))
			clock = "%d:%02d" % [t / 60, t % 60]
		var mode := "Friendslop" if arena._fs else "Classic"
		var limit: int = Net.settings.kill_limit
		var info := "First to %d" % limit if limit > 0 else "No kill limit"
		var clock_box := Rect2((viewport_width - 294) * 0.5, 14, 294, 49)
		ArenaUi.panel(self, clock_box)
		_text(clock_box.position + Vector2(15, 30), mode, ArenaUi.MUTED, 15, 78)
		draw_string(ArenaUi.DISPLAY, clock_box.position + Vector2(0, 32), clock, HORIZONTAL_ALIGNMENT_CENTER, clock_box.size.x, 24, ArenaUi.GOLD)
		if arena._tdm:
			var scores: Array[int] = arena.team_totals(arena._kills, arena._teams)
			_text(clock_box.position + Vector2(183, 22), "Red %d / %d Blue" % [scores[0], scores[1]], ArenaUi.INK, 14, 96, HORIZONTAL_ALIGNMENT_RIGHT)
			_text(clock_box.position + Vector2(183, 36), info, ArenaUi.MUTED, 12, 96, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			_text(clock_box.position + Vector2(183, 30), info, ArenaUi.MUTED, 15, 96, HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_buffs(clock_box)
		_draw_scores(viewport_width)

	func _draw_buffs(clock_box: Rect2) -> void:
		var me: Player = arena._players.get(Net.local_id())
		if not me:
			return
		var buffs: PackedStringArray = []
		for kind in ["damage", "speed", "giant", "chicken"]:
			if me.buffed(kind):
				buffs.append("%s %ds" % [PvpPickup.LABELS[kind], ceili(me.buff_left(kind))])
		if not buffs.is_empty():
			var box := Rect2(clock_box.position + Vector2(0, 53), Vector2(clock_box.size.x, 30))
			draw_rect(box, ArenaUi.SHADE)
			_text(box.position + Vector2(5, 21), "  /  ".join(buffs), ArenaUi.GOLD, 16, box.size.x - 10, HORIZONTAL_ALIGNMENT_CENTER)

	func _draw_scores(viewport_width: float) -> void:
		var ids: Array = arena._players.keys()
		ids.sort_custom(func(a: int, b: int) -> bool:
			if arena._kills[a] != arena._kills[b]:
				return arena._kills[a] > arena._kills[b]
			if arena._deaths[a] != arena._deaths[b]:
				return arena._deaths[a] < arena._deaths[b]
			return a < b)
		var box := Rect2(viewport_width - WIDTH - 16, 14, WIDTH, 51 + ids.size() * 25)
		ArenaUi.panel(self, box)
		draw_string(ArenaUi.DISPLAY, box.position + Vector2(16, 28), "Standings", HORIZONTAL_ALIGNMENT_LEFT, 150, 16, ArenaUi.GOLD)
		_text(box.position + Vector2(164, 28), "KILLS", ArenaUi.MUTED, 12, 30, HORIZONTAL_ALIGNMENT_CENTER)
		_text(box.position + Vector2(199, 28), "DEATHS", ArenaUi.MUTED, 12, 40, HORIZONTAL_ALIGNMENT_CENTER)
		draw_line(box.position + Vector2(15, 36), box.position + Vector2(WIDTH - 15, 36), Color(ArenaUi.GOLD, 0.4))
		for i in ids.size():
			var id: int = ids[i]
			var p: Player = arena._players[id]
			var origin := box.position + Vector2(15, 41 + i * 25)
			var color: Color = Player.TEAM_COLORS[p.team] if p.team >= 0 else Player.NAME_COLORS[p.player_index % Player.NAME_COLORS.size()]
			if id == Net.local_id():
				draw_rect(Rect2(origin, Vector2(WIDTH - 30, 23)), Color(ArenaUi.MOSS, 0.13))
			draw_circle(origin + Vector2(6, 12), 3.0, color)
			var name_width := 124.0
			if id == arena._crown:
				draw_texture_rect(ArenaUi.CROWN, Rect2(origin + Vector2(135, 4), Vector2(16, 16)), false)
				name_width -= 8
			_text(origin + Vector2(16, 17), p.display_name, ArenaUi.INK, 16, name_width)
			_text(origin + Vector2(149, 17), str(arena._kills[id]), ArenaUi.GOLD, 16, 30, HORIZONTAL_ALIGNMENT_CENTER)
			_text(origin + Vector2(184, 17), str(arena._deaths[id]), ArenaUi.MUTED, 16, 40, HORIZONTAL_ALIGNMENT_CENTER)

	func _text(at: Vector2, text: String, color: Color, px: int, width: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
		draw_string(ArenaUi.BODY, at, text, align, width, px, color)

class KillFeed extends Control:
	const LIFE := 6.0
	const MAX := 5
	var _lines: Array[Dictionary] = []

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func add(text: String, color: Color) -> void:
		_lines.append({"text": text, "color": color, "age": 0.0})
		if _lines.size() > MAX:
			_lines.pop_front()

	func _process(delta: float) -> void:
		for line in _lines:
			line.age += delta
		_lines = _lines.filter(func(line: Dictionary) -> bool: return line.age < LIFE)
		queue_redraw()

	func _draw() -> void:
		for i in _lines.size():
			var line: Dictionary = _lines[_lines.size() - 1 - i]
			var alpha := clampf((LIFE - line.age), 0.0, 1.0)
			var at := Vector2(16, 16 + i * 34)
			var width := clampf(ArenaUi.BODY.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 44, 115, 425)
			draw_rect(Rect2(at, Vector2(width, 30)), Color(ArenaUi.SHADE, 0.94 * alpha))
			draw_rect(Rect2(at, Vector2(2, 30)), Color(line.color, alpha))
			draw_texture_rect(ArenaUi.SWORDS, Rect2(at + Vector2(8, 4), Vector2(22, 22)), false, Color(1, 1, 1, alpha))
			draw_string(ArenaUi.BODY, at + Vector2(36, 20), line.text, HORIZONTAL_ALIGNMENT_LEFT, width - 43, 16, Color(ArenaUi.INK, alpha))

class Results extends Control:
	var title := ""
	var rows: Array[Dictionary] = []
	var next_label := ""
	var proceed: Callable

	func _ready() -> void:
		theme = ArenaUi.THEME
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		ArenaUi.scrim(self, 0.82)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(center)
		var panel := PanelContainer.new()
		panel.custom_minimum_size.x = 684
		center.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		box.add_child(ArenaUi.picture(ArenaUi.CROWN, Vector2(0, 54)))
		var winner := ArenaUi.heading(title, 38)
		winner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		winner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(winner)
		if not rows.is_empty():
			box.add_child(ArenaUi.heading("Match Awards", 19))
			for row in rows:
				_add_award(box, row)
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_END
		box.add_child(actions)
		var leave := ArenaUi.button("Leave", Net.leave)
		actions.add_child(leave)
		if proceed.is_valid():
			var next := ArenaUi.button(next_label, proceed, true)
			actions.add_child(next)
			ArenaUi.defer_focus(next)
		else:
			actions.add_child(ArenaUi.label("Waiting for the host", 17, ArenaUi.MUTED))
			ArenaUi.defer_focus(leave)

	func _add_award(box: VBoxContainer, award: Dictionary) -> void:
		var stripe := PanelContainer.new()
		var tint := StyleBoxFlat.new()
		tint.bg_color = Color("#1d302d")
		tint.content_margin_left = 12
		tint.content_margin_right = 12
		tint.content_margin_top = 5
		tint.content_margin_bottom = 5
		stripe.add_theme_stylebox_override("panel", tint)
		box.add_child(stripe)
		var row := HBoxContainer.new()
		stripe.add_child(row)
		var name := ArenaUi.label(award.title, 18, ArenaUi.GOLD)
		name.custom_minimum_size.x = 176
		row.add_child(name)
		var player := ArenaUi.label(award.who, 18)
		player.size_flags_horizontal = SIZE_EXPAND_FILL
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(player)
		var detail := ArenaUi.label(award.detail, 17, ArenaUi.MUTED)
		detail.custom_minimum_size.x = 246
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(detail)
