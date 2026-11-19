class_name HeroPanel extends Control
## Combat HUD. PvE also displays character progression and gear.
## Positions itself (bottom-left, or bottom-right when mirror). Hud.add_player creates one per player.

const SIZE_PX := Vector2(422, 114)
const GOLD := ArenaUi.GOLD
const BAR := Rect2(98, 45, 154, 20)
const SLOT := 48.0
const SLOT_POS := Vector2(276, 25)
var player: Player
var mirror := false
var _portrait: Texture2D
var _gear_icons: Array[Texture2D] = []
var _shown := -1.0   ## HP the damage tail has drained down to
var _hooked := false

func _ready() -> void:
	size = SIZE_PX if player.online else SIZE_PX + Vector2(0, 28)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot: String in Item.SLOTS:
		_gear_icons.append(ArenaUi.gear_icon(slot))

func _process(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	position = Vector2(vp.x - size.x - 20.0 if mirror else 20.0, vp.y - size.y - 16.0).round()
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
	draw_string_outline(f, pos, s, align, width, px, 2, ArenaUi.SHADE)
	draw_string(f, pos, s, align, width, px, col)

func _draw() -> void:
	if not is_instance_valid(player) or player.prog == null:
		return
	ArenaUi.panel(self, Rect2(Vector2.ZERO, size))
	_text(Vector2(98, 34), player.hero.display_name, 22, ArenaUi.INK)
	_draw_portrait()
	_draw_hp()
	_draw_dash()
	_draw_skills()
	if not player.online:
		_draw_progression()

func _draw_portrait() -> void:
	if _portrait == null:
		var color: String = Player.TEAM_SPRITES[player.team] if player.team >= 0 else Player.COLORS[player.player_index % Player.COLORS.size()]
		_portrait = ArenaUi.portrait(player.hero, color)
	var box := Rect2(14, 16, 72, 72)
	var tint := Color(0.42, 0.5, 0.54) if player.down else Color.WHITE
	draw_rect(box, ArenaUi.SLATE)
	draw_texture_rect(_portrait, box, false, tint)
	draw_rect(box, ArenaUi.EDGE, false, 2.0)
	if not player.online:
		_text(Vector2(14, 108), "LV %d" % player.prog.level, 15, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 72.0)

func _draw_progression() -> void:
	var need := player.prog.xp_to_next()
	var ratio := 1.0 if need == 0 else float(player.prog.xp) / need
	var track := Rect2(98, 113, 154, 4)
	draw_rect(track, ArenaUi.NIGHT)
	draw_rect(Rect2(track.position, Vector2(track.size.x * ratio, track.size.y)), Color("#8ecad1"))
	_text(Vector2(98, 108), "XP MAX" if need == 0 else "XP %d / %d" % [player.prog.xp, need], 14, ArenaUi.MUTED)
	for i in Item.SLOTS.size():
		var slot := Rect2(14 + i * 24, 114, 20, 20)
		var item: Item = player.equipment.get(Item.SLOTS[i])
		draw_rect(slot, ArenaUi.SLATE)
		draw_texture_rect(_gear_icons[i], slot.grow(-2), false, Color.WHITE if item else Color(1, 1, 1, 0.3))
		draw_rect(slot, item.color() if item else ArenaUi.EDGE, false, 1.0)
	if player.prog.skill_points > 0:
		_text(Vector2(98, 133), "Skill points: %d  [Tab]" % player.prog.skill_points, 14, ArenaUi.MOSS)

func _draw_hp() -> void:
	var ratio := clampf(float(player.hp) / player.max_hp, 0.0, 1.0)
	draw_rect(BAR.grow(2), ArenaUi.NIGHT)
	var tail := clampf(_shown / player.max_hp, 0.0, 1.0)
	draw_rect(Rect2(BAR.position, Vector2(roundf(BAR.size.x * tail), BAR.size.y)), GOLD)
	var color := ArenaUi.MOSS if ratio > 0.5 else (GOLD if ratio > 0.25 else ArenaUi.DANGER)
	draw_rect(Rect2(BAR.position, Vector2(roundf(BAR.size.x * ratio), BAR.size.y)), color)
	draw_rect(BAR.grow(2), ArenaUi.EDGE, false, 2.0)
	var text := "DOWN" if player.down else "%d / %d" % [player.hp, player.max_hp]
	_text(BAR.position + Vector2(0, 15), text, 16, ArenaUi.INK, HORIZONTAL_ALIGNMENT_CENTER, BAR.size.x)

func _draw_dash() -> void:
	_text(Vector2(98, 89), "DASH", 15, ArenaUi.MUTED)
	for i in Player.MAX_DASH:
		var pos := Vector2(144 + i * 21, 76)
		var pip := Rect2(pos, Vector2(16, 13))
		draw_rect(pip, ArenaUi.EDGE)
		draw_rect(pip.grow(-2), Color("#8ecad1") if i < player.dash_charges else ArenaUi.NIGHT)

func _draw_skills() -> void:
	var hints: Array = Hud.HINTS[0 if player.online else player.player_index % 2]
	for i in 2:
		var r := Rect2(SLOT_POS + Vector2(i * (SLOT + 16.0), 0), Vector2(SLOT, SLOT))
		draw_rect(r, ArenaUi.SHADE)
		var spell: Spell = player.spells[i] if i < player.spells.size() else null
		var border := ArenaUi.EDGE
		if spell:
			draw_texture_rect(ArenaUi.skill_icon(player.hero, i), Rect2(r.position + Vector2(8, 8), Vector2(32, 32)), false)
			if not player.weapon_active(i):
				_text(r.position + Vector2(-12, SLOT + 34), spell.display_name, 13, ArenaUi.MUTED, HORIZONTAL_ALIGNMENT_CENTER, SLOT + 24.0)
			var cd := player.cooldowns[i]
			if cd > 0.0:
				var frac := clampf(cd / maxf(player.cooldown_max[i], 0.01), 0.0, 1.0)
				draw_rect(Rect2(r.position, Vector2(SLOT, roundf(SLOT * frac))), Color(0, 0, 0, 0.7))
				if player.cooldown_max[i] >= 2.0:
					_text(r.position + Vector2(0, 33), str(ceili(cd)) if cd >= 1.0 else "%.1f" % cd, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
			if not player.online:
				for k in player.prog.ranks[i]:
					draw_rect(Rect2(r.position + Vector2(5 + k * 8, SLOT - 8), Vector2(6, 4)), GOLD)
				if player.prog.can_rank_up(i):
					_text(r.position + Vector2(SLOT - 17, 15), "+", 14, ArenaUi.MOSS, HORIZONTAL_ALIGNMENT_CENTER, 16.0)
		draw_rect(r, border, false, 2.0)
		_draw_weapon(i, r)
		_text(r.position + Vector2(0, SLOT + 17), hints[i], 15, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_CENTER, SLOT)

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
	_text(r.position + Vector2(-12, SLOT + 34), "%s %ds" % [w.display_name, ceili(w.seconds_left())], 12, col, HORIZONTAL_ALIGNMENT_CENTER, SLOT + 24.0)
