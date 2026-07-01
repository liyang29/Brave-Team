extends Control

# ─────────────────────────────────────────────────────────────────────────────
# EventScreen — 事件节点（照 Rest/Village 套路）
# 读 RunManager.current_event → 显示标题/描述/选项；门槛不满足的选项灰掉并标原因。
# 选一个 → RunManager.resolve_event_choice → 显示结果 → 继续 → leave_event 回地图。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"
const EventTable = preload("res://scripts/systems/run/EventTable.gd")
const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")

var _root: VBoxContainer
var _choices_box: VBoxContainer
var _result: RichTextLabel
var _continue: Button


func _ready() -> void:
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 10)
	_root.offset_left = 40; _root.offset_top = 30; _root.offset_right = -40; _root.offset_bottom = -30
	add_child(_root)

	var ev: Dictionary = EventTable.get_event(RunManager.current_event)

	var title := Label.new()
	title.text = "❓ %s" % ev.get("title", "神秘事件")
	title.add_theme_font_size_override("font_size", 28)
	_root.add_child(title)

	var info := Label.new()
	info.text = "金币 %d" % RunManager.gold
	info.modulate = Color(0.85, 0.85, 0.6)
	_root.add_child(info)

	_root.add_child(_rich("[i]%s[/i]" % ev.get("desc", "")))
	_root.add_child(HSeparator.new())

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	_root.add_child(_choices_box)

	var choices: Array = RunManager.event_choices()
	for i in range(choices.size()):
		_choices_box.add_child(_choice_button(i, choices[i]))

	_result = _rich("")
	_root.add_child(_result)

	_continue = Button.new()
	_continue.text = "继续 ▶"
	_continue.custom_minimum_size = Vector2(200, 44)
	_continue.add_theme_font_size_override("font_size", 20)
	_continue.visible = false
	_continue.pressed.connect(func():
		RunManager.leave_event()
		get_tree().change_scene_to_file(SCENE_MAP))
	_root.add_child(_continue)


func _choice_button(index: int, choice: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(420, 40)
	btn.add_theme_font_size_override("font_size", 16)
	var available: bool = RunManager.event_choice_available(index)
	var label: String = choice.get("label", "选项")
	if not available:
		btn.disabled = true
		label += "  （%s）" % _require_hint(choice.get("require", {}))
	btn.text = label
	if available:
		btn.pressed.connect(func(): _on_choice(index))
	return btn


func _on_choice(index: int) -> void:
	var res: Dictionary = RunManager.resolve_event_choice(index)
	# 清掉选项，展示结果 + 继续
	for c in _choices_box.get_children():
		c.queue_free()
	var txt: String = res.get("text", "")
	_result.text = "[color=#9fe0a0]%s[/color]\n[color=#cccc88]金币 %d[/color]" % [
		txt if txt != "" else "……", RunManager.gold]
	_continue.visible = true


# 门槛不满足时的提示文案
func _require_hint(require: Dictionary) -> String:
	var parts: Array = []
	if require.has("gold"):
		parts.append("需 %d 金" % int(require["gold"]))
	if require.has("item"):
		parts.append("需 %s" % Backpack.item_name(String(require["item"])))
	if require.has("class"):
		parts.append("需 %s" % _class_zh(String(require["class"])))
	return "、".join(parts) if not parts.is_empty() else "条件不足"


func _class_zh(k: String) -> String:
	match k:
		"warrior": return "战士"
		"mage":    return "法师"
		"priest":  return "牧师"
		"rogue":   return "盗贼"
		"archer":  return "猎人"
	return k


func _rich(bb: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(640, 0)
	rt.text = bb
	return rt
