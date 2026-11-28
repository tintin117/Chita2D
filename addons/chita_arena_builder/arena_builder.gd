@tool
extends EditorPlugin

const Edit := preload("./arena_edit.gd")
# Tile, sprite scale relative to iso_prop.tscn, cover radius at 100% brush size.
const COVER := {
	"Log": Vector3(48, 1.0, 18), "Log with grass": Vector3(51, 1.0, 21),
	"Brown rock": Vector3(53, 0.85, 15), "Tall brown rock": Vector3(54, 1.0, 19),
	"Stone": Vector3(64, 1.0, 20), "Standing stone": Vector3(66, 1.15, 18),
}
const DECOR := {
	"Shrub": Vector3(29, 0.8, 0), "Leafy bush": Vector3(33, 0.8, 0),
	"Wildflowers": Vector3(41, 0.65, 0), "Grass tuft": Vector3(43, 0.55, 0),
	"Purple flowers": Vector3(44, 0.65, 0), "Mushrooms": Vector3(46, 0.55, 0),
}
const SNAPPED_PROP := &"arena_builder_snapped"
const SHORE_COLOR := Color("#72c7ff")
const COVER_COLOR := Color("#f2a64c")
const CROWN_COLOR := Color("#ffe19a")
const TEAM_COLORS := [Color("#7bc9ff"), Color("#f99a91")]

enum Brush { COVER, DECOR, SPAWN, CROWN }

var _dock: EditorDock
var _tools: VBoxContainer
var _maps: OptionButton
var _brush: OptionButton
var _palette: ItemList
var _size: SpinBox
var _preview: Sprite2D
var _marker: OptionButton
var _snap: CheckBox
var _armed: CheckButton
var _guides: CheckBox
var _report: Label
var _arena: Node2D
var _mouse := Vector2.ZERO
var _has_mouse := false
var _routes: Array[PackedVector2Array] = []
var _shore := PackedVector2Array()
var _validated := false

func _enter_tree() -> void:
	_build_dock()
	add_dock(_dock)
	set_input_event_forwarding_always_enabled()
	scene_changed.connect(_scene_changed)
	get_undo_redo().history_changed.connect(_invalidate_routes)
	get_undo_redo().version_changed.connect(_invalidate_routes)
	_scene_changed(EditorInterface.get_edited_scene_root())

func _exit_tree() -> void:
	if is_instance_valid(_preview):
		_preview.free()
	if is_instance_valid(_dock):
		remove_dock(_dock)
		_dock.queue_free()

