extends Control

# ─────────────────────────────────────────────────────────────────────────────
# RunMap — 跑局节点地图（尖塔式分层 DAG）
# 读 RunManager：MAP→按层画节点图，当前节点高亮，只有"当前节点的后继"可点选进入；
#   VICTORY/GAME_OVER→横幅 + 返回标题。
# 严格连线约束：点选某后继 → RunManager.travel_to（走过去 + 进房间）→ 切到对应场景。
# ─────────────────────────────────────────────────────────────────────────────

const NodeTypes = preload("res://scripts/systems/run/NodeTypes.gd")
const MapGraphView = preload("res://scripts/ui/MapGraphView.gd")
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
			_banner(root, "[color=red]💀 全灭[/color]\n队伍倒在了第 %d 层。" % (RunManager.current_layer() + 1))
			return

	# ── 正常地图 ──
	var title := Label.new()
	title.text = "远征地图"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var info := Label.new()
	info.text = "金币 %d    层 %d/%d" % [RunManager.gold, RunManager.current_layer() + 1, RunManager.map_layers]
	info.modulate = Color(0.8, 0.85, 0.7)
	root.add_child(info)

	# 地图图（自定义绘制：连接线 + 按列摆节点），大图交给 ScrollContainer 滚动
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var graph := MapGraphView.new()
	graph.node_chosen.connect(_on_node_chosen)
	scroll.add_child(graph)
	root.add_child(scroll)

	# 队伍状态
	root.add_child(_section("队伍"))
	for h in RunManager.party:
		var hl := Label.new()
		var dead := "（阵亡）" if not h.is_alive() else ""
		hl.text = "%s  HP %d/%d%s" % [h.entity_name, h.current_hp, h.get_max_hp(), dead]
		hl.modulate = Color(0.6, 0.6, 0.6) if not h.is_alive() else Color(0.85, 0.9, 0.85)
		root.add_child(hl)

	# 提示
	var succ: Array = RunManager.reachable_next()
	var hint := Label.new()
	hint.text = "▶ 点选一个高亮节点前往（选了这条就去不了那条）" if not succ.is_empty() else "（无可前往节点）"
	hint.modulate = Color(1.0, 0.95, 0.6)
	root.add_child(hint)


# 玩家点选一个后继节点 → 走过去并进入它的房间场景（严格连线约束在 travel_to 里保证）。
func _on_node_chosen(id: String) -> void:
	if RunManager.travel_to(id):
		get_tree().change_scene_to_file(NodeTypes.scene_for(RunManager.current_node().get("type", "")))


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
