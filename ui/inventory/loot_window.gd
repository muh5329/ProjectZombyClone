class_name LootWindow
extends CanvasLayer
## Loot UI (Project Zomboid reference 4 layout): two panels along the top
## of the screen — the player's inventory on the left (header
## "Inventory" · "Transfer All" · "W / Cap kg") and the open container on
## the right ("Loot All" · "<Container name>" · "W / Cap"). Each panel
## lists its stacks: colour-square icon, name, count, weight, condition.
##
## - Opens on EventBus.container_opened for the player, closes on
##   container_closed (the container closes itself when the player walks
##   > 2 m away), on E / Esc (handled here before PlayerInteraction sees
##   it) or Tab.
## - Tab with no container open toggles the player panel alone.
## - Click a row → move that stack to the other side; Shift-click → move
##   one item. Rows that cannot fit on the other side are greyed with the
##   reason as tooltip; clicking one shows "Too heavy" in the footer.
## - Pure presentation: every move goes through LootContainer.take/put/
##   take_all/put_all. Test API: transfer_index(), loot_all(),
##   transfer_all(), rows(), row_enabled(), is_open().
## Built in code (blockout UI); buttons never take keyboard focus so WASD
## keeps moving the player while the window is open.

const SIDE_PLAYER := &"player"
const SIDE_CONTAINER := &"container"
const PANEL_W := 380.0
## Lists grow with their rows up to LIST_H (then scroll); never below LIST_MIN_H.
const LIST_H := 242.0
const LIST_MIN_H := 70.0
const ROW_H := 22.0
const LEFT := 160.0
const COL_W_CAT := 44.0
const COL_W_QTY := 32.0
const COL_W_KG := 40.0
const COL_W_COND := 38.0
const TOP := 6.0
const COL_PANEL := Color(0.09, 0.09, 0.1, 0.88)
const COL_HEADER := Color(0.015, 0.015, 0.02, 0.97)
const COL_TEXT := Color(0.9, 0.9, 0.87)
const COL_DIM := Color(0.58, 0.58, 0.56)
const COL_WARN := Color(1.0, 0.62, 0.3)
const COL_ROW_ALT := Color(1, 1, 1, 0.035)
const COL_ROW_HOVER := Color(1, 1, 1, 0.12)
const FONT := 13
## Short category labels (ItemData.Category order) for the "Type" column.
const CATEGORY_SHORT: Array[String] = ["Food", "Drink", "Med", "Weapon", "Tool", "Mat", "Cloth", "Bag", "Misc"]

## The player (GameManager.player when unset).
var player: Node
## The container open for the player (null = none).
var container: LootContainer
## Player panel opened with Tab (stays after the container closes).
var inventory_pinned: bool = false

var root: VBoxContainer
var player_panel: PanelContainer
var container_panel: PanelContainer
var player_title: Label
var player_weight: Label
var container_title: Label
var container_weight: Label
var transfer_all_button: Button
var loot_all_button: Button
var player_list: VBoxContainer
var container_list: VBoxContainer
var player_scroll: ScrollContainer
var container_scroll: ScrollContainer
var footer: Label
var status_label: Label

var _status_time: float = 0.0
var _refresh_queued: bool = false
var _row_styles: Array[StyleBox] = []
## side -> Array[Button] (pooled rows); side -> "(empty)" Label.
var _pools: Dictionary = {SIDE_PLAYER: [], SIDE_CONTAINER: []}
var _empty_labels: Dictionary = {}


