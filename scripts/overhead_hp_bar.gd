class_name OverheadHpBar extends Node2D
## Small HP bar above a Player or Enemy (its parent). Hidden at full health, shown while damaged.
## Set `scale` before add_child to size it (the boss uses 2x).

const W := 44.0
const H := 6.0
const RISE := 50.0   ## px above the parent's origin (a hero/enemy is ~60 px tall)

func _ready() -> void:
	z_index = 50
	position = Vector2(0, -RISE * scale.y)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var p := get_parent()
	if not ("hp" in p and "max_hp" in p) or p.hp >= p.max_hp or p.hp <= 0 or ("down" in p and p.down):
		return
	var ratio := clampf(float(p.hp) / p.max_hp, 0.0, 1.0)
	var r := Rect2(-W / 2.0, 0, W, H)
	draw_rect(r.grow(1.5), Color(0.05, 0.04, 0.04, 0.9))
	var col := Color(0.35, 0.8, 0.3) if ratio > 0.5 else (Color(0.95, 0.6, 0.15) if ratio > 0.25 else Color(0.9, 0.2, 0.2))
	draw_rect(Rect2(r.position, Vector2(W * ratio, H)), col)
	draw_rect(Rect2(r.position, Vector2(W * ratio, H * 0.4)), Color(1, 1, 1, 0.18))