func _build_dock() -> void:
	_dock = EditorDock.new()
	_dock.title = "Arena Builder"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_dock.custom_minimum_size.x = 244
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)
	scroll.add_child(layout)
	_maps = OptionButton.new()
	_maps.tooltip_text = "Open a map scene in the 2D editor."
	_maps.add_item("Open an arena…")
	_maps.set_item_disabled(0, true)
	for entry in Arenas.LIST:
		if not entry.scene.is_empty():
			_maps.add_item(entry.name)
			_maps.set_item_metadata(_maps.item_count - 1, entry.scene)
	_maps.item_selected.connect(_open_arena)
	layout.add_child(_maps)
	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 7)
	layout.add_child(_tools)

	_armed = CheckButton.new()
	_armed.text = "Place in viewport"
	_armed.toggled.connect(func(_on: bool) -> void: update_overlays())
	_tools.add_child(_armed)
	_brush = OptionButton.new()
	for label in ["Solid cover", "Decor", "Team spawn", "Crown center"]:
		_brush.add_item(label)
	_brush.item_selected.connect(_select_brush)
	_tools.add_child(_brush)
	_palette = ItemList.new()
	_palette.icon_mode = ItemList.ICON_MODE_TOP
	_palette.fixed_icon_size = Vector2i(40, 40)
	_palette.fixed_column_width = 108
	_palette.max_columns = 2
	_palette.same_column_width = true
	_palette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_palette.custom_minimum_size.y = 228
	_palette.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_tools.add_child(_palette)
	_size = SpinBox.new()
	_size.prefix = "Prop size"
	_size.suffix = "%"
	_size.min_value = 50
	_size.max_value = 200
	_size.step = 5
	_size.value = 100
	_size.tooltip_text = "Scales the sprite and solid cover footprint together."
	_size.value_changed.connect(func(_value: float) -> void: _refresh_preview())
	_tools.add_child(_size)
	_marker = OptionButton.new()
	_tools.add_child(_marker)
	_snap = CheckBox.new()
	_snap.text = "Snap to ground cell"
	_snap.button_pressed = true
	_snap.toggled.connect(func(_on: bool) -> void: update_overlays())
	_tools.add_child(_snap)
	_guides = CheckBox.new()
	_guides.text = "Show shore, cover and routes"
	_guides.button_pressed = true
	_guides.toggled.connect(func(_on: bool) -> void: update_overlays())
	_tools.add_child(_guides)
	var actions := HBoxContainer.new()
	_tools.add_child(actions)
	var select_center := Button.new()
	select_center.text = "Select crown"
	select_center.tooltip_text = "Select the crown marker. Press F over the 2D viewport to frame it."
	select_center.pressed.connect(_select_center)
	actions.add_child(select_center)
	var validate := Button.new()
	validate.text = "Validate arena"
	validate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validate.pressed.connect(_validate)
	actions.add_child(validate)
	_report = _label("Use Validate to preview the bot routes.")
	_tools.add_child(_report)
	_select_brush(Brush.COVER)

func _label(words: String) -> Label:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _scene_changed(root: Node) -> void:
	_arena = root as Node2D if Edit.is_arena(root) else null
	_tools.visible = is_instance_valid(_arena)
	while _maps.item_count > 1 and _maps.get_item_metadata(_maps.item_count - 1) == null:
		_maps.remove_item(_maps.item_count - 1)
	_maps.select(0)
	_armed.set_pressed_no_signal(false)
	_has_mouse = false
	_marker.clear()
	_shore.clear()
	if is_instance_valid(_arena):
		for i in range(1, _maps.item_count):
			if _maps.get_item_metadata(i) == _arena.scene_file_path:
				_maps.select(i)
				break
		if _maps.selected == 0:
			_maps.add_item(_arena.scene_file_path.get_file().get_basename())
			_maps.set_item_disabled(_maps.item_count - 1, true)
			_maps.select(_maps.item_count - 1)
		for child in _arena.get_node("Spawns").get_children():
			var team := "A" if child.get_index() < 4 else "B"
			_marker.add_item("Team %s · %s" % [team, child.name])
		_shore = Edit.shore_segments(_arena.get_node("Ground"))
	_invalidate_routes()
	update_overlays()

func _open_arena(index: int) -> void:
	EditorInterface.open_scene_from_path(_maps.get_item_metadata(index))
	EditorInterface.set_main_screen_editor("2D")

func _select_center() -> void:
	var select := EditorInterface.get_selection()
	select.clear()
	select.add_node(_arena.get_node("Center"))

func _select_brush(brush: int) -> void:
	_marker.visible = brush == Brush.SPAWN
	_palette.visible = brush == Brush.COVER or brush == Brush.DECOR
	_size.visible = _palette.visible
	if _palette.visible:
		_palette.clear()
		var items := COVER if brush == Brush.COVER else DECOR
		var source := Edit.TILE_SET.get_source(Edit.ATLAS_SOURCE) as TileSetAtlasSource
		for label in items:
			var profile: Vector3 = items[label]
			var thumb := AtlasTexture.new()
			thumb.atlas = source.texture
			thumb.region = source.get_tile_texture_region(Edit.atlas_cell(int(profile.x)))
			thumb.filter_clip = true
			var index := _palette.add_item(label, thumb)
			_palette.set_item_metadata(index, profile)
		_palette.select(0)
	_refresh_preview()

