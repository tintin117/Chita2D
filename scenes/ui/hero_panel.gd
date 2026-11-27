class_name HeroPanel extends Control
## Combat HUD. PvE also displays character progression and gear.
## Positions itself (bottom-left, or bottom-right when mirror). Hud.add_player creates one per player.
## The contents are laid out from PAD inwards, inside the ornate frame.

const SIZE_PX := Vector2(438, 132)
const PAD := Vector2(6, 8)
const ULT_EXTRA := 86.0   ## the panel grows by one skill column for a hero with an ult, and one more for a passive
const PASSIVE_COLOR := ArenaUi.PASSIVE_COLOR
const ULT_COLOR := ArenaUi.ULT_COLOR
const GOLD := ArenaUi.GOLD
const BAR := Rect2(98, 45, 154, 20)
const SLOT := 48.0
const SLOT_POS := Vector2(272, 25)
const SKILL_COLUMN_WIDTH := 84.0   ## "Connection" fits on one line
const SKILL_COLUMN_GAP := 2.0
const TIP_WIDTH := 340.0
var player: Player
var mirror := false
var _portrait: Texture2D
var _gear_icons: Array[Texture2D] = []
var _shown := -1.0   ## HP the damage tail has drained down to
var _hooked := false

func _ready() -> void:
	size = (SIZE_PX if player.online else SIZE_PX + Vector2(0, 10)) + PAD * 2.0
	if player.spells.size() > Player.ULT_SLOT or player.hero.ult_skill != "" or _drop_kit():
		size.x += ULT_EXTRA
	if player.hero.passive_name != "" or _drop_kit():
		size.x += ULT_EXTRA
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot: String in Item.SLOTS:
		_gear_icons.append(ArenaUi.gear_icon(slot))

## Index into columns() of the skill tile under `at` (panel coordinates), -1 when there is none.
func column_at(at: Vector2) -> int:
	for c in columns().size():
		if column_rect(c).has_point(at - PAD):
			return c
	return -1

## Hovering a skill tile opens its details above the panel, centred on that tile and kept on screen (Godot's own
## tooltip opens at the cursor and runs off the bottom of the screen).
func _draw_tooltip() -> void:
	var c := column_at(get_local_mouse_position())
	if c < 0:
		return
	var text := skill_detail(columns()[c])
	var f := ArenaUi.BODY
	var width := TIP_WIDTH - 40.0
	var body := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, 16)
	var x := clampf(PAD.x + column_rect(c).get_center().x - TIP_WIDTH / 2.0, 8.0 - position.x,
		get_viewport_rect().size.x - position.x - TIP_WIDTH - 8.0)
	var height := maxf(body.y + 32.0, 64.0)   # the ornate frame needs 64
	var box := Rect2(roundf(x), -height - 6.0, TIP_WIDTH, height)
	ArenaUi.panel(self, box)
	draw_multiline_string(f, box.position + Vector2(20, 16 + f.get_ascent(16)), text, HORIZONTAL_ALIGNMENT_LEFT, width, 16, -1, ArenaUi.INK)

## Key, name and text of a column from columns(); a held weapon replaces the skill it covers.
func skill_detail(column: Variant) -> String:
	var slot: int = 2 if column is String else (3 if column == Player.ULT_SLOT else column)
	var key := ArenaUi.skill_key(slot, 0 if player.online else player.player_index)
	if slot < 2 and player.weapon_active(slot):
		var w: FsWeapon = player.weapons[slot]
		return "%s  /  %s\nHeld weapon: %d uses left, %d s." % [key, w.display_name, w.uses, ceili(w.seconds_left())]
	var info := ArenaUi.skill_info(player.hero, slot)
	var text := "%s  /  %s\n%s" % [key, info[0], info[1]]
	if slot == 1:
		text += "\nCooldown: %.1f s" % player.spells[slot].cooldown
	return text

## A skill tile's box, in content coordinates (PAD inside the panel).
func column_rect(c: int) -> Rect2:
	return Rect2(SLOT_POS + Vector2(c * (SKILL_COLUMN_WIDTH + SKILL_COLUMN_GAP), 0), Vector2(SLOT, SLOT))

