extends Control

# ─────────────────────────────────────────────────────────────────────────────
# ShopScreen — 村庄商店（只买不卖）
# 读 RunManager.shop_stock（进店时按 rarity 随机上的 6 件）→ 花金币买进库存 →
# 离开 → RunManager.leave_shop 前进到下一节点。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"
const Backpack = preload("res://scripts/experiments/BackpackModel.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")

const RARITY_ZH := { "common": "普通", "rare": "稀有", "epic": "史诗" }
const RARITY_COLOR := {
	"common": Color(0.8, 0.8, 0.8),
	"rare": Color(0.45, 0.7, 1.0),
	"epic": Color(0.85, 0.55, 1.0),
}

var _gold_label: Label
var _stock_box: VBoxContainer


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 40; root.offset_top = 30; root.offset_right = -40; root.offset_bottom = -30
	add_child(root)

	var title := Label.new()
	title.text = "村庄 · 商店"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.modulate = Color(1.0, 0.9, 0.5)
	root.add_child(_gold_label)

	var hint := Label.new()
	hint.text = "采购装备 → 进库存，下一关战前摆进背包。只买不卖。"
	hint.modulate = Color(0.75, 0.78, 0.85)
	root.add_child(hint)

	root.add_child(HSeparator.new())

	_stock_box = VBoxContainer.new()
	_stock_box.add_theme_constant_override("separation", 6)
	root.add_child(_stock_box)

	root.add_child(HSeparator.new())

	var leave := Button.new()
	leave.text = "离开村庄 ▶"
	leave.custom_minimum_size = Vector2(200, 44)
	leave.add_theme_font_size_override("font_size", 20)
	leave.pressed.connect(func():
		RunManager.leave_shop()
		get_tree().change_scene_to_file(SCENE_MAP))
	root.add_child(leave)

	_refresh()


func _refresh() -> void:
	_gold_label.text = "金币 %d" % RunManager.gold
	for c in _stock_box.get_children():
		_stock_box.remove_child(c)
		c.free()
	if RunManager.shop_stock.is_empty():
		var sold := Label.new()
		sold.text = "（已售空）"
		sold.modulate = Color(0.55, 0.55, 0.55)
		_stock_box.add_child(sold)
		return
	for item_id in RunManager.shop_stock:
		_stock_box.add_child(_make_row(item_id))


func _make_row(item_id: String) -> Control:
	var it: Dictionary = Backpack.ITEMS.get(item_id, {})
	var rarity: String = it.get("rarity", "common")
	var cost: int = LootTable.price(item_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var desc := Label.new()
	desc.custom_minimum_size = Vector2(420, 0)
	desc.text = "【%s】%s" % [RARITY_ZH.get(rarity, rarity), Backpack.item_desc(item_id)]
	desc.modulate = RARITY_COLOR.get(rarity, Color.WHITE)
	row.add_child(desc)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(140, 36)
	buy.text = "买  %d 金" % cost
	buy.disabled = RunManager.gold < cost
	buy.pressed.connect(_on_buy.bind(item_id))
	row.add_child(buy)

	return row


func _on_buy(item_id: String) -> void:
	RunManager.buy_item(item_id)
	# 延迟刷新：避免在"买"按钮自身 pressed 信号发射途中把它 free 掉而报错
	call_deferred("_refresh")
