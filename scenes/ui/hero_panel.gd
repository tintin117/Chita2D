class_name HeroPanel extends Control
## Per-hero HUD: portrait + level badge, XP, HP bar with damage tail, gear, dash pips and the two skill slots (LMB basic, RMB signature).
## Positions itself (bottom-left, or bottom-right when mirror). Hud.add_player creates one per player.

const SIZE_PX := Vector2(482, 148)
const GOLD := ArenaUi.GOLD
const BAR := Rect2(108, 57, 194, 24)
const SLOT := 56.0
const SLOT_POS := Vector2(332, 45)
var player: Player
var mirror := false
var _portrait: Texture2D
var _gear_icons: Array[Texture2D] = []
var _shown := -1.0   ## HP the damage tail has drained down to
var _hooked := false

func _ready() -> void:
	size = SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot: String in Item.SLOTS:
		_gear_icons.append(ArenaUi.gear_icon(slot))

func _process(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	position = Vector2(vp.x - size.x - 20.0 if mirror else 20.0, vp.y - size.y - 16.0)
	if is_instance_valid(player):
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
	draw_string_outline(f, pos, s, align, width, px, 2, ArenaUi.SHADE)
	draw_string(f, pos, s, align, width, px, col)

func _draw() -> void:
	if not is_instance_valid(player) or player.prog == null:
		return
	ArenaUi.panel(self, Rect2(Vector2.ZERO, size))
	_text(Vector2(108, 37), player.hero.display_name, 23, GOLD)
	_draw_portrait()
	_draw_xp()
	_draw_hp()
	_draw_gear_and_dash()
	_draw_skills()

func _draw_portrait() -> void:
	if _portrait == null:
		_portrait = ArenaUi.portrait(player.hero.id)
	var box := Rect2(20, 25, 76, 86)
	var tint := Color(0.46, 0.5, 0.46) if player.down else Color.WHITE
	draw_texture_rect(_portrait, box, false, tint)
	draw_rect(box, GOLD, false, 1.0)
	var badge := Rect2(24, 107, 68, 21)
	draw_rect(badge, ArenaUi.SHADE)
	draw_rect(badge, GOLD, false, 1.0)
	_text(badge.position + Vector2(0, 15), "LV %d" % player.prog.level, 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x)

func _draw_xp() -> void:
	var need := player.prog.xp_to_next()
	var r := Rect2(BAR.position.x, 88, BAR.size.x, 4)
	_text(Vector2(BAR.position.x, 49), "XP MAX" if need == 0 else "XP %d / %d" % [player.prog.xp, need], 12, ArenaUi.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, BAR.size.x)
	draw_rect(r, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(r.position, Vector2(r.size.x * (1.0 if need == 0 else float(player.prog.xp) / need), r.size.y)), Color(0.45, 0.7, 1.0))

func _draw_hp() -> void:
	var ratio := clampf(float(player.hp) / player.max_hp, 0.0, 1.0)
	draw_rect(BAR.grow(2), Color(0.05, 0.04, 0.04, 0.95))
	var tail := clampf(_shown / player.max_hp, 0.0, 1.0)
	draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * tail, BAR.size.y)), Color(1.0, 0.85, 0.5))
	var col := Color("#6eaa52") if ratio > 0.5 else (Color(0.95, 0.6, 0.15) if ratio > 0.25 else Color(0.9, 0.2, 0.2))
	draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * ratio, BAR.size.y)), col)
	draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * ratio, BAR.size.y * 0.4)), Color(1, 1, 1, 0.14))
	draw_rect(BAR.grow(2), GOLD * 0.85, false, 2.0)
	_text(BAR.position + Vector2(0, 19), "DOWN" if player.down else "%d / %d" % [player.hp, player.max_hp], 15, Color.WHITE if not player.down else Color(1, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, BAR.size.x)

func _draw_gear_and_dash() -> void:
	for i in Item.SLOTS.size():
		var g := Rect2(108 + i * 29, 101, 22, 22)
		var it: Item = player.equipment.get(Item.SLOTS[i])
		draw_rect(g, Color(0, 0, 0, 0.6))
		draw_texture_rect(_gear_icons[i], g.grow(-2), false, Color.WHITE if it else Color(1, 1, 1, 0.25))
		draw_rect(g, it.color() if it else Color(0.4, 0.4, 0.4), false, 2.0)
	for i in Player.MAX_DASH:
		var c := Vector2(264 + i * 21, 111)
		draw_circle(c, 8, Color(0, 0, 0, 0.7))
		if i < player.dash_charges:
			draw_circle(c, 6, Color(0.5, 0.85, 1.0))
	if player.prog.skill_points > 0:
		_text(Vector2(108, 138), "Skill points: %d   [Tab]" % player.prog.skill_points, 12, Color(0.5, 1, 0.5))

func _draw_skills() -> void:
	var hints: Array = Hud.HINTS[0 if player.online else player.player_index % 2]
	for i in 2:
		var r := Rect2(SLOT_POS + Vector2(i * (SLOT + 16.0), 0), Vector2(SLOT, SLOT))
		draw_rect(r, ArenaUi.SHADE)
		var spell: Spell = player.spells[i] if i < player.spells.size() else null
		var border := GOLD
		if spell:
			draw_texture_rect(ArenaUi.skill_icon(player.hero, i), r.grow(-5), false)
			if not player.weapon_active(i):
				_text(r.position + Vector2(-10, SLOT + 29), spell.display_name, 11, ArenaUi.MUTED, HORIZONTAL_ALIGNMENT_CENTER, SLOT + 20.0)
			var cd := player.cooldowns[i]
			if cd > 0.0:
				var frac := clampf(cd / maxf(player.cooldown_max[i], 0.01), 0.0, 1.0)
				draw_rect(Rect2(r.position, Vector2(SLOT, SLOT * frac)), Color(0, 0, 0, 0.7))
				if player.cooldown_max[i] >= 2.0:
					_text(r.position + Vector2(0, 33), str(ceili(cd)) if cd >= 1.0 else "%.1f" % cd, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
			for k in player.prog.ranks[i]:   # rank pips
				draw_rect(Rect2(r.position + Vector2(5 + k * 8, SLOT - 8), Vector2(6, 4)), GOLD)
			if player.prog.can_rank_up(i):
				draw_circle(r.position + Vector2(SLOT - 9, 9), 8, Color(0.2, 0.6, 0.25))
				_text(r.position + Vector2(SLOT - 17, 15), "+", 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 16.0)
		draw_rect(r, border, false, 2.0)
		_draw_weapon(i, r)
		_text(r.position + Vector2(0, SLOT + 14), hints[i], 13, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_CENTER, SLOT)

## Friendslop: the weapon held in slot i covers the slot with its tier colour, icon, uses left and a time bar; its name sits above.
func _draw_weapon(i: int, r: Rect2) -> void:
	if not player.weapon_active(i):
		return
	var w: FsWeapon = player.weapons[i]
	var col := PvpPickup.tier_color(w.id)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	draw_rect(r, Color(0.06, 0.06, 0.09, 0.97))
	draw_rect(r.grow(-3), Color(PvpPickup.COLORS[w.id], 0.35))
	_text(r.position + Vector2(0, 28), PvpPickup.ICONS[w.id], 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	_text(r.position + Vector2(0, 46), "x%d" % w.uses, 15, Color(1, 0.95, 0.6), HORIZONTAL_ALIGNMENT_CENTER, SLOT)
	var left := clampf(w.seconds_left() / w.time, 0.0, 1.0)
	draw_rect(Rect2(r.position + Vector2(0, -7), Vector2(SLOT, 5)), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(r.position + Vector2(0, -7), Vector2(SLOT * left, 5)), Color(col, 0.7 + 0.3 * pulse) if left > 0.25 else Color(1, 0.3, 0.2, 0.6 + 0.4 * pulse))
	draw_rect(r, Color(col, 0.7 + 0.3 * pulse), false, 3.0)
	_text(r.position + Vector2(SLOT * 0.5 - 70.0, -13 - i * 13), "%s  %ds" % [w.display_name, ceili(w.seconds_left())], 12, col, HORIZONTAL_ALIGNMENT_CENTER, 140.0)
