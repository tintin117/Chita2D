class_name HeroPanel extends Control
## Per-hero HUD: portrait + level badge, XP, HP bar with damage tail, gear, dash pips and the two skill slots (LMB basic, RMB signature).
## Positions itself (bottom-left, or bottom-right when mirror). Hud.add_player creates one per player.

const SIZE_PX := Vector2(480, 124)
const GOLD := Color(0.9, 0.75, 0.4)
const BAR := Rect2(88, 38, 250, 26)
const SLOT := 52.0
const SLOT_POS := Vector2(352, 50)
const GEAR_ICONS := {
	"weapon": preload("res://assets/tiny_swords/ui/Icon_05.png"),
	"armor": preload("res://assets/tiny_swords/ui/Icon_06.png"),
	"trinket": preload("res://assets/tiny_swords/ui/Icon_03.png"),
}

var player: Player
var mirror := false
var _portrait: Texture2D
var _shown := -1.0   ## HP the damage tail has drained down to
var _hooked := false

func _ready() -> void:
	size = SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, px, 4, Color.BLACK)
	draw_string(f, pos, s, align, width, px, col)

func _draw() -> void:
	if not is_instance_valid(player) or player.prog == null:
		return
	_draw_portrait()
	_draw_xp()
	_draw_hp()
	_draw_gear_and_dash()
	_draw_skills()

func _draw_portrait() -> void:
	if _portrait == null:
		_portrait = player.hero.portrait(Player.COLORS[player.player_index % Player.COLORS.size()])
	var box := Rect2(6, 34, 70, 70)
	draw_rect(box, Color(0.08, 0.09, 0.11, 0.9))
	var tint := Color(0.45, 0.45, 0.45) if player.down else player.hero.tint
	if _portrait is AtlasTexture:   # crop the empty margin around the sprite
		var r := (_portrait as AtlasTexture).region
		draw_texture_rect_region((_portrait as AtlasTexture).atlas, box, Rect2(r.position + r.size * 0.2, r.size * 0.6), tint)
	else:
		draw_texture_rect(_portrait, box, false, tint)
	draw_rect(box, GOLD, false, 2.0)
	# level badge: gold-edged diamond overlapping the portrait's corner
	var c := Vector2(14, 102)
	var pts := PackedVector2Array([c + Vector2(0, -24), c + Vector2(24, 0), c + Vector2(0, 24), c + Vector2(-24, 0)])
	draw_colored_polygon(pts, Color(0.1, 0.1, 0.13))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), GOLD, 2.5)
	_text(c + Vector2(-20, 8), str(player.prog.level), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	if player.prog.skill_points > 0:
		draw_circle(c + Vector2(20, -18), 10, Color(0.2, 0.6, 0.25))
		_text(c + Vector2(10, -12), "+%d" % player.prog.skill_points, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 20.0)

func _draw_xp() -> void:
	var need := player.prog.xp_to_next()
	_text(Vector2(BAR.position.x, 28), "XP  MAX" if need == 0 else "XP  %d / %d" % [player.prog.xp, need], 13, Color(0.7, 0.85, 1.0))
	var r := Rect2(BAR.position.x, 31, BAR.size.x, 4)
	draw_rect(r, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(r.position, Vector2(r.size.x * (1.0 if need == 0 else float(player.prog.xp) / need), r.size.y)), Color(0.45, 0.7, 1.0))

func _draw_hp() -> void:
	var ratio := clampf(float(player.hp) / player.max_hp, 0.0, 1.0)
	draw_rect(BAR.grow(2), Color(0.05, 0.04, 0.04, 0.95))
	var tail := clampf(_shown / player.max_hp, 0.0, 1.0)
	draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * tail, BAR.size.y)), Color(1.0, 0.85, 0.5))
	var col := Color(0.35, 0.8, 0.3) if ratio > 0.5 else (Color(0.95, 0.6, 0.15) if ratio > 0.25 else Color(0.9, 0.2, 0.2))
	draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * ratio, BAR.size.y)), col)
	draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * ratio, BAR.size.y * 0.4)), Color(1, 1, 1, 0.14))
	draw_rect(BAR.grow(2), GOLD * 0.85, false, 2.0)
	_text(BAR.position + Vector2(0, 19), "DOWN" if player.down else "%d / %d" % [player.hp, player.max_hp], 15, Color.WHITE if not player.down else Color(1, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, BAR.size.x)

func _draw_gear_and_dash() -> void:
	for i in Item.SLOTS.size():
		var g := Rect2(88 + i * 32, 74, 26, 26)
		var it: Item = player.equipment.get(Item.SLOTS[i])
		draw_rect(g, Color(0, 0, 0, 0.6))
		draw_texture_rect(GEAR_ICONS[Item.SLOTS[i]], g.grow(-2), false, Color.WHITE if it else Color(1, 1, 1, 0.25))
		draw_rect(g, it.color() if it else Color(0.4, 0.4, 0.4), false, 2.0)
	for i in Player.MAX_DASH:
		var c := Vector2(224 + i * 22, 87)
		draw_circle(c, 8, Color(0, 0, 0, 0.7))
		if i < player.dash_charges:
			draw_circle(c, 6, Color(0.5, 0.85, 1.0))
	if player.prog.skill_points > 0:
		_text(Vector2(88, 118), "Skill points: %d   [Tab]" % player.prog.skill_points, 12, Color(0.5, 1, 0.5))

func _draw_skills() -> void:
	var hints: Array = Hud.HINTS[0 if player.online else player.player_index % 2]
	for i in 2:
		var r := Rect2(SLOT_POS + Vector2(i * (SLOT + 6.0), 0), Vector2(SLOT, SLOT))
		draw_rect(r, Color(0.07, 0.07, 0.09, 0.92))
		var spell: Spell = player.spells[i] if i < player.spells.size() else null
		var border := GOLD
		if spell:
			_text(r.position + Vector2(0, 33), spell.display_name.substr(0, 1), 26, Color(1, 0.85, 0.5), HORIZONTAL_ALIGNMENT_CENTER, SLOT)
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
		_text(r.position + Vector2(0, SLOT + 16), hints[i], 12, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_CENTER, SLOT)

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
	_text(r.position + Vector2(SLOT * 0.5 - 70.0, -12 - i * 14), "%s  %ds" % [w.display_name, ceili(w.seconds_left())], 12, col, HORIZONTAL_ALIGNMENT_CENTER, 140.0)
