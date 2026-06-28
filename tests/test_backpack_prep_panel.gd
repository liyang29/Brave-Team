extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_backpack_prep_panel — BackpackPrepPanel 编辑组件（Step 3）
#
# 重点：面板按引用操作宿主状态——放入/退回物品要真的改到注入的 grid/owned_items，
# 以及给宿主的校验助手 has_front_row / any_item_placed 正确。
# （不真点按钮，直接调交互方法验证状态变更逻辑。）
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


func test_setup_builds_without_error() -> void:
	var e := _warrior_entry()
	var p = _make_panel([e], { "iron_sword": 1 }, { Vector2i(0,0): e["hero"] })
	assert_not_null(p, "面板实例化 + setup 不报错")
	assert_true(p.any_item_placed() == false, "起始未摆装备")


func test_has_front_row() -> void:
	var e := _warrior_entry()
	var with_front = _make_panel([e], {}, { Vector2i(0,0): e["hero"] })
	assert_true(with_front.has_front_row(), "有人在 row0 → 前排有人")
	var e2 := _warrior_entry()
	var no_front = _make_panel([e2], {}, { Vector2i(0,1): e2["hero"] })
	assert_false(no_front.has_front_row(), "只有 row1 → 前排无人")


func test_place_item_mutates_injected_state() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1 }
	var p = _make_panel([e], owned, { Vector2i(0,0): e["hero"] })
	# 选中 + 放入 (0,0)
	p._selected_item = "iron_sword"
	p._on_cell_pressed(0, Vector2i(0,0))
	assert_eq(e["grid"].get(Vector2i(0,0)), "iron_sword", "物品摆进了注入的 grid")
	assert_eq(int(owned.get("iron_sword", -1)), 0, "库存对应 -1")
	assert_true(p.any_item_placed(), "摆了装备后 any_item_placed=true")


func test_return_item_to_pool() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1 }
	var p = _make_panel([e], owned, { Vector2i(0,0): e["hero"] })
	p._selected_item = "iron_sword"
	p._on_cell_pressed(0, Vector2i(0,0))   # 放入
	p._on_cell_pressed(0, Vector2i(0,0))   # 再点 → 退回
	assert_false(e["grid"].has(Vector2i(0,0)), "格子已空")
	assert_eq(int(owned.get("iron_sword", -1)), 1, "退回库存 +1")


func test_return_all_to_pool() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1, "shield": 1 }
	var p = _make_panel([e], owned, { Vector2i(0,0): e["hero"] })
	p._selected_item = "iron_sword"
	p._on_cell_pressed(0, Vector2i(0,0))
	p._selected_item = "shield"
	p._on_cell_pressed(0, Vector2i(1,0))
	p.return_all_to_pool()
	assert_true(e["grid"].is_empty(), "全部取回后背包空")
	assert_eq(int(owned.get("iron_sword", -1)), 1, "铁剑回库存")
	assert_eq(int(owned.get("shield", -1)), 1, "盾回库存")
