class_name ArenaUi extends RefCounted

const THEME := preload("res://assets/ui/arena_theme.tres")
const BODY := preload("res://assets/ui/SourceSans3.ttf")
const DISPLAY := preload("res://assets/ui/Cinzel.ttf")
const BACKDROP := preload("res://assets/ui/arena-backdrop.webp")
const LOGO := preload("res://assets/ui/chita-logo.png")
const ABILITIES := preload("res://assets/ui/ability-icons.png")
const EQUIPMENT := preload("res://assets/ui/equipment-icons.png")
const PORTRAITS := preload("res://assets/ui/hero-portraits.png")
const CROWN := preload("res://assets/ui/crown.png")
const SWORDS := preload("res://assets/ui/crossed-swords.png")
const GOLD := Color("#f8d890")
const INK := Color("#eeeee0")
const MUTED := Color("#becdbd")
const SHADE := Color("#101d1e")
const MOSS := Color("#a7cf78")

const PORTRAIT_CELLS := {"knight": 0, "ranger": 1, "wizard": 2, "bonker": 3, "rogue": 6}
const BASIC_CELLS := {"wizard": 1, "ranger": 2}
const SIGNATURE_CELLS := {"knight": 3, "rogue": 4, "wizard": 5, "ranger": 2}

static var _skills: Dictionary[int, Texture2D] = {}

static func backdrop(root: Control, veil := 0.0) -> void:
	var art := picture(BACKDROP, Vector2.ZERO)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(art)
	if veil > 0.0:
		scrim(root, veil)

static func scrim(root: Control, opacity: float) -> void:
	var shade := ColorRect.new()
	shade.color = Color(SHADE, opacity)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)

static func picture(texture: Texture2D, extent: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.custom_minimum_size = extent
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art

static func heading(text: String, px: int) -> Label:
	var node := label(text, px, GOLD)
	node.theme_type_variation = &"DisplayLabel"
	return node

static func label(text: String, px: int = 20, shade := INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", px)
	node.add_theme_color_override("font_color", shade)
	return node

static func button(text: String, action: Callable, primary := false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 42
	if primary:
		node.theme_type_variation = &"PrimaryButton"
	if action.is_valid():
		node.pressed.connect(action)
	return node

static func panel(canvas: CanvasItem, box: Rect2) -> void:
	canvas.draw_style_box(THEME.get_stylebox("panel", "Panel"), box)

static func defer_focus(target: Control) -> void:
	var select := func() -> void:
		if is_instance_valid(target) and target.is_inside_tree() and target.is_visible_in_tree():
			if not target is BaseButton or not target.disabled:
				target.grab_focus()
	select.call_deferred()

static func focusable(node: Control) -> Array[Control]:
	var items: Array[Control] = []
	for child in node.get_children():
		if child is Control and child.visible:
			if child.focus_mode == Control.FOCUS_ALL and (not child is BaseButton or not child.disabled):
				items.append(child)
			items.append_array(focusable(child))
	return items

static func portrait(hero_id: String) -> Texture2D:
	return _atlas_cell(PORTRAITS, PORTRAIT_CELLS.get(hero_id, 0), 3)

static func skill_icon(hero: Hero, slot: int) -> Texture2D:
	if hero.id == "bonker" and slot == 0:
		return SWORDS
	var cells := BASIC_CELLS if slot == 0 else SIGNATURE_CELLS
	var cell: int = 6 if hero.id == "bonker" else cells.get(hero.id, 0)
	if not _skills.has(cell):
		_skills[cell] = _atlas_cell(EQUIPMENT, 0, 2) if cell == 6 else _atlas_cell(ABILITIES, cell, 3)
	return _skills[cell]

static func gear_icon(slot: String) -> Texture2D:
	var cell: int = {"weapon": 1, "armor": 2, "trinket": 3}[slot]
	return _atlas_cell(EQUIPMENT, cell, 2)

static func _atlas_cell(texture: Texture2D, cell: int, columns: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	@warning_ignore("integer_division")
	var side := texture.get_width() / columns
	@warning_ignore("integer_division")
	atlas.region = Rect2((cell % columns) * side, (cell / columns) * side, side, side)
	atlas.filter_clip = true
	return atlas
