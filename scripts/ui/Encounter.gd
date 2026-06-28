extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Encounter — 遭遇（已接入背包 prep）
# 读 RunManager 当前节点的敌人 + 队伍名册 → 战前搭背包/摆站位(BackpackPrepPanel)
# → 开战(钳血消耗战, full_heal=false) → 结果 → 继续回报 RunManager。
# HP 跨节点保留（消耗战）；背包/库存/站位都来自 RunManager，跨节点持续。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"
const SCENE_DRAFT := "res://scenes/run/Draft.tscn"
const Loadout = preload("res://scripts/systems/BackpackLoadout.gd")
const Prep = preload("res://scripts/ui/BackpackPrepPanel.gd")

var _prep
var _hp_box: VBoxContainer
var _result_label: RichTextLabel
var _log_label: RichTextLabel
var _action_btn: Button


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.custom_minimum_size = Vector2(740, 0)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 40; root.offset_top = 24
	scroll.add_child(root)

	var node: Dictionary = RunManager.current_node()
	var title := Label.new()
	title.text = "遭遇：%s%s" % [node.get("name", "?"), "  ☠BOSS" if node.get("type") == "boss" else ""]
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)

	# 敌人预览
	root.add_child(_section("敌人"))
	for e in node.get("enemies", []):
		var el := Label.new()
		el.text = "%s  HP%d 攻%d 防%d  [%s]" % [
			e.entity_name, e.base_max_hp, e.base_attack, e.base_defense,
			"后排远程" if e.is_ranged else "前排"]
		el.modulate = Color(1.0, 0.7, 0.65)
		root.add_child(el)

	# 我方 HP（跨关消耗，开战不回血）
	root.add_child(_section("我方 HP（跨关保留 · 开战不回血，靠泉水/休息点恢复）"))
	_hp_box = VBoxContainer.new()
	root.add_child(_hp_box)
	_refresh_hp()

	# 背包 / 站位编辑（共享组件，操作 RunManager 状态）
	root.add_child(_section("战前准备：搭背包 + 摆站位"))
	_prep = Prep.new()
	root.add_child(_prep)
	_prep.setup(RunManager.roster, RunManager.owned_items, RunManager.squad_slots)

	root.add_child(HSeparator.new())

	_action_btn = Button.new()
	_action_btn.text = "⚔  开战"
	_action_btn.custom_minimum_size = Vector2(200, 44)
	_action_btn.add_theme_font_size_override("font_size", 20)
	_action_btn.pressed.connect(_on_fight)
	root.add_child(_action_btn)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size = Vector2(700, 0)
	root.add_child(_result_label)

	root.add_child(_section("战斗日志"))
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.custom_minimum_size = Vector2(700, 0)
	root.add_child(_log_label)


func _refresh_hp() -> void:
	for c in _hp_box.get_children():
		_hp_box.remove_child(c)
		c.free()
	for h in RunManager.party:
		var hl := Label.new()
		var dead := "（阵亡）" if not h.is_alive() else ""
		hl.text = "%s  HP %d/%d%s" % [h.entity_name, h.current_hp, h.get_max_hp(), dead]
		hl.modulate = Color(0.55, 0.55, 0.55) if not h.is_alive() else Color(0.8, 0.9, 0.8)
		_hp_box.add_child(hl)


func _on_fight() -> void:
	# 允许裸打（不强制摆装备）；仅保留"前排至少留 1 人"的世界树规则
	if not _prep.has_front_row():
		_result_label.text = "[color=red]前排至少留 1 人（不能全员躲后排）。[/color]"
		return

	# 只让存活的人参战；钳血消耗战（full_heal=false）
	var alive_loadouts: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
	if alive_loadouts.is_empty():
		return
	var party: Party = Loadout.build_party(alive_loadouts, RunManager.squad_slots, false)
	var enemies: Array = RunManager.current_node().get("enemies", [])
	var result: BattleResult = BattleSimulator.simulate(party, enemies)
	_render_result(result)


func _render_result(result: BattleResult) -> void:
	var won: bool = result.party_won
	var head := "[color=lime][b]✅ 胜利[/b][/color]" if won else "[color=red][b]❌ 团灭[/b][/color]"
	var survivors: Array = []
	for h in RunManager.party:
		if h.is_alive():
			survivors.append("%s(%d)" % [h.entity_name, h.current_hp])
	var line := "\n存活：%s" % (", ".join(survivors) if not survivors.is_empty() else "无")
	_result_label.text = "%s（%d 回合）%s" % [head, result.total_turns, line]
	_refresh_hp()

	# 完整战斗日志（界面在 ScrollContainer 里，可滚动查看全部）
	var lines: Array = []
	for log in result.turn_logs:
		lines.append(_fmt(log))
	_log_label.text = "\n".join(lines)

	# 切换为"继续"，回报 RunManager
	_action_btn.text = "继续 ▶"
	for c in _action_btn.pressed.get_connections():
		_action_btn.pressed.disconnect(c.callable)
	_action_btn.pressed.connect(func():
		RunManager.resolve_encounter(won, result)
		# 普通胜利 → 战利品 draft；通关/失败 → 回地图（地图据状态显示横幅）
		var next := SCENE_DRAFT if RunManager.state == RunManager.State.DRAFT else SCENE_MAP
		get_tree().change_scene_to_file(next))


func _fmt(log) -> String:
	if log.skill_id == "dot_tick":
		return "[color=#9b6dff]☠ %s 毒伤 %d[/color]" % [log.target_name, log.damage]
	var act := "普攻" if log.skill_id.is_empty() else SkillTable.get_display_name(log.skill_id)
	var crit := " [color=gold]暴击![/color]" if log.is_crit else ""
	var kill := "（击杀）" if log.is_kill else ""
	if log.damage > 0 or not log.skill_id.is_empty():
		return "%s【%s】→ %s %d%s%s" % [log.actor_name, act, log.target_name, log.damage, crit, kill]
	return "%s【%s】" % [log.actor_name, act]


func _section(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(0.6, 0.65, 0.75)
	return l
