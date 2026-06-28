extends Control

# ─────────────────────────────────────────────────────────────────────────────
# VillageScreen — 村庄（队伍列表 + 招募 + 商店，一屏搞定）
#
# 起手空队：先在这招人(≥1 才能离开)，再买装备，再出发。
# 读 RunManager.tavern_offers / shop_stock；recruit / buy_item / leave_village。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"
const Backpack = preload("res://scripts/experiments/BackpackModel.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")

const CLASS_ZH := {
	Hero.HeroClass.WARRIOR: "战士", Hero.HeroClass.MAGE: "法师", Hero.HeroClass.PRIEST: "牧师",
	Hero.HeroClass.ROGUE: "盗贼", Hero.HeroClass.ARCHER: "猎人",
}
const RARITY_ZH := { "common": "普通", "rare": "稀有", "epic": "史诗" }
const RARITY_COLOR := {
	"common": Color(0.8, 0.8, 0.8), "rare": Color(0.45, 0.7, 1.0), "epic": Color(0.85, 0.55, 1.0),
}

var _gold_label: Label
var _party_box: VBoxContainer
var _recruit_box: VBoxContainer
var _shop_box: VBoxContainer
var _leave_btn: Button


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

	var title := Label.new()
	title.text = "%s · 队伍 / 招募 / 商店" % RunManager.current_node().get("name", "村庄")
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.modulate = Color(1.0, 0.9, 0.5)
	root.add_child(_gold_label)

	root.add_child(_section("我的队伍"))
	_party_box = VBoxContainer.new()
	root.add_child(_party_box)

	root.add_child(_section("招募（%d 金/人 · 队伍上限 %d · 新人满血空背包加入）" % [RunManager.RECRUIT_COST, RunManager.MAX_PARTY]))
	_recruit_box = VBoxContainer.new()
	_recruit_box.add_theme_constant_override("separation", 6)
	root.add_child(_recruit_box)

	root.add_child(_section("商店（买装备进库存，战前摆进背包；只买不卖）"))
	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 6)
	root.add_child(_shop_box)

	root.add_child(HSeparator.new())

	_leave_btn = Button.new()
	_leave_btn.custom_minimum_size = Vector2(200, 44)
	_leave_btn.add_theme_font_size_override("font_size", 20)
	_leave_btn.pressed.connect(func():
		if RunManager.roster.is_empty():
			return
		RunManager.leave_village()
		get_tree().change_scene_to_file(SCENE_MAP))
	root.add_child(_leave_btn)

	_refresh()


func _section(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(0.6, 0.65, 0.75)
	return l


func _refresh() -> void:
	_gold_label.text = "金币 %d    队伍 %d/%d" % [RunManager.gold, RunManager.roster.size(), RunManager.MAX_PARTY]
	_refresh_party()
	_refresh_recruit()
	_refresh_shop()
	# 必须至少招 1 人才能出发
	var empty: bool = RunManager.roster.is_empty()
	_leave_btn.text = "先招募至少 1 人" if empty else "出发 ▶"
	_leave_btn.disabled = empty


func _refresh_party() -> void:
	_clear(_party_box)
	if RunManager.roster.is_empty():
		var none := Label.new()
		none.text = "（队伍空，先到下面招募）"
		none.modulate = Color(0.7, 0.55, 0.55)
		_party_box.add_child(none)
		return
	for e in RunManager.roster:
		var h = e["hero"]
		var l := Label.new()
		l.text = "%s（%s）  HP %d/%d" % [h.entity_name, CLASS_ZH.get(h.hero_class, "?"), h.current_hp, h.get_max_hp()]
		l.modulate = Color(0.8, 0.9, 0.8)
		_party_box.add_child(l)


func _refresh_recruit() -> void:
	_clear(_recruit_box)
	if RunManager.tavern_offers.is_empty():
		_recruit_box.add_child(_dim("（没有可招募的人了）"))
		return
	for tid in RunManager.tavern_offers:
		var t: Dictionary = RunManager.HERO_TEMPLATES.get(tid, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var desc := Label.new()
		desc.custom_minimum_size = Vector2(460, 0)
		desc.text = "%s（%s）  血%d 攻%d 防%d 速%d 魔%d" % [
			t.get("name", tid), CLASS_ZH.get(t.get("cls"), "?"),
			int(t.get("hp", 0)), int(t.get("atk", 0)), int(t.get("def", 0)),
			int(t.get("spd", 0)), int(t.get("magic", 0))]
		desc.modulate = Color(0.85, 0.9, 0.95)
		row.add_child(desc)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 34)
		btn.text = "招募 %d 金" % RunManager.RECRUIT_COST
		btn.disabled = RunManager.party_is_full() or RunManager.gold < RunManager.RECRUIT_COST
		btn.pressed.connect(func():
			RunManager.recruit(tid)
			call_deferred("_refresh"))
		row.add_child(btn)
		_recruit_box.add_child(row)


func _refresh_shop() -> void:
	_clear(_shop_box)
	if RunManager.shop_stock.is_empty():
		_shop_box.add_child(_dim("（已售空）"))
		return
	for item_id in RunManager.shop_stock:
		var it: Dictionary = Backpack.ITEMS.get(item_id, {})
		var rarity: String = it.get("rarity", "common")
		var cost: int = LootTable.price(item_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var desc := Label.new()
		desc.custom_minimum_size = Vector2(460, 0)
		desc.text = "【%s】%s" % [RARITY_ZH.get(rarity, rarity), Backpack.item_desc(item_id)]
		desc.modulate = RARITY_COLOR.get(rarity, Color.WHITE)
		row.add_child(desc)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 34)
		btn.text = "买 %d 金" % cost
		btn.disabled = RunManager.gold < cost
		btn.pressed.connect(func():
			RunManager.buy_item(item_id)
			call_deferred("_refresh"))
		row.add_child(btn)
		_shop_box.add_child(row)


func _dim(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(0.55, 0.55, 0.55)
	return l

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.free()
