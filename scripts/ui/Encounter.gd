extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Encounter — 遭遇（最小骨架）
# 读 RunManager 当前节点的敌人 + 队伍 → 开战(自动战斗, 软站位) → 结果 → 继续回报。
# 注：HP 用 RunManager.party 现值（跨节点消耗）；这里暂无背包 prep（下一步接入）。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"

var _result_label: RichTextLabel
var _log_label: RichTextLabel
var _action_btn: Button


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 40; root.offset_top = 24; root.offset_right = -40; root.offset_bottom = -24
	add_child(root)

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

	# 队伍预览
	root.add_child(_section("我方（HP 跨关保留）"))
	for h in RunManager.party:
		var hl := Label.new()
		var dead := "（阵亡）" if not h.is_alive() else ""
		hl.text = "%s  HP %d/%d  攻%d 防%d 魔%d%s" % [
			h.entity_name, h.current_hp, h.get_max_hp(),
			h.get_attack(), h.get_defense(), h.get_magic(), dead]
		hl.modulate = Color(0.6, 0.6, 0.6) if not h.is_alive() else Color(0.8, 0.9, 0.8)
		root.add_child(hl)

	var spacer := Control.new(); spacer.custom_minimum_size = Vector2(0, 12)
	root.add_child(spacer)

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


func _on_fight() -> void:
	var heroes: Array = RunManager.alive_party()
	if heroes.is_empty():
		return
	var party: Party = Party.create(heroes, null, 0.4)
	party.positioning_mode = "soft_row"
	for h in heroes:
		party.set_row(h, _default_row(h))

	var enemies: Array = RunManager.current_node().get("enemies", [])
	var result: BattleResult = BattleSimulator.simulate(party, enemies)
	_render_result(result)


func _default_row(hero) -> String:
	if hero.hero_class == Hero.HeroClass.WARRIOR or hero.hero_class == Hero.HeroClass.ROGUE:
		return "front"
	return "back"


func _render_result(result: BattleResult) -> void:
	var won: bool = result.party_won
	var head := "[color=lime][b]✅ 胜利[/b][/color]" if won else "[color=red][b]❌ 团灭[/b][/color]"
	var survivors: Array = []
	for h in RunManager.party:
		if h.is_alive():
			survivors.append("%s(%d)" % [h.entity_name, h.current_hp])
	var line := "\n存活：%s" % (", ".join(survivors) if not survivors.is_empty() else "无")
	_result_label.text = "%s（%d 回合）%s" % [head, result.total_turns, line]

	# 简短日志（最后 16 行）
	var lines: Array = []
	for log in result.turn_logs:
		lines.append(_fmt(log))
	if lines.size() > 16:
		lines = lines.slice(lines.size() - 16)
	_log_label.text = "\n".join(lines)

	# 切换为"继续"，回报 RunManager
	_action_btn.text = "继续 ▶"
	for c in _action_btn.pressed.get_connections():
		_action_btn.pressed.disconnect(c.callable)
	_action_btn.pressed.connect(func():
		RunManager.resolve_encounter(won, result)
		get_tree().change_scene_to_file(SCENE_MAP))


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