func _ready() -> void:
	_build()
	EventBus.container_opened.connect(_on_container_opened)
	EventBus.container_closed.connect(_on_container_closed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.interaction_refused.connect(_on_refused)
	EventBus.item_transferred.connect(_on_item_transferred)
	_update_visibility()


func _player() -> Node:
	if player != null and is_instance_valid(player):
		return player
	return GameManager.player


func _player_inventory() -> ItemContainer:
	return LootContainer.inventory_of(_player())


func is_open() -> bool:
	return container != null


func player_panel_visible() -> bool:
	return player_panel.visible


func container_panel_visible() -> bool:
	return container_panel.visible


# --- Events ------------------------------------------------------------------

func _on_container_opened(actor: Node, c: Node) -> void:
	if actor == null or actor != _player() or not c is LootContainer:
		return
	container = c
	_set_status("")
	_update_visibility()
	refresh()


func _on_container_closed(_actor: Node, c: Node) -> void:
	if c != container:
		return
	container = null
	_update_visibility()
	refresh()


func _on_inventory_changed(owner: Node) -> void:
	if owner == _player() or (container != null and owner == container):
		_queue_refresh()


func _on_refused(actor: Node, _target: Node, reason: String) -> void:
	if actor == _player() and (is_open() or inventory_pinned):
		_set_status(reason, true)


func _on_item_transferred(from: Node, to: Node, item: Dictionary) -> void:
	if container == null or (from != container and to != container):
		return
	var n := int(item.get("count", 0))
	var nm := String(item.get("name", ""))
	if nm == "":
		_set_status("Moved %d item%s" % [n, "" if n == 1 else "s"])
	else:
		_set_status("%s %s%s" % ["Took" if from == container else "Stored", nm, " ×%d" % n if n > 1 else ""])


# --- Input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_inventory"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif is_open() and (event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


## Tab: with a container open, closes everything; otherwise toggles the
## player's inventory panel on its own.
func toggle_inventory() -> void:
	if is_open():
		inventory_pinned = false
		close()
	else:
		inventory_pinned = not inventory_pinned
	_update_visibility()
	refresh()


## Close the open container (and with it the container panel).
func close() -> void:
	if container != null and is_instance_valid(container):
		container.close()
	container = null
	_update_visibility()


# --- Actions (buttons, rows, tests) --------------------------------------------

## Move the stack at [index] of [side] to the other side ([one]: a single
## item). Returns the LootContainer result ({ok, reason?, moved}).
func transfer_index(side: StringName, index: int, one: bool = false) -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	var inv := _inv(side)
	if inv == null or index < 0 or index >= inv.items.size():
		return {"ok": false, "reason": "Not here", "moved": 0}
	return transfer_item(side, inv.items[index], one)


## Move the stack [item] (shown on [side]) to the other side. Rows bind
## to the ItemInstance, never to a list index: a second press on a row
## whose stack already moved is refused ("Not here") instead of moving
## whatever slid into that index.
func transfer_item(side: StringName, item: ItemInstance, one: bool = false) -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	var count := 1 if one else -1
	if side == SIDE_PLAYER:
		return container.put(_player(), item, count)
	return container.take(_player(), item, count)


## "Loot All" (container → player).
func loot_all() -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	return container.take_all(_player())


## "Transfer All" (player → container).
func transfer_all() -> Dictionary:
	if container == null:
		return {"ok": false, "reason": "Nothing open", "moved": 0}
	return container.put_all(_player())


## Row data of [side]: [{name, count, weight, condition, id, enabled, reason}].
func rows(side: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := _inv(side)
	if inv == null:
		return out
	var other := _inv(SIDE_CONTAINER if side == SIDE_PLAYER else SIDE_PLAYER)
	for it in inv.items:
		var r := row_texts(it)
		r["id"] = it.id()
		var why := move_block_reason(it, other) if container != null else ""
		r["enabled"] = why == ""
		r["reason"] = why
		out.append(r)
	return out


func row_enabled(side: StringName, index: int) -> bool:
	var r := rows(side)
	return index >= 0 and index < r.size() and bool(r[index].enabled)


func _inv(side: StringName) -> ItemContainer:
	if side == SIDE_PLAYER:
		return _player_inventory()
	return container.inventory if container != null else null


# --- Pure formatting ------------------------------------------------------------

## "0.25 / 18" (+ " kg" when [unit]).
static func format_weight(w: float, cap: float, unit: bool = false) -> String:
	var c := "∞" if cap < 0.0 else (("%d" % int(cap)) if is_equal_approx(cap, roundf(cap)) else ("%.1f" % cap))
	return "%.2f / %s%s" % [w, c, " kg" if unit else ""]


## {name, count, weight, condition} display strings for one stack.
static func row_texts(it: ItemInstance) -> Dictionary:
	var cond := ""
	if it.data and it.data.has_condition():
		cond = "%d%%" % int(round(it.condition_fraction() * 100.0))
	return {
		"name": it.display_name(),
		"category": category_short(it.data),
		"count": ("×%d" % it.stack) if it.stack > 1 else "",
		"weight": "%.2f" % it.total_weight(),
		"condition": cond,
	}


static func category_short(d: ItemData) -> String:
	if d == null or d.category < 0 or d.category >= CATEGORY_SHORT.size():
		return ""
	return CATEGORY_SHORT[d.category]


## Why one item of [it] cannot move into [to] ("" when it can).
static func move_block_reason(it: ItemInstance, to: ItemContainer) -> String:
	if to == null:
		return "Nowhere to put it"
	if not to.can_fit(it.data, 1):
		return ItemContainer.REASON_HEAVY
	return ""


# --- View ------------------------------------------------------------------------

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred(&"refresh")


## Rebuild both lists and headers from the models.
func refresh() -> void:
	_refresh_queued = false
	var pinv := _player_inventory()
	player_title.text = "Inventory"
	player_weight.text = format_weight(pinv.total_weight(), pinv.capacity, true) if pinv else ""
	transfer_all_button.disabled = container == null or pinv == null or pinv.is_empty()
	_fill(player_list, SIDE_PLAYER)
	if container != null:
		container_title.text = container.display_name
		container_weight.text = format_weight(container.inventory.total_weight(), container.inventory.capacity, true)
		loot_all_button.disabled = container.inventory.is_empty()
		_fill(container_list, SIDE_CONTAINER)
	else:
		_clear(container_list)
		_empty_labels[SIDE_CONTAINER].visible = false
	# Both lists share one height: as tall as the longer one, capped.
	var n := pinv.items.size() if pinv else 0
	if container != null:
		n = maxi(n, container.inventory.items.size())
	var h := clampf(n * ROW_H + 4.0, LIST_MIN_H, LIST_H)
	player_scroll.custom_minimum_size.y = h
	container_scroll.custom_minimum_size.y = h


func _update_visibility() -> void:
	container_panel.visible = container != null
	player_panel.visible = container != null or inventory_pinned
	root.visible = player_panel.visible
	footer.text = "Click: move stack  ·  Shift+click: move one  ·  E / Esc: close  ·  Tab: inventory" \
			if container != null else "Tab: close inventory"


func _clear(list: VBoxContainer) -> void:
	for ch in list.get_children():
		ch.visible = false


## Rows are pooled per list: created once, re-bound and shown / hidden on
## every refresh (no per-refresh node churn).
func _fill(list: VBoxContainer, side: StringName) -> void:
	var data := rows(side)
	var inv := _inv(side)
	var pool: Array = _pools[side]
	var empty: Label = _empty_labels[side]
	empty.visible = data.is_empty()
	for i in data.size():
		if i >= pool.size():
			var nb := _make_row(side, i)
			list.add_child(nb)
			pool.append(nb)
		_bind_row(pool[i], i, data[i], inv.items[i])
	for i in range(data.size(), pool.size()):
		pool[i].visible = false
		pool[i].set_meta(&"item", null)


## Number of visible item rows on [side].
func visible_row_count(side: StringName) -> int:
	var n := 0
	for b in _pools[side]:
		if b.visible:
			n += 1
	return n


## The (pooled) row node showing index [i] of [side].
func row_node(side: StringName, i: int) -> Button:
	var pool: Array = _pools[side]
	return pool[i] if i >= 0 and i < pool.size() else null


func _make_row(side: StringName, index: int) -> Button:
	var b := Button.new()
	b.name = "Row%d" % index
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.add_theme_stylebox_override(&"normal", _row_styles[index % 2])
	b.add_theme_stylebox_override(&"hover", _row_styles[2])
	b.add_theme_stylebox_override(&"pressed", _row_styles[2])
	b.add_theme_stylebox_override(&"disabled", _row_styles[index % 2])
	b.set_meta(&"side", side)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", 6)
	b.add_child(h)
	var icon_holder := CenterContainer.new()
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon_holder)
	var border := ColorRect.new()
	border.custom_minimum_size = Vector2(16, 16)
	border.color = Color(0, 0, 0, 0.8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(border)
	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.position = Vector2(2, 2)
	icon.size = Vector2(12, 12)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(icon)
	var nm := _label("", COL_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	h.add_child(nm)
	var cells := [nm, _cell("", COL_W_CAT, COL_TEXT), _cell("", COL_W_QTY, COL_TEXT), _cell("", COL_W_KG, COL_TEXT), _cell("", COL_W_COND, COL_TEXT)]
	cells[1].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for i in range(1, cells.size()):
		h.add_child(cells[i])
	b.set_meta(&"icon", icon)
	b.set_meta(&"cells", cells)
	b.pressed.connect(_on_row_pressed.bind(b))
	return b


func _bind_row(b: Button, index: int, d: Dictionary, item: ItemInstance) -> void:
	b.visible = true
	b.set_meta(&"item", item)
	b.add_theme_stylebox_override(&"normal", _row_styles[index % 2])
	b.tooltip_text = String(d.reason) if not bool(d.enabled) else (item.data.description if item.data else "")
	(b.get_meta(&"icon") as ColorRect).color = item.data.color if item.data else Color.GRAY
	var col := COL_TEXT if bool(d.enabled) else COL_DIM
	var cells: Array = b.get_meta(&"cells")
	var texts := [String(d.name), String(d.category), String(d.count), String(d.weight), String(d.condition)]
	for i in cells.size():
		cells[i].text = texts[i]
		cells[i].add_theme_color_override(&"font_color", col if i != 1 else (COL_DIM if bool(d.enabled) else COL_DIM.darkened(0.2)))
	b.modulate = Color(1, 1, 1, 1.0 if bool(d.enabled) else 0.55)


func _on_row_pressed(b: Button) -> void:
	var item: ItemInstance = b.get_meta(&"item", null)
	if item == null:
		return
	if container == null:
		_set_status("Open a container to move items")
		return
	transfer_item(StringName(b.get_meta(&"side")), item, Input.is_key_pressed(KEY_SHIFT))


func _cell(text: String, width: float, col: Color) -> Label:
	# (row cells and column headers share the widths below)
	var l := _label(text, col)
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _label(text: String, col: Color = COL_TEXT, size: int = FONT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override(&"font_color", col)
	l.add_theme_font_size_override(&"font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _set_status(text: String, warn: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override(&"font_color", COL_WARN if warn else COL_TEXT)
	_status_time = 2.0 if text != "" else 0.0


func _process(delta: float) -> void:
	if _status_time > 0.0:
		_status_time = maxf(_status_time - delta, 0.0)
		if _status_time == 0.0:
			status_label.text = ""


# --- Construction ------------------------------------------------------------------

func _flat(c: Color, margin: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.5
	s.content_margin_bottom = margin * 0.5
	return s


func _build() -> void:
	_row_styles = [_flat(Color(0, 0, 0, 0)), _flat(COL_ROW_ALT), _flat(COL_ROW_HOVER)]
	root = VBoxContainer.new()
	root.name = "Root"
	root.position = Vector2(LEFT, TOP)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"separation", 2)
	add_child(root)
	var hb := HBoxContainer.new()
	hb.name = "Panels"
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override(&"separation", 6)
	root.add_child(hb)
	var p := _panel("PlayerPanel", true)
	player_panel = p.panel
	player_title = p.title
	player_weight = p.weight
	transfer_all_button = p.button
	player_list = p.list
	player_scroll = p.scroll
	transfer_all_button.pressed.connect(func(): transfer_all())
	hb.add_child(player_panel)
	var c := _panel("ContainerPanel", false)
	container_panel = c.panel
	container_title = c.title
	container_weight = c.weight
	loot_all_button = c.button
	container_list = c.list
	container_scroll = c.scroll
	loot_all_button.pressed.connect(func(): loot_all())
	hb.add_child(container_panel)
	var foot := PanelContainer.new()
	foot.name = "Footer"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_stylebox_override(&"panel", _flat(Color(0, 0, 0, 0.6), 8.0))
	root.add_child(foot)
	var fh := HBoxContainer.new()
	fh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(fh)
	footer = _label("", COL_DIM, 12)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(footer)
	status_label = _label("", COL_TEXT, 12)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fh.add_child(status_label)


## One panel: dark title bar (player: title · Transfer All · weight;
## container: Loot All · title · weight), column header, scroll list.
func _panel(nm: String, is_player: bool) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = nm
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override(&"panel", _flat(COL_PANEL))
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	panel.add_child(v)
	var bar := PanelContainer.new()
	bar.name = "TitleBar"
	bar.add_theme_stylebox_override(&"panel", _flat(COL_HEADER, 8.0))
	v.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	bar.add_child(h)
	var dot := _label("◆", COL_DIM, 11)
	var title := _label("", COL_TEXT, 14)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	var button := Button.new()
	button.name = "TransferAll" if is_player else "LootAll"
	button.text = "Transfer All" if is_player else "Loot All"
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.add_theme_font_size_override(&"font_size", 13)
	button.add_theme_color_override(&"font_color", COL_TEXT)
	button.add_theme_color_override(&"font_hover_color", Color(1, 0.85, 0.45))
	button.add_theme_color_override(&"font_disabled_color", Color(0.45, 0.45, 0.45))
	var weight := _label("", COL_TEXT, 13)
	weight.name = "Weight"
	weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight.custom_minimum_size = Vector2(96, 0)
	h.add_child(dot)
	if is_player:
		h.add_child(title)
		h.add_child(button)
	else:
		h.add_child(button)
		h.add_child(title)
	h.add_child(weight)
	# Column header.
	var colbar := MarginContainer.new()
	colbar.add_theme_constant_override(&"margin_left", 6)
	colbar.add_theme_constant_override(&"margin_right", 6)
	colbar.add_theme_constant_override(&"margin_top", 2)
	v.add_child(colbar)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override(&"separation", 6)
	colbar.add_child(ch)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(16, 0)
	ch.add_child(sp)
	var n := _label("Name", COL_DIM, 11)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(n)
	var type_h := _cell("Type", COL_W_CAT, COL_DIM)
	type_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ch.add_child(type_h)
	ch.add_child(_cell("Qty", COL_W_QTY, COL_DIM))
	ch.add_child(_cell("kg", COL_W_KG, COL_DIM))
	ch.add_child(_cell("Cond", COL_W_COND, COL_DIM))
	for l in ch.get_children():
		if l is Label:
			l.add_theme_font_size_override(&"font_size", 11)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 0)
	scroll.add_child(list)
	var empty := _label("(empty)", COL_DIM)
	empty.name = "Empty"
	empty.custom_minimum_size = Vector2(0, ROW_H)
	empty.visible = false
	list.add_child(empty)
	_empty_labels[SIDE_PLAYER if is_player else SIDE_CONTAINER] = empty
	return {"panel": panel, "title": title, "weight": weight, "button": button, "list": list, "scroll": scroll}
