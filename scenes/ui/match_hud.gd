class_name MatchHud extends RefCounted

class Board extends Control:
	const WIDTH := 300.0
	const ROW := 24.0
	const CLOCK := Vector2(344, 56)
	var arena: Node

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		var mode := GameMode.title(Net.mode)
		var limit: int = Net.settings.kill_limit
		var info := "First to %d" % limit if limit > 0 else "No kill limit"
		if arena._cm:
			info = "First to %d pts" % int(arena._cfg.score_limit)
		var clock_box := Rect2(Vector2(roundf((viewport_width - CLOCK.x) * 0.5), 12), CLOCK)
		for side in [-1.0, 1.0]:   # a flourish at each end of the clock
			var end := Vector2(clock_box.get_center().x + side * (CLOCK.x / 2.0 + 12.0), clock_box.get_center().y + 4.0)
			ArenaUi.draw_flourish(self, ArenaUi.SCROLL, end, 2.0, side > 0.0)
		ArenaUi.plate(self, clock_box)
		_text(clock_box.position + Vector2(18, 32), mode, ArenaUi.MUTED, 16, 96)
		draw_string(ArenaUi.DISPLAY, clock_box.position + Vector2(0, 37), clock, HORIZONTAL_ALIGNMENT_CENTER, CLOCK.x, 32, ArenaUi.INK)
		var right := clock_box.position + Vector2(CLOCK.x - 126.0, 0)
		if arena._tdm:
			var scores: Array[int] = arena.team_totals(arena._kills, arena._teams)
			_text(right + Vector2(0, 24), "Red %d / %d Blue" % [scores[0], scores[1]], ArenaUi.INK, 16, 108, HORIZONTAL_ALIGNMENT_RIGHT)
			_text(right + Vector2(0, 42), info, ArenaUi.MUTED, 16, 108, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			_text(right + Vector2(0, 32), info, ArenaUi.MUTED, 16, 108, HORIZONTAL_ALIGNMENT_RIGHT)
		var below := _draw_event_chip(clock_box)
		_draw_buffs(clock_box, below)
		_draw_scores(viewport_width)

	## The match event, pinned under the clock for the whole match (docs §6.5). Returns where the next strip may start.
	func _draw_event_chip(clock_box: Rect2) -> float:
		var ev: String = MatchEvent.current
		if ev == MatchEvent.NONE:
			return clock_box.end.y + 2.0
		var col := MatchEvent.color(ev)
		var box := Rect2(clock_box.position + Vector2(12, CLOCK.y + 2.0), Vector2(CLOCK.x - 24.0, 30))
		ArenaUi.plate(self, box)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		draw_rect(Rect2(box.position + Vector2(12, 9), Vector2(10, 10)), Color(col, 0.6 + 0.4 * pulse))
		_text(box.position + Vector2(32, 20), MatchEvent.title(ev).to_upper(), col, 16, box.size.x - 40)
		return box.end.y + 2.0

	func _draw_buffs(clock_box: Rect2, top: float) -> void:
		var me: Player = arena._players.get(Net.local_id())
		if not me:
			return
		var buffs: PackedStringArray = []
		for kind in Player.TIMED_BUFFS:
			if me.buffed(kind):
				var label: String = PvpPickup.LABELS[kind]
				if kind == "shield":
					label = "Shield %d" % me.shield_hp
				buffs.append("%s %ds" % [label, ceili(me.buff_left(kind))])
		if not buffs.is_empty():
			var line := "  /  ".join(buffs)
			# no wider than the clock (the kill feed is beside it): a long list wraps
			var width := CLOCK.x - 16.0
			var extent := ArenaUi.BODY.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, width, 16)
			var box := Rect2(Vector2(clock_box.position.x, top), Vector2(CLOCK.x, extent.y + 12.0))
			ArenaUi.plate(self, box)
			draw_multiline_string(ArenaUi.BODY, box.position + Vector2(8, 21), line, HORIZONTAL_ALIGNMENT_CENTER, width, 16, -1, ArenaUi.GOLD)

	func _draw_scores(viewport_width: float) -> void:
		var ids: Array = arena._players.keys()
		var crown_mode: bool = arena._cm
		ids.sort_custom(func(a: int, b: int) -> bool:
			if crown_mode and int(arena._score[a]) != int(arena._score[b]):
				return arena._score[a] > arena._score[b]
			if arena._kills[a] != arena._kills[b]:
				return arena._kills[a] > arena._kills[b]
			if arena._deaths[a] != arena._deaths[b]:
				return arena._deaths[a] < arena._deaths[b]
			return a < b)
		var box := Rect2(viewport_width - WIDTH - 12, 12, WIDTH, 82 + ids.size() * ROW)
		ArenaUi.panel(self, box)
		var middle := box.position.x + WIDTH / 2.0
		for side in [-1.0, 1.0]:   # the title: a pill between two flourishes, as on the menus
			ArenaUi.draw_flourish(self, ArenaUi.SCROLL, Vector2(middle + side * 78.0, box.position.y + 29.0), 2.0, side > 0.0)
		ArenaUi.pill(self, Rect2(middle - 72.0, box.position.y + 10.0, 144, 34))
		draw_string(ArenaUi.DISPLAY, Vector2(middle - 72.0, box.position.y + 32.0), "Standings", HORIZONTAL_ALIGNMENT_CENTER, 144, 20, ArenaUi.SUN)
		_text(box.position + Vector2(166, 63), "PTS" if crown_mode else "KILLS", ArenaUi.MUTED, 16, 48, HORIZONTAL_ALIGNMENT_CENTER)
		_text(box.position + Vector2(220, 63), "KILLS" if crown_mode else "DEATHS", ArenaUi.MUTED, 16, 64, HORIZONTAL_ALIGNMENT_CENTER)
		for i in ids.size():
			var id: int = ids[i]
			var p: Player = arena._players[id]
			var origin := box.position + Vector2(16, 69 + i * ROW)
			var color: Color = Player.TEAM_COLORS[p.team] if p.team >= 0 else Player.NAME_COLORS[p.player_index % Player.NAME_COLORS.size()]
			if id == Net.local_id():
				draw_rect(Rect2(origin, Vector2(WIDTH - 32, ROW - 1.0)), ArenaUi.SLATE)
			draw_rect(Rect2(origin + Vector2(5, 9), Vector2(6, 6)), color)
			var name_width := 130.0
			if id == arena._crown:
				draw_texture_rect(ArenaUi.CROWN, Rect2(origin + Vector2(134, 4), Vector2(16, 16)), false)
				name_width -= 14
			_text(origin + Vector2(18, 17), p.display_name, ArenaUi.INK, 16, name_width)
			var first := str(int(arena._score[id])) if crown_mode else str(arena._kills[id])
			var second := str(arena._kills[id]) if crown_mode else str(arena._deaths[id])
			_text(origin + Vector2(150, 18), first, ArenaUi.GOLD if crown_mode and id == arena._crown else ArenaUi.MOSS, 20, 48, HORIZONTAL_ALIGNMENT_CENTER)
			_text(origin + Vector2(204, 17), second, ArenaUi.MUTED, 16, 64, HORIZONTAL_ALIGNMENT_CENTER)

	func _text(at: Vector2, text: String, color: Color, px: int, width: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
		draw_string(ArenaUi.BODY, at, text, align, width, px, color)

class KillFeed extends Control:
	const LIFE := 6.0
	const MAX := 5
	var _lines: Array[Dictionary] = []

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
			var at := Vector2(12, 12 + i * 36)
			var width := clampf(ArenaUi.BODY.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 54, 125, 425)
			ArenaUi.plate(self, Rect2(at, Vector2(width, 33)), alpha)
			draw_rect(Rect2(at + Vector2(7, 6), Vector2(3, 19)), Color(line.color, alpha))
			draw_texture_rect(ArenaUi.SWORDS, Rect2(at + Vector2(17, 8), Vector2(16, 16)), false, Color(1, 1, 1, alpha))
			draw_string(ArenaUi.BODY, at + Vector2(42, 21), line.text, HORIZONTAL_ALIGNMENT_LEFT, width - 52, 16, Color(ArenaUi.INK, alpha))

## The FIGHT card for the match event (docs §6.5): name + one line under the centre banner, in the event's colour,
## SHOW seconds then a fade. Players pick a plan before the first drop.
class EventCard extends Control:
	const SHOW := 3.5
	const FADE := 0.6
	var _event := MatchEvent.NONE
	var _age := INF

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		mouse_filter = MOUSE_FILTER_IGNORE

	func show_event(id: String) -> void:
		_event = id
		_age = 0.0

	func _process(delta: float) -> void:
		if _age < SHOW + FADE:
			_age += delta
			queue_redraw()

	func _draw() -> void:
		if _event == MatchEvent.NONE or _age >= SHOW + FADE:
			return
		var alpha := 1.0 if _age < SHOW else 1.0 - (_age - SHOW) / FADE
		var pop := clampf(_age / 0.25, 0.0, 1.0)   # slides up into place
		var col := MatchEvent.color(_event)
		var view := get_viewport_rect().size
		var box := Rect2(Vector2(roundf((view.x - 560) * 0.5), view.y * 0.5 + 60.0 + (1.0 - pop) * 30.0), Vector2(560, 92))
		ArenaUi.plate(self, box, alpha)
		draw_rect(Rect2(box.position + Vector2(14, 16), Vector2(6, box.size.y - 34)), Color(col, alpha))
		draw_string(ArenaUi.DISPLAY, box.position + Vector2(34, 40), "EVENT:  " + MatchEvent.title(_event).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, 32, Color(col, alpha))
		draw_string(ArenaUi.BODY, box.position + Vector2(34, 68), MatchEvent.cfg(_event).blurb, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, 16, Color(ArenaUi.INK, alpha))

class Results extends Control:
	var title := ""
	var board: Array[Dictionary] = []   ## every player: name, hero, color, kills, deaths, score (-1 = no points), won, me
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
		var panel := ArenaUi.OrnatePanel.new()
		panel.custom_minimum_size.x = 760
		center.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		var header := HBoxContainer.new()
		header.add_child(ArenaUi.picture(ArenaUi.CROWN, Vector2(48, 48)))
		var winner := ArenaUi.heading(title, 42)
		winner.size_flags_horizontal = SIZE_EXPAND_FILL
		winner.size_flags_vertical = SIZE_SHRINK_CENTER
		winner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		header.add_child(winner)
		box.add_child(header)
		box.add_child(HSeparator.new())
		for entry in board:
			_add_player(box, entry)
		if not board.is_empty():
			box.add_child(HSeparator.new())
		if not rows.is_empty():
			box.add_child(ArenaUi.heading("Match Awards", 19))
			for i in mini(rows.size(), 3 if board.size() > 6 else rows.size()):   # a full lobby: keep it on one screen
				_add_award(box, rows[i])
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(actions)
		var leave := ArenaUi.button("Leave", Net.leave)
		actions.add_child(leave)
		if proceed.is_valid():
			var next := ArenaUi.button(next_label, proceed, true)
			actions.add_child(next)
			ArenaUi.defer_focus(next)
		else:
			actions.add_child(ArenaUi.label("Waiting for the host", 16, ArenaUi.MUTED))
			ArenaUi.defer_focus(leave)

	## One player on the scoreboard: a crown for the winner, the name (gold for you), the hero they played in its own
	## colour, then K / D (and points in Crown mode).
	func _add_player(box: VBoxContainer, e: Dictionary) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		if e.won:
			row.add_child(ArenaUi.picture(ArenaUi.CROWN, Vector2(22, 22)))
		else:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(22, 22)
			row.add_child(gap)
		var who := ArenaUi.label(e.name, 18, ArenaUi.GOLD if e.me else ArenaUi.INK)
		who.size_flags_horizontal = SIZE_EXPAND_FILL
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(who)
		var hero := ArenaUi.label(e.hero, 18, Color(e.color).lightened(0.25))
		hero.custom_minimum_size.x = 170
		row.add_child(hero)
		var kd := "%d / %d" % [e.kills, e.deaths]
		if int(e.score) >= 0:
			kd = "%d pts   %s" % [e.score, kd]
		var stat := ArenaUi.label(kd, 18, ArenaUi.MUTED)
		stat.custom_minimum_size.x = 150
		stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(stat)

	func _add_award(box: VBoxContainer, award: Dictionary) -> void:
		var stripe := PanelContainer.new()
		var tint := StyleBoxFlat.new()
		tint.bg_color = ArenaUi.SLATE
		tint.content_margin_left = 12
		tint.content_margin_right = 12
		tint.content_margin_top = 5
		tint.content_margin_bottom = 5
		stripe.add_theme_stylebox_override("panel", tint)
		box.add_child(stripe)
		var row := HBoxContainer.new()
		stripe.add_child(row)
		var name := ArenaUi.label(award.title, 18, ArenaUi.SUN)
		name.custom_minimum_size.x = 176
		row.add_child(name)
		var player := ArenaUi.label(award.who, 18)
		player.size_flags_horizontal = SIZE_EXPAND_FILL
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(player)
		var detail := ArenaUi.label(award.detail, 16, ArenaUi.MUTED)
		detail.custom_minimum_size.x = 246
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(detail)