func _refresh_preview() -> void:
	if is_instance_valid(_preview):
		_preview.free()
		_preview = null
	var selected := _palette.get_selected_items()
	if _palette.visible and not selected.is_empty():
		var profile: Vector3 = _palette.get_item_metadata(selected[0])
		var size := _size.value / 100.0
		_preview = Edit.make_prop(int(profile.x), _brush.selected == Brush.COVER, Vector2.ZERO)
		_preview.scale *= profile.y * size
		_preview.set("solid_radius", profile.z * size)
	update_overlays()

func _handles(object: Object) -> bool:
	return is_instance_valid(_arena) and object is Node and (object == _arena or _arena.is_ancestor_of(object))

func _canvas() -> Transform2D:
	return EditorInterface.get_editor_viewport_2d().global_canvas_transform

func _ground() -> TileMapLayer:
	return _arena.get_node("Ground")

func _world_at(viewport_point: Vector2) -> Vector2:
	var canvas := _canvas()
	if _snap.button_pressed:
		var ground := _ground()
		return ground.to_global(ground.map_to_local(Edit.cell_at(ground, viewport_point, canvas)))
	return canvas.affine_inverse() * viewport_point

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not is_instance_valid(_arena) or not _tools.is_visible_in_tree() or not _armed.button_pressed:
		return false
	if event is InputEventMouseMotion:
		_mouse = event.position
		_has_mouse = true
		update_overlays()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.pressed:
			_mouse = event.position
			_has_mouse = true
			_place(_world_at(event.position))
			update_overlays()
		return true
	return false

func _place(world: Vector2) -> void:
	if not Edit.on_ground(_ground(), world):
		_report.text = "That point is in water."
		return
	match _brush.selected:
		Brush.COVER, Brush.DECOR:
			_place_prop(world, _brush.selected == Brush.COVER)
		Brush.SPAWN:
			if _marker.selected >= 0:
				_move_marker(_arena.get_node("Spawns").get_child(_marker.selected), world)
		Brush.CROWN:
			_move_marker(_arena.get_node("Center"), world)

func _place_prop(world: Vector2, solid: bool) -> void:
	if not is_instance_valid(_preview):
		_report.text = "Pick a prop from the palette."
		return
	var layer: TileMapLayer = _arena.get_node("Props" if solid else "Decor")
	var parent: Node2D = _arena.get_node("FreeProps")
	var prop := _preview.duplicate() as Sprite2D
	prop.position = parent.to_local(world)
	prop.z_index = layer.z_index - parent.z_index
	if _snap.button_pressed:
		prop.set_meta(SNAPPED_PROP, true)
	var undo := get_undo_redo()
	undo.create_action("Place arena prop", UndoRedo.MERGE_DISABLE, _arena)
	if _snap.button_pressed:
		_replace_snapped_prop(undo, layer, prop, parent, solid)
	undo.add_do_method(parent, "add_child", prop, true)
	undo.add_do_property(prop, "owner", _arena)
	undo.add_do_reference(prop)
	undo.add_undo_method(parent, "remove_child", prop)
	undo.commit_action()

func _replace_snapped_prop(undo: EditorUndoRedoManager, layer: TileMapLayer, prop: Sprite2D, parent: Node2D, solid: bool) -> void:
	var cell := layer.local_to_map(layer.to_local(parent.to_global(prop.position)))
	var old_source := layer.get_cell_source_id(cell)
	if old_source != -1:
		var old_tile := layer.get_cell_atlas_coords(cell)
		var old_alternative := layer.get_cell_alternative_tile(cell)
		undo.add_do_method(layer, "erase_cell", cell)
		undo.add_undo_method(layer, "set_cell", cell, old_source, old_tile, old_alternative)
	for child in parent.get_children():
		if child is Sprite2D and child.has_meta(SNAPPED_PROP) and child.position.is_equal_approx(prop.position) and (child.get("solid_radius") > 0.0) == solid:
			undo.add_do_method(parent, "remove_child", child)
			undo.add_undo_method(parent, "add_child", child, true)
			undo.add_undo_property(child, "owner", child.owner)
			undo.add_undo_method(parent, "move_child", child, child.get_index())
			undo.add_undo_reference(child)
			break

