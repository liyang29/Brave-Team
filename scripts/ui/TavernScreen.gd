extends Control

# ─────────────────────────────────────────────────────────────────────────────
# TavernScreen — 酒馆 / 招募（途中花金币招英雄）
# 读 RunManager.tavern_offers（进店随机上的候选）→ 花 RECRUIT_COST 招进队 → 离开。
# 队伍满（MAX_PARTY）或金币不足时招募按钮禁用。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"

const CLASS_ZH := {
	Hero.HeroClass.WARRIOR: "战士", Hero.HeroClass.MAGE: "法师", Hero.HeroClass.PRIEST: "牧师",
	Hero.HeroClass.ROGUE: "盗贼", Hero.HeroClass.ARCHER: "猎人",
}

var _gold_label: Label
var _party_label: Label
var _offer_box: VBoxContainer


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 40; root.offset_top = 30; root.offset_right = -40; root.offset_bottom = -30
	add_child(root)

	var title := Label.new()
	title.text = "酒馆 · 招募"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.modulate = Color(1.0, 0.9, 0.5)
	root.add_child(_gold_label)

	_party_label = Label.new()
	_party_label.modulate = Color(0.75, 0.85, 0.75)
	root.add_child(_party_label)

	var hint := Label.new()
	hint.text = "招募 %d 金/人，队伍上限 %d。新人空背包、满血加入，下一关战前给他配装。" % [
		RunManager.RECRUIT_COST, RunManager.MAX_PARTY]
	hint.modulate = Color(0.7, 0.73, 0.8)
	root.add_child(hint)

	root.add_child(HSeparator.new())

	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", 6)
	root.add_child(_offer_box)

	root.add_child(HSeparator.new())

	var leave := Button.new()
	leave.text = "离开酒馆 ▶"
	leave.custom_minimum_size = Vector2(200, 44)
	leave.add_theme_font_size_override("font_size", 20)
	leave.pressed.connect(func():
		RunManager.leave_tavern()
		get_tree().change_scene_to_file(SCENE_MAP))
	root.add_child(leave)

	_refresh()


func _refresh() -> void:
	_gold_label.text = "金币 %d" % RunManager.gold
	_party_label.text = "队伍 %d / %d" % [RunManager.roster.size(), RunManager.MAX_PARTY]
	for c in _offer_box.get_children():
		_offer_box.remove_child(c)
		c.free()
	if RunManager.tavern_offers.is_empty():
		var none := Label.new()
		none.text = "（没有可招募的人了）"
		none.modulate = Color(0.55, 0.55, 0.55)
		_offer_box.add_child(none)
		return
	for tid in RunManager.tavern_offers:
		_offer_box.add_child(_make_row(tid))


func _make_row(template_id: String) -> Control:
	var t: Dictionary = RunManager.HERO_TEMPLATES.get(template_id, {})
	var cls_name: String = CLASS_ZH.get(t.get("cls"), "?")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var desc := Label.new()
	desc.custom_minimum_size = Vector2(460, 0)
	desc.text = "%s（%s）  血%d 攻%d 防%d 速%d 魔%d" % [
		t.get("name", template_id), cls_name,
		int(t.get("hp", 0)), int(t.get("atk", 0)), int(t.get("def", 0)),
		int(t.get("spd", 0)), int(t.get("magic", 0))]
	desc.modulate = Color(0.85, 0.9, 0.95)
	row.add_child(desc)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(150, 36)
	buy.text = "招募  %d 金" % RunManager.RECRUIT_COST
	buy.disabled = RunManager.party_is_full() or RunManager.gold < RunManager.RECRUIT_COST
	buy.pressed.connect(_on_recruit.bind(template_id))
	row.add_child(buy)

	return row


func _on_recruit(template_id: String) -> void:
	RunManager.recruit(template_id)
	call_deferred("_refresh")   # 延迟刷新：避免在按钮 pressed 途中 free 它