func _process(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	position = Vector2(vp.x - size.x - 16.0 if mirror else 16.0, vp.y - size.y - 12.0).round()
	if not is_instance_valid(player):
		return
	if not _hooked and player.prog != null:
		_hooked = true
		player.prog.leveled_up.connect(func(lv: int) -> void: LevelUpPicker.request(get_tree(), player, lv))
	if _shown < player.hp:
		_shown = player.hp
	else:
		_shown = move_toward(_shown, player.hp, player.max_hp * 0.5 * delta)
	queue_redraw()

func _text(pos: Vector2, s: String, px: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := ArenaUi.BODY
	draw_string_outline(f, pos, s, align, width, px, 3, ArenaUi.SHADE)
	draw_string(f, pos, s, align, width, px, col)

## Text centred under a tile, as wide as its column.
func _under_slot(slot: Rect2, y: float, s: String, col: Color) -> void:
	_text(Vector2(slot.get_center().x - SKILL_COLUMN_WIDTH / 2.0, slot.position.y + y), s, 16, col, HORIZONTAL_ALIGNMENT_CENTER, SKILL_COLUMN_WIDTH)

func _draw() -> void:
	if not is_instance_valid(player) or player.prog == null:
		return
	ArenaUi.panel(self, Rect2(Vector2.ZERO, size))
	draw_set_transform(PAD)
	_text(Vector2(98, 34), player.hero.display_name, 24, ArenaUi.INK)
	_draw_portrait()
	_draw_hp()
	_draw_dash()
	_draw_skills()
	if not player.online:
		_draw_progression()
	draw_set_transform(Vector2.ZERO)
	_draw_tooltip()

func _draw_portrait() -> void:
	if _portrait == null:
		var color: String = Player.TEAM_SPRITES[player.team] if player.team >= 0 else Player.COLORS[player.player_index % Player.COLORS.size()]
		_portrait = ArenaUi.portrait(player.hero, color)
	var box := Rect2(14, 16, 72, 72)
	var tint := Color(0.42, 0.42, 0.42) if player.down else Color.WHITE
	ArenaUi.frame(self, box.grow(3), &"Button")
	draw_texture_rect(_portrait, box, false, tint)
	if not player.online:
		_text(Vector2(14, 108), "LV %d" % player.prog.level, 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 72.0)

func _draw_progression() -> void:
	var need := player.prog.xp_to_next()
	var ratio := 1.0 if need == 0 else float(player.prog.xp) / need
	var track := Rect2(98, 113, 154, 4)
	draw_rect(track, ArenaUi.SLATE)
	draw_rect(Rect2(track.position, Vector2(track.size.x * ratio, track.size.y)), Color("#8ecad1"))
	_text(Vector2(98, 108), "XP MAX" if need == 0 else "XP %d / %d" % [player.prog.xp, need], 16, ArenaUi.MUTED)
	for i in Item.SLOTS.size():
		var slot := Rect2(14 + i * 24, 114, 20, 20)
		var item: Item = player.equipment.get(Item.SLOTS[i])
		draw_rect(slot, ArenaUi.SLATE)
		draw_texture_rect(_gear_icons[i], slot.grow(-2), false, Color.WHITE if item else Color(1, 1, 1, 0.3))
		draw_rect(slot, item.color() if item else ArenaUi.EDGE, false, 1.0)
	if player.prog.skill_points > 0:
		_text(Vector2(98, 133), "Skill points: %d  [Tab]" % player.prog.skill_points, 16, ArenaUi.MOSS)

func _draw_hp() -> void:
	var ratio := clampf(float(player.hp) / player.max_hp, 0.0, 1.0)
	ArenaUi.plate(self, BAR.grow(3))
	var tail := clampf(_shown / player.max_hp, 0.0, 1.0)
	draw_rect(Rect2(BAR.position, Vector2(roundf(BAR.size.x * tail), BAR.size.y)), GOLD)
	var color := Color("#5f9e4a") if ratio > 0.5 else (Color("#b8862f") if ratio > 0.25 else ArenaUi.DANGER)
	draw_rect(Rect2(BAR.position, Vector2(roundf(BAR.size.x * ratio), BAR.size.y)), color)
	var text := "DOWN" if player.down else "%d / %d" % [player.hp, player.max_hp]
	_text(BAR.position + Vector2(0, 15), text, 16, ArenaUi.INK, HORIZONTAL_ALIGNMENT_CENTER, BAR.size.x)

func _draw_dash() -> void:
	_text(Vector2(98, 90), "DASH", 16, ArenaUi.MUTED)
	for i in Player.MAX_DASH:
		var pos := Vector2(146 + i * 21, 77)
		var pip := Rect2(pos, Vector2(16, 13))
		draw_rect(pip, ArenaUi.EDGE)
		draw_rect(pip.grow(-2), Color("#8ecad1") if i < player.dash_charges else ArenaUi.NIGHT)

## The kit as the player knows it: LMB, RMB, PASSIVE (no button), ULT. Column -> what it shows.
func columns() -> Array:
	var out: Array = [0, 1]
	if player.hero.passive_name != "" or _drop_kit():
		out.append("passive")
	if player.spells.size() > Player.ULT_SLOT or _drop_kit():
		out.append(Player.ULT_SLOT)
	return out

## Friendslop's Bonker: the passive and ult columns are always there, empty until a drop fills them (FsLoot).
func _drop_kit() -> bool:
	return player.hero != null and player.hero.id == "bonker"

## An empty drop slot: a dim tile with a dash, captioned "find a drop".
func _draw_empty(r: Rect2, color: Color) -> void:
	draw_rect(r.grow(-4), Color(color, 0.06))
	_text(r.position + Vector2(0, 30), "-", 20, Color(color, 0.5), HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	draw_rect(r.grow(-4), Color(color, 0.3), false, 2.0)
	_draw_skill_caption(r, "find a drop", ArenaUi.MUTED)

func _draw_skills() -> void:
	var hints: Array = Hud.HINTS[0 if player.online else player.player_index % 2]
	var cols := columns()
	for c in cols.size():
		var r := column_rect(c)
		ArenaUi.plate(self, r.grow(3))
		if cols[c] is String:
			_draw_passive(r)
			_under_slot(r, SLOT + 18, "PASSIVE", ArenaUi.MUTED)
			continue
		var i: int = cols[c]
		if i == Player.ULT_SLOT:
			_draw_ult(r)
			_under_slot(r, SLOT + 18, hints[i], ArenaUi.INK)
			continue
		var spell: Spell = player.spells[i] if i < player.spells.size() else null
		if spell:
			draw_texture_rect(ArenaUi.skill_icon(player.hero, i), Rect2(r.position + Vector2(8, 8), Vector2(32, 32)), false)
			if not player.weapon_active(i):
				_draw_skill_caption(r, spell.display_name, ArenaUi.MUTED)
			var cd := player.cooldowns[i]
			if cd > 0.0:
				var frac := clampf(cd / maxf(player.cooldown_max[i], 0.01), 0.0, 1.0)
				draw_rect(Rect2(r.position, Vector2(SLOT, roundf(SLOT * frac))), Color(0, 0, 0, 0.7))
				if player.cooldown_max[i] >= 2.0:
					_text(r.position + Vector2(0, 31), str(ceili(cd)) if cd >= 1.0 else "%.1f" % cd, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
			if not player.online:
				for k in player.prog.ranks[i]:
					draw_rect(Rect2(r.position + Vector2(5 + k * 8, SLOT - 8), Vector2(6, 4)), GOLD)
				if player.prog.can_rank_up(i):
					_text(r.position + Vector2(SLOT - 17, 15), "+", 16, ArenaUi.MOSS, HORIZONTAL_ALIGNMENT_CENTER, 16.0)
		_draw_weapon(i, r)
		_under_slot(r, SLOT + 18, hints[i], ArenaUi.INK)

## The ult: no icon sheet row for it yet, so a charge bar filling the slot from the bottom; it pulses once ready.
func _draw_ult(r: Rect2) -> void:
	if player.spells.size() <= Player.ULT_SLOT or player.ult_slot_empty():
		_draw_empty(r, ULT_COLOR)
		return
	var spell: Spell = player.spells[Player.ULT_SLOT]
	var frac := player.ult_fraction()
	var full := player.ult_ready()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	var inner := r.grow(-3)
	var fill := roundf(inner.size.y * frac)
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - fill), Vector2(inner.size.x, fill)), Color(ULT_COLOR, 0.85 if full else 0.45))
	_text(r.position + Vector2(0, 30), "ULT" if full else "%d%%" % int(frac * 100.0), 16,
		Color.WHITE if full else ArenaUi.INK, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	if full:
		draw_rect(r, Color(ULT_COLOR, 0.6 + 0.4 * pulse), false, 3.0)
	_draw_skill_caption(r, spell.display_name, ULT_COLOR if full else ArenaUi.MUTED)

## The passive: no button and no cooldown, so a gold-edged tile with its initials; it lights up while it is doing
## something you can see (Ranger: Steady Aim doubling the draw right now).
func _draw_passive(r: Rect2) -> void:
	var h := player.hero
	if h.passive_name == "":
		_draw_empty(r, PASSIVE_COLOR)
		return
	var lit := (h.steady_aim and player.charge_show > 0.0 and player.draw_rate() > 1.0) or player.passive_lit()   # Stalk faded, a wave ready, Fiendform...
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	var words := h.passive_name.split(" ")
	var initials := ""
	for w in words:
		if w != "":
			initials += w[0]
	draw_rect(r.grow(-4), Color(PASSIVE_COLOR, 0.35 + 0.35 * pulse) if lit else Color(PASSIVE_COLOR, 0.12))
	_text(r.position + Vector2(0, 31), "67" if h.lives_67 else initials.to_upper(), 20, Color.WHITE if lit else PASSIVE_COLOR, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	if lit and h.steady_aim:
		_text(r.position + Vector2(0, 45), "x2", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	if h.lives_67 and player._lives_cd > 0.0:   # 67 Lives has a wait: shown like a skill cooldown
		var lcd: float = player._lives_cd
		draw_rect(Rect2(r.position, Vector2(SLOT, roundf(SLOT * clampf(lcd / Player.LIVES_CD, 0.0, 1.0)))), Color(0, 0, 0, 0.7))
		_text(r.position + Vector2(0, 31), str(ceili(lcd)), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	if h.tide_wave and player._wave_cd > 0.0:   # Tide Breaker has a wait: shown like a skill cooldown
		var cd: float = player._wave_cd
		var frac := clampf(cd / Player.WAVE_CD, 0.0, 1.0)
		draw_rect(Rect2(r.position, Vector2(SLOT, roundf(SLOT * frac))), Color(0, 0, 0, 0.7))
		_text(r.position + Vector2(0, 31), str(ceili(cd)) if cd >= 1.0 else "%.1f" % cd, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	draw_rect(r.grow(-2), Color(PASSIVE_COLOR, 0.6 + 0.4 * pulse) if lit else Color(PASSIVE_COLOR, 0.7), false, 2.0)
	_draw_skill_caption(r, h.passive_name, PASSIVE_COLOR if lit else ArenaUi.MUTED)

func _draw_skill_caption(slot: Rect2, caption: String, color: Color) -> void:
	var at := slot.end + Vector2(-(SLOT + SKILL_COLUMN_WIDTH) * 0.5, 35)
	if caption.count(" ") == 1:
		caption = caption.replace(" ", "\n")   # a word a line: two names side by side never read as one
	draw_multiline_string(ArenaUi.BODY, at, caption, HORIZONTAL_ALIGNMENT_CENTER, SKILL_COLUMN_WIDTH, 16, 2, color,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)

## The held weapon covers the slot with its icon, uses left and lifetime bar.
func _draw_weapon(i: int, r: Rect2) -> void:
	if not player.weapon_active(i):
		return
	var w: FsWeapon = player.weapons[i]
	var col := PvpPickup.tier_color(w.id)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	draw_rect(r, Color(ArenaUi.NIGHT, 0.97))
	draw_rect(r.grow(-3), Color(PvpPickup.COLORS[w.id], 0.35))
	_text(r.position + Vector2(0, 27), PvpPickup.ICONS[w.id], 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	_text(r.position + Vector2(0, 45), "x%d" % w.uses, 16, Color(1, 0.95, 0.6), HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	var left := clampf(w.seconds_left() / w.time, 0.0, 1.0)
	draw_rect(Rect2(r.position + Vector2(0, -8), Vector2(SLOT, 5)), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(r.position + Vector2(0, -8), Vector2(SLOT * left, 5)), Color(col, 0.7 + 0.3 * pulse) if left > 0.25 else Color(1, 0.3, 0.2, 0.6 + 0.4 * pulse))
	draw_rect(r, Color(col, 0.7 + 0.3 * pulse), false, 3.0)
	_draw_skill_caption(r, "%s %ds" % [w.display_name, ceili(w.seconds_left())], col)
