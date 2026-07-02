extends PanelContainer

# ─────────────────────────────────────────────────────────────────────────────
# DragSlot — 可拖放槽位（背包格 / 站位格 / 公共装备栏格 共用）
#
# 实现 Godot 原生拖放三虚函数，把"取出/能否放/放下"委托给 BackpackPrepPanel：
#   _get_drag_data  → panel.grab_payload(kind, key)
#   _can_drop_data  → panel.can_accept(kind, key, data)
#   _drop_data      → panel.handle_drop(kind, key, data)
#
# kind: "bag"（背包格）/ "squad"（站位格）/ "pool"（公共装备栏格）
# key : bag → { "hero_index": int, "cell": Vector2i }；squad → Vector2i；pool → item_id(String)
# ─────────────────────────────────────────────────────────────────────────────

var panel              # BackpackPrepPanel
var kind: String = ""
var key

var _label: Label
var _badge: Label      # 右下角数量角标（公共装备栏用）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_children()


## 懒建子节点：不依赖 _ready() 的时机——调用方可能在把本节点 add_child 进树【之前】
## 就调 set_display()（比如批量构建时先设值再挂树），_label 若只在 _ready() 建，
## 那种时序下会静默丢字（_label 还是 null，set_display 的 if _label: 直接跳过）。
func _ensure_children() -> void:
	if _label:
		return
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_badge = Label.new()
	_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.modulate = Color(1.0, 0.9, 0.5)
	add_child(_badge)


func set_display(text: String, color: Color, badge: String = "") -> void:
	_ensure_children()
	_label.text = text
	_label.modulate = color
	_badge.text = badge


# ── Godot 拖放三虚函数 ────────────────────────────────────────────────────────

func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload = panel.grab_payload(kind, key)
	if payload == null:
		return null
	var preview := Label.new()
	preview.text = "  %s  " % payload.get("label", "?")
	preview.modulate = Color(1, 1, 1, 0.9)
	set_drag_preview(preview)
	return payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and panel != null and panel.can_accept(kind, key, data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	panel.handle_drop(kind, key, data)
