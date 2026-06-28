extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_backpack_prep_panel — BackpackPrepPanel 拖放编辑组件（Step 3 + 拖放重写）
#
# 重点：拖放回调（grab_payload / can_accept / handle_drop）按引用真正改到注入的
# grid/owned_items/squad_slots，以及载荷类型校验（物品/英雄不能错放）。
# （不真拖鼠标，直接调拖放回调验证状态变更逻辑。）
# ─────────────────────────────────────────────────────────────────────────────

const Prep = preload("res://scripts/ui/BackpackPrepPanel.gd")


func _make_panel(roster: Array, owned: Dictionary, slots: Dictionary):
	var p = Prep.new()
	add_child_autofree(p)
	p.setup(roster, owned, slots)
	return p

func _warrior_entry() -> Dictionary:
	var h: Hero = HeroFactory.create(Hero.HeroClass.WARRIOR)
	h.entity_name = "战士"
	return { "hero": h, "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 }, "grid": {} }

func _bag_key(hi: int, cell: Vector2i) -> Dictionary:
	return { "hero_index": hi, "cell": cell }


func test_setup_builds_without_error() -> void:
	var e := _warrior_entry()
	var p = _make_panel([e], { "iron_sword": 1 }, { Vector2i(0,0): e["hero"] })
	assert_not_null(p, "面板实例化 + setup 不报错")
	assert_false(p.any_item_placed(), "起始未摆装备")


func test_has_front_row() -> void:
	var e := _warrior_entry()
	var with_front = _make_panel([e], {}, { Vector2i(0,0): e["hero"] })
	assert_true(with_front.has_front_row(), "有人在 row0 → 前排有人")
	var e2 := _warrior_entry()
	var no_front = _make_panel([e2], {}, { Vector2i(0,1): e2["hero"] })
	assert_false(no_front.has_front_row(), "只有 row1 → 前排无人")


func test_can_accept_type_rules() -> void:
	var e := _warrior_entry()
	var p = _make_panel([e], { "iron_sword": 1 }, { Vector2i(0,0): e["hero"] })
	var item := { "type": "item" }
	var hero := { "type": "hero" }
	assert_true(p.can_accept("bag", null, item), "物品可进背包格")
	assert_true(p.can_accept("pool", null, item), "物品可进库存")
	assert_false(p.can_accept("squad", null, item), "物品不能进站位格")
	assert_true(p.can_accept("squad", null, hero), "英雄可进站位格")
	assert_false(p.can_accept("bag", null, hero), "英雄不能进背包格")


func test_drag_pool_to_bag() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1 }
	var p = _make_panel([e], owned, { Vector2i(0,0): e["hero"] })
	var data = p.grab_payload("pool", "iron_sword")
	assert_eq(data["type"], "item", "从库存抓起物品载荷")
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), data)
	assert_eq(e["grid"].get(Vector2i(0,0)), "iron_sword", "物品落入注入的 grid")
	assert_eq(int(owned.get("iron_sword", 0)), 0, "库存 -1（到 0 移除）")
	assert_true(p.any_item_placed(), "摆了装备 → any_item_placed=true")


func test_drag_bag_back_to_pool() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1 }
	var p = _make_panel([e], owned, { Vector2i(0,0): e["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), p.grab_payload("pool", "iron_sword"))
	# 再从背包拖回库存
	var back = p.grab_payload("bag", _bag_key(0, Vector2i(0,0)))
	p.handle_drop("pool", "iron_sword", back)
	assert_false(e["grid"].has(Vector2i(0,0)), "背包格已空")
	assert_eq(int(owned.get("iron_sword", 0)), 1, "退回库存 +1")


func test_drag_bag_to_occupied_swaps() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1, "shield": 1 }
	var p = _make_panel([e], owned, { Vector2i(0,0): e["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), p.grab_payload("pool", "iron_sword"))
	p.handle_drop("bag", _bag_key(0, Vector2i(1,0)), p.grab_payload("pool", "shield"))
	# 把 (0,0) 的剑拖到 (1,0) 的盾上 → 交换
	p.handle_drop("bag", _bag_key(0, Vector2i(1,0)), p.grab_payload("bag", _bag_key(0, Vector2i(0,0))))
	assert_eq(e["grid"].get(Vector2i(1,0)), "iron_sword", "目标格变成被拖的剑")
	assert_eq(e["grid"].get(Vector2i(0,0)), "shield", "原格换成被挤掉的盾")


func test_drag_hero_swaps_squad() -> void:
	var w := _warrior_entry()
	var m := _warrior_entry(); m["hero"].entity_name = "法师"
	var slots := { Vector2i(0,0): w["hero"], Vector2i(0,1): m["hero"] }
	var p = _make_panel([w, m], {}, slots)
	# 把后排法师拖到前排战士格 → 交换
	var data = p.grab_payload("squad", Vector2i(0,1))
	assert_eq(data["type"], "hero", "从站位格抓起英雄载荷")
	p.handle_drop("squad", Vector2i(0,0), data)
	assert_eq(slots.get(Vector2i(0,0)), m["hero"], "前排变成法师")
	assert_eq(slots.get(Vector2i(0,1)), w["hero"], "后排换成战士")


func test_return_all_to_pool() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1, "shield": 1 }
	var p = _make_panel([e], owned, { Vector2i(0,0): e["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), p.grab_payload("pool", "iron_sword"))
	p.handle_drop("bag", _bag_key(0, Vector2i(1,0)), p.grab_payload("pool", "shield"))
	p.return_all_to_pool()
	assert_true(e["grid"].is_empty(), "全部取回后背包空")
	assert_eq(int(owned.get("iron_sword", 0)), 1, "铁剑回库存")
	assert_eq(int(owned.get("shield", 0)), 1, "盾回库存")
