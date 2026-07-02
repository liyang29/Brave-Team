extends Control

# ─────────────────────────────────────────────────────────────────────────────
# BagGridView — 空间网格背包（自绘 + 多格拖放），英雄背包 / 驮兽仓库共用
#
# 自绘（_draw）画网格 + 跨格物品 + 拖拽落点幽灵预览（绿=可放/红=越界或重叠）。
# 走 Godot 原生拖放，把取出/校验/放下委托回宿主 panel（同 DragSlot 路子）：
#   _get_drag_data → panel.grab_payload(kind, key)
#   _can_drop_data → panel.bag_can_drop(...) / panel.mule_can_drop(...)（按 kind 分派）
#   _drop_data     → panel.handle_drop(kind, key, data)
#
# kind = "bag"（英雄背包，4×4，hero_index 有效，会锁阵亡英雄）
#      / "mule"（驮兽仓库，尺寸见 grid_w/grid_h，不会"死"，永不锁）
# 落点约定：物品锚点(左上角)吸附到鼠标所在格；能否放由 BackpackModel.can_place 判。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")

const CELL := 46.0
const GAP := 4.0
const STEP := CELL + GAP

var panel                       # BackpackPrepPanel（kind=bag/mule 都可）或 MulePanel（kind=mule）
var kind: String = "bag"
var hero_index: int = 0                 # kind=="bag" 时用
var grid_w: int = Backpack.GRID_W       # kind=="mule" 时宿主会覆盖成 MULE_GRID_W/H
var grid_h: int = Backpack.GRID_H

var _ghosting: bool = false
var _ghost_cells: Array = []
var _ghost_ok: bool = false

const EMPTY_BG := Color(0.13, 0.14, 0.17)
const GRID_LINE := Color(0.28, 0.30, 0.35)
const BORDER := Color(0.75, 0.8, 0.9, 0.9)
const BOOK_COLOR := Color(0.24, 0.44, 0.32)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(grid_w * STEP, grid_h * STEP)


func _grid() -> Dictionary:
	if kind == "mule":
		return panel.mule_grid_ref()
	return panel._roster[hero_index]["grid"]

## 阵亡英雄的背包锁编辑（随葬品：能看不能动，见 RunManager._vacate_dead_from_squad 的同一决策）。
## 驮兽不会"死"，kind=="mule" 时永不锁。
func _is_locked() -> bool:
	if kind == "mule":
		return false
	return not panel._roster[hero_index]["hero"].is_alive()

## 拖放载荷的 key：bag 是 {hero_index,cell}，mule 就是锚点本身。
func _payload_key(anchor: Vector2i):
	if kind == "mule":
		return anchor
	return { "hero_index": hero_index, "cell": anchor }


# ── 坐标 <-> 格子 ─────────────────────────────────────────────────────────────

func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / STEP), int(pos.y / STEP))

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(cell.x * STEP, cell.y * STEP, CELL, CELL)


# ── 绘制 ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	# 空网格
	for y in range(grid_h):
		for x in range(grid_w):
			var r := _cell_rect(Vector2i(x, y))
			draw_rect(r, EMPTY_BG, true)
			draw_rect(r, GRID_LINE, false, 1.0)

	# 物品（跨格填充 + 包围框 + 居中名字）
	var font := ThemeDB.fallback_font
	var grid := _grid()
	for anchor in grid:
		var id: String = grid[anchor]
		var cells: Array = Backpack.item_cells(id, anchor)
		var col: Color = _item_color(id)
		for c in cells:
			draw_rect(_cell_rect(c).grow(-2.0), col, true)
		var bb := _bounding_box(cells)
		draw_rect(bb.grow(-2.0), BORDER, false, 2.0)
		draw_string(font, Vector2(bb.position.x, bb.position.y + bb.size.y * 0.5 + 5.0),
			Backpack.item_name(id), HORIZONTAL_ALIGNMENT_CENTER, bb.size.x, 13, Color(0.95, 0.97, 1.0))

	# 拖拽落点幽灵
	if _ghosting:
		var ghost_col: Color = Color(0.35, 0.85, 0.4, 0.5) if _ghost_ok else Color(0.9, 0.3, 0.3, 0.5)
		for c in _ghost_cells:
			if Backpack.in_bounds(c, grid_w, grid_h):
				draw_rect(_cell_rect(c).grow(-2.0), ghost_col, true)


## 背景色 = 色阶（白绿蓝紫橙红）；技能书不参与色阶系统，固定书本色。
func _item_color(id: String) -> Color:
	var it: Dictionary = Backpack.item_def(id)
	if it.get("tag", "") == "skillbook":
		return BOOK_COLOR
	return Backpack.tier_color(Backpack.item_tier(id))

func _bounding_box(cells: Array) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for c in cells:
		var r := _cell_rect(c)
		mn.x = min(mn.x, r.position.x); mn.y = min(mn.y, r.position.y)
		mx.x = max(mx.x, r.end.x);       mx.y = max(mx.y, r.end.y)
	return Rect2(mn, mx - mn)


# ── Godot 原生拖放 ────────────────────────────────────────────────────────────

func _get_drag_data(at_position: Vector2) -> Variant:
	if _is_locked():
		return null
	# 找鼠标所在格属于哪件物品 → 抓它整件（锚点）
	var cell := _cell_at(at_position)
	var occ: Dictionary = Backpack.occupied_cells(_grid())
	if not occ.has(cell):
		return null
	var anchor: Vector2i = occ[cell]
	var payload = panel.grab_payload(kind, _payload_key(anchor))
	if payload == null:
		return null
	var preview := Label.new()
	preview.text = "  %s  " % payload.get("label", "?")
	preview.modulate = Color(1, 1, 1, 0.9)
	set_drag_preview(preview)
	return payload


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _is_locked():
		return false
	if not (data is Dictionary) or data.get("type", "") != "item":
		return false
	var anchor := _cell_at(at_position)
	var id: String = data["id"]
	var ok: bool
	if kind == "mule":
		ok = panel.mule_can_drop(id, data.get("src", {}), anchor)
	else:
		ok = panel.bag_can_drop(hero_index, id, data.get("src", {}), anchor)
	# 更新幽灵
	_ghosting = true
	_ghost_ok = ok
	_ghost_cells = Backpack.item_cells(id, anchor)
	queue_redraw()
	return ok


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var anchor := _cell_at(at_position)
	panel.handle_drop(kind, _payload_key(anchor), data)
	_ghosting = false
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_ghosting = false
		queue_redraw()


## 悬浮提示：自绘控件没有逐格子节点，用 Godot 的位置相关 tooltip 钩子按鼠标所在格
## 查是哪件物品、返回它的属性文案；空格返回空串 = 不弹提示（Godot 默认行为）。
func _get_tooltip(at_position: Vector2) -> String:
	var cell := _cell_at(at_position)
	var occ: Dictionary = Backpack.occupied_cells(_grid())
	if not occ.has(cell):
		return ""
	var anchor: Vector2i = occ[cell]
	return Backpack.item_tooltip(_grid()[anchor])
