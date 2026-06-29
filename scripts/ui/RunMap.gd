extends Control

# ─────────────────────────────────────────────────────────────────────────────
# RunMap — 跑局节点地图（最小骨架）
# 读 RunManager：MAP→显示节点路径+进入按钮；VICTORY/GAME_OVER→横幅+返回标题。
# ─────────────────────────────────────────────────────────────────────────────

const NodeTypes = preload("res://scripts/systems/run/NodeTypes.gd")
const SCENE_TITLE := "res://scenes/ui/TitleScreen.tscn"

func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.offset_left = 40; root.offset_top = 30; root.offset_right = -40; root.offset_bottom = -30
	add_child(root)

	match RunManager.state:
		RunManager.State.VICTORY:
			_banner(root, "[color=gold]🏆 通关！[/color]\n打到了魔王，金币 %d。" % RunManager.gold)
			return
		RunManager.State.GAME_OVER:
			_banner(root, "[color=red]💀 全灭[/color]\n队伍倒在了第 %d 关。" % (RunManager.depth + 1))
			return

	# ── 正常地图 ──
	var title := Label.new()
	title.text = "远征地图"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var info := Label.new()
	info.text = "金币 %d    进度 %d/%d" % [RunManager.gold, RunManager.depth + 1, RunManager.nodes.size()]
	info.modulate = Color(0.8, 0.85, 0.7)
	root.add_child(info)

	# 节点路径
	var path := HBoxContainer.new()
	path.add_theme_constant_override("separation", 10)
	for i in range(RunManager.nodes.size()):
		var n: Dictionary = RunManager.nodes[i]
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(130, 64)
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var mark := "✓" if i < RunManager.depth else ("▶" if i == RunManager.depth else "·")
		var boss := "  ☠" if n.get("type") == "boss" else ""
		lbl.text = "%s %s%s" % [mark, n.get("name", "?"), boss]
		if i < RunManager.depth:
			lbl.modulate = Color(0.5, 0.8, 0.5)
		elif i == RunManager.depth:
			lbl.modulate = Color(1.0, 0.95, 0.6)
		else:
			lbl.modulate = Color(0.5, 0.5, 0.55)
		cell.add_child(lbl)
		path.add_child(cell)
	root.add_child(path)

	# 队伍状态
	root.add_child(_section("队伍"))
	for h in RunManager.party:
		var hl := Label.new()
		var dead := "（阵亡）" if not h.is_alive() else ""
		hl.text = "%s  HP %d/%d%s" % [h.entity_name, h.current_hp, h.get_max_hp(), dead]
		hl.modulate = Color(0.6, 0.6, 0.6) if not h.is_alive() else Color(0.85, 0.9, 0.85)
		root.add_child(hl)

	# 进入按钮
	var spacer := Control.new(); spacer.custom_minimum_size = Vector2(0, 16)
	root.add_child(spacer)
	var node: Dictionary = RunManager.current_node()
	var enter := Button.new()
	enter.text = "▶  进入：%s" % node.get("name", "?")
	enter.custom_minimum_size = Vector2(240, 44)
	enter.add_theme_font_size_override("font_size", 20)
	enter.pressed.connect(func():
		RunManager.enter_current_node()
		# 按节点类型进对应场景（单一真相源：NodeTypes 注册表）
		get_tree().change_scene_to_file(NodeTypes.scene_for(node.get("type", ""))))
	root.add_child(enter)


func _banner(root: VBoxContainer, bbcode: String) -> void:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.add_theme_font_size_override("normal_font_size", 26)
	rt.text = bbcode
	root.add_child(rt)
	var btn := Button.new()
	btn.text = "返回标题"
	btn.custom_minimum_size = Vector2(180, 40)
	btn.pressed.connect(func(): get_tree().change_scene_to_file(SCENE_TITLE))
	root.add_child(btn)


func _section(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(0.6, 0.65, 0.75)
	return l