func _move_marker(marker: Node2D, world: Vector2) -> void:
	var parent: Node2D = marker.get_parent()
	var at := parent.to_local(world)
	if at.is_equal_approx(marker.position):
		return
	var undo := get_undo_redo()
	undo.create_action("Move " + str(marker.name), UndoRedo.MERGE_DISABLE, _arena)
	undo.add_do_property(marker, "position", at)
	undo.add_undo_property(marker, "position", marker.position)
	undo.commit_action()

func _invalidate_routes() -> void:
	_routes.clear()
	_validated = false
	_report.text = "Validate to refresh the bot routes."
	update_overlays()

func _validate() -> void:
	if not is_instance_valid(_arena):
		return
	var result := Edit.validate_arena(_arena)
	_routes = result.routes
	_shore = Edit.shore_segments(_ground())
	var errors: Array[String] = result.errors
	_validated = true
	_report.text = "All eight spawns are dry and can reach the crown." if errors.is_empty() else "\n".join(errors)
	update_overlays()

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(_arena) or not _tools.is_visible_in_tree():
		return
	var canvas := _canvas()
	if _guides.button_pressed:
		_draw_guides(overlay, canvas)
	if _armed.button_pressed and _has_mouse and overlay.get_rect().has_point(_mouse):
		_draw_preview(overlay, canvas)

func _draw_guides(overlay: Control, canvas: Transform2D) -> void:
	if _shore.size() >= 2:
		overlay.draw_multiline(canvas * _shore, Color(SHORE_COLOR, 0.57), 1.5)
	for footprint in Edit.cover_footprints(_arena):
		var at := canvas * Vector2(footprint.x, footprint.y)
		overlay.draw_arc(at, footprint.z * canvas.get_scale().x, 0.0, TAU, 20, Color(COVER_COLOR, 0.62), 1.5, true)
	var center := canvas * (_arena.get_node("Center") as Node2D).global_position
	overlay.draw_circle(center, 6.0, CROWN_COLOR)
	var spawns := _arena.get_node("Spawns").get_children()
	var font := overlay.get_theme_default_font()
	for i in spawns.size():
		var marker := spawns[i] as Node2D
		var at := canvas * marker.global_position
		var team: Color = TEAM_COLORS[0 if i < 4 else 1]
		if _validated and i < _routes.size() and _routes[i].size() > 1:
			overlay.draw_polyline((canvas * _arena.global_transform) * _routes[i], Color(team, 0.6), 2.0, true)
		overlay.draw_circle(at, 5.0, team)
		overlay.draw_string_outline(font, at + Vector2(8, -8), str(marker.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
		overlay.draw_string(font, at + Vector2(8, -8), str(marker.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, team)

func _draw_preview(overlay: Control, canvas: Transform2D) -> void:
	var world := _world_at(_mouse)
	var at := canvas * world
	var dry := Edit.on_ground(_ground(), world)
	var color := CROWN_COLOR if dry else Color("#ff7474")
	if is_instance_valid(_preview):
		var parent := _arena.get_node("FreeProps") as Node2D
		var transform := _preview.transform
		transform.origin = parent.to_local(world)
		overlay.draw_set_transform_matrix(canvas * parent.global_transform * transform)
		overlay.draw_texture_rect_region(_preview.texture, _preview.get_rect(), _preview.region_rect, Color(color, 0.66))
		overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
		var radius: float = _preview.get("solid_radius")
		if radius > 0.0:
			overlay.draw_arc(at, radius * canvas.get_scale().x, 0.0, TAU, 24, color, 2.0, true)
	overlay.draw_line(at - Vector2(6, 0), at + Vector2(6, 0), color, 2.0)
	overlay.draw_line(at - Vector2(0, 6), at + Vector2(0, 6), color, 2.0)
	if not dry:
		overlay.draw_string(overlay.get_theme_default_font(), at + Vector2(10, 14), "Water", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
