extends Control

# ─────────────────────────────────────────────────────────────────────────────
# RestScreen — 泉水 / 休息点（消耗战泄压阀）
# 进入即全员回复 RunManager.REST_HEAL_PCT 比例的最大血 → 展示前后 → 继续回地图。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 40; root.offset_top = 30; root.offset_right = -40; root.offset_bottom = -30
	add_child(root)

	var title := Label.new()
	title.text = "泉水 · 休息"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "队伍在泉水边休整，全员回复 %d%% 最大生命。" % int(RunManager.REST_HEAL_PCT * 100)
	hint.modulate = Color(0.6, 0.9, 0.7)
	root.add_child(hint)

	root.add_child(HSeparator.new())

	var report: Array = RunManager.rest_heal()
	for r in report:
		var l := Label.new()
		var gained: int = int(r["after"]) - int(r["before"])
		l.text = "%s  HP %d → %d/%d  [color=#7fdca0](+%d)[/color]" % [
			r["name"], r["before"], r["after"], r["max"], gained]
		l.add_theme_font_size_override("font_size", 16)
		root.add_child(_rich(l.text))
	if report.is_empty():
		root.add_child(_rich("[color=gray]无存活成员可回复。[/color]"))

	root.add_child(HSeparator.new())

	var cont := Button.new()
	cont.text = "继续 ▶"
	cont.custom_minimum_size = Vector2(200, 44)
	cont.add_theme_font_size_override("font_size", 20)
	cont.pressed.connect(func():
		RunManager.leave_rest()
		get_tree().change_scene_to_file(SCENE_MAP))
	root.add_child(cont)


func _rich(bb: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(500, 0)
	rt.text = bb
	return rt
