extends Control

# ─────────────────────────────────────────────────────────────────────────────
# MapGraphView — 尖塔式分层 DAG 的可视化控件
#
# 读 RunManager 的图，按"列→x / 层→y"摆正节点，并用 _draw() 画节点间连接线：
#   当前可走的边 = 亮黄粗线；已过区域 = 暗；未来 = 灰。
#   当前节点 ◉ 高亮，可前往的后继 = 按钮，其余静态。
# 只负责"画图 + 报告点选"，不知道场景路由 —— 点选后继时 emit node_chosen(id)。
# ─────────────────────────────────────────────────────────────────────────────

signal node_chosen(node_id)

const COL_W := 158.0    # 列间距
const ROW_H := 70.0     # 层间距
const NODE_W := 138.0
const NODE_H := 40.0
const MARGIN := 14.0

const TYPE_ICON := {
	"village": "🏠", "battle": "⚔", "elite": "☢", "rest": "⛲",
	"event": "❓", "boss": "☠",
}

var _centers: Dictionary = {}   # id -> Vector2（节点中心，画线用）
var current_node_control: Control = null   # 当前节点的静态面板（外层用来定位自动滚动）


func _ready() -> void:
	_build()


func _build() -> void:
	var nodes: Dictionary = RunManager.map_nodes
	var layers: int = RunManager.map_layers
	var cur_id: String = RunManager.current_node_id
	var cur_layer: int = RunManager.current_layer()
	var succ: Array = RunManager.reachable_next()

	# 画布尺寸（按最大列 + 层数撑开，交给外层 ScrollContainer 滚动）
	var max_col := 0
	for id in nodes:
		max_col = max(max_col, int(nodes[id]["col"]))
	custom_minimum_size = Vector2(
		MARGIN * 2 + (max_col + 1) * COL_W,
		MARGIN * 2 + layers * ROW_H)

	_centers.clear()
	current_node_control = null
	for id in nodes:
		var n: Dictionary = nodes[id]
		var pos := _node_pos(int(n["col"]), int(n["layer"]))
		_centers[id] = pos + Vector2(NODE_W, NODE_H) * 0.5
		_add_node(n, id, cur_id, cur_layer, succ, pos)
	queue_redraw()


func _node_pos(col: int, layer: int) -> Vector2:
	return Vector2(MARGIN + col * COL_W, MARGIN + layer * ROW_H)


func _add_node(n: Dictionary, id: String, cur_id: String, cur_layer: int,
		succ: Array, pos: Vector2) -> void:
	var typ: String = n["type"]
	var text := "%s %s" % [TYPE_ICON.get(typ, "·"), n["name"]]

	if id in succ:
		# 可前往 → 亮按钮
		var btn := Button.new()
		btn.text = "▶ " + text
		btn.position = pos
		btn.size = Vector2(NODE_W, NODE_H)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func(): node_chosen.emit(id))
		add_child(btn)
		return

	# 不可前往 → 静态格（当前 / 已过 / 未来）
	var panel := PanelContainer.new()
	panel.position = pos
	panel.size = Vector2(NODE_W, NODE_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	if id == cur_id:
		lbl.text = "◉ " + text
		lbl.modulate = Color(1.0, 0.95, 0.55)      # 当前位置：亮黄
		current_node_control = panel
	elif int(n["layer"]) < cur_layer:
		lbl.text = text
		lbl.modulate = Color(0.42, 0.48, 0.42)     # 已过：暗绿
	else:
		lbl.text = text
		lbl.modulate = Color(0.55, 0.55, 0.62)     # 未来：灰
	panel.add_child(lbl)
	add_child(panel)


func _draw() -> void:
	# 连接线：从上一节点的"底边中点"连到后继的"顶边中点"（画在两行的空隙里，清晰可见）。
	var nodes: Dictionary = RunManager.map_nodes
	var cur_id: String = RunManager.current_node_id
	var cur_layer: int = RunManager.current_layer()
	var succ: Array = RunManager.reachable_next()
	for id in nodes:
		if not _centers.has(id):
			continue
		var from: Vector2 = _centers[id] + Vector2(0, NODE_H * 0.5)
		for nxt in nodes[id]["next"]:
			if not _centers.has(nxt):
				continue
			var to: Vector2 = _centers[nxt] - Vector2(0, NODE_H * 0.5)
			var col: Color
			var w := 2.0
			if id == cur_id and nxt in succ:
				col = Color(1.0, 0.88, 0.35, 0.95); w = 3.5   # 可走：亮黄粗
			elif int(nodes[id]["layer"]) < cur_layer:
				col = Color(0.38, 0.42, 0.38, 0.55)           # 已过：暗
			else:
				col = Color(0.5, 0.5, 0.58, 0.55)             # 未来：灰
			draw_line(from, to, col, w, true)
