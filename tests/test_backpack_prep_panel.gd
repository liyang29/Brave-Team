extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_backpack_prep_panel — BackpackPrepPanel 拖放编辑组件
#
# 重点：拖放回调（grab_payload / can_accept / handle_drop）按引用真正改到注入的
# grid/mule_grid/squad_slots，以及载荷类型校验（物品/英雄不能错放）。驮兽仓库
# （原"公共装备栏"）已空间化：{ Vector2i(锚点): item_id }，跟英雄背包同一套逻辑。
# （不真拖鼠标，直接调拖放回调验证状态变更逻辑。）
# ─────────────────────────────────────────────────────────────────────────────

const Prep = preload("res://scripts/ui/BackpackPrepPanel.gd")


func _make_panel(roster: Array, mule: Dictionary, slots: Dictionary):
	var p = Prep.new()
	add_child_autofree(p)
	p.setup(roster, mule, slots)
	return p

func _warrior_entry() -> Dictionary:
	var h: Hero = HeroFactory.create(Hero.HeroClass.WARRIOR)
	h.entity_name = "战士"
	return { "hero": h, "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 }, "grid": {} }

func _bag_key(hi: int, cell: Vector2i) -> Dictionary:
	return { "hero_index": hi, "cell": cell }


func test_setup_builds_without_error() -> void:
	var e := _warrior_entry()
	var p = _make_panel([e], { Vector2i(0,0): "iron_sword" }, { Vector2i(0,0): e["hero"] })
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
	var p = _make_panel([e], { Vector2i(0,0): "iron_sword" }, { Vector2i(0,0): e["hero"] })
	var item := { "type": "item" }
	var hero := { "type": "hero" }
	assert_true(p.can_accept("bag", null, item), "物品可进背包格")
	assert_true(p.can_accept("mule", null, item), "物品可进驮兽仓库")
	assert_true(p.can_accept("trash", null, item), "物品可拖进丢弃桶")
	assert_false(p.can_accept("squad", null, item), "物品不能进站位格")
	assert_true(p.can_accept("squad", null, hero), "英雄可进站位格")
	assert_false(p.can_accept("bag", null, hero), "英雄不能进背包格")
	assert_false(p.can_accept("trash", null, hero), "英雄不能拖进丢弃桶")


func test_drag_mule_to_bag() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword" }
	var p = _make_panel([e], mule, { Vector2i(0,0): e["hero"] })
	var data = p.grab_payload("mule", Vector2i(0,0))
	assert_eq(data["type"], "item", "从驮兽抓起物品载荷")
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), data)
	assert_eq(e["grid"].get(Vector2i(0,0)), "iron_sword", "物品落入注入的 grid")
	assert_false(mule.has(Vector2i(0,0)), "驮兽原锚点腾空")
	assert_true(p.any_item_placed(), "摆了装备 → any_item_placed=true")


func test_drag_bag_back_to_mule() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword" }
	var p = _make_panel([e], mule, { Vector2i(0,0): e["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), p.grab_payload("mule", Vector2i(0,0)))
	# 再从背包拖回驮兽（放到 (2,0)，驮兽此时是空的）
	var back = p.grab_payload("bag", _bag_key(0, Vector2i(0,0)))
	p.handle_drop("mule", Vector2i(2,0), back)
	assert_false(e["grid"].has(Vector2i(0,0)), "背包格已空")
	assert_eq(mule.get(Vector2i(2,0)), "iron_sword", "退回驮兽指定锚点")


func test_drag_bag_onto_overlap_rejected() -> void:
	# 形状感知：拖到会与别件重叠的落点 → 拒绝（不交换），双方原地不动
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword", Vector2i(2,0): "shield" }
	var p = _make_panel([e], mule, { Vector2i(0,0): e["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), p.grab_payload("mule", Vector2i(0,0)))  # 剑 1×2竖 占(0,0)(0,1)
	p.handle_drop("bag", _bag_key(0, Vector2i(1,0)), p.grab_payload("mule", Vector2i(2,0)))  # 盾 1×2竖 占(1,0)(1,1)
	# 把剑拖到 (1,0)（盾的占用格）→ 重叠 → 拒绝
	p.handle_drop("bag", _bag_key(0, Vector2i(1,0)), p.grab_payload("bag", _bag_key(0, Vector2i(0,0))))
	assert_eq(e["grid"].get(Vector2i(0,0)), "iron_sword", "重叠被拒 → 剑留在原位")
	assert_eq(e["grid"].get(Vector2i(1,0)), "shield", "盾也没被挤动")

func test_drag_bag_to_free_spot_moves() -> void:
	# 移到空处 → 成功移动（形状放得下）
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword" }
	var p = _make_panel([e], mule, { Vector2i(0,0): e["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), p.grab_payload("mule", Vector2i(0,0)))
	# 从 (0,0) 移到 (2,0)（空、界内）
	p.handle_drop("bag", _bag_key(0, Vector2i(2,0)), p.grab_payload("bag", _bag_key(0, Vector2i(0,0))))
	assert_false(e["grid"].has(Vector2i(0,0)), "原锚点已空")
	assert_eq(e["grid"].get(Vector2i(2,0)), "iron_sword", "移动到新锚点")

func test_drag_mule_to_bag_out_of_bounds_rejected() -> void:
	# 1×3 竖法杖放在 row2 会越到 row4 → 拒绝，物品留驮兽
	var m := _warrior_entry()
	var mule := { Vector2i(0,0): "staff" }
	var p = _make_panel([m], mule, { Vector2i(0,0): m["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,2)), p.grab_payload("mule", Vector2i(0,0)))
	assert_false(m["grid"].has(Vector2i(0,2)), "越界落点被拒 → 未放入背包")
	assert_eq(mule.get(Vector2i(0,0)), "staff", "法杖留在驮兽原位")


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


# ── 阵亡英雄背包锁编辑（随葬品：能看不能动）────────────────────────────────────

func test_dead_hero_bag_locked_for_drag_out() -> void:
	var e := _warrior_entry()
	e["grid"][Vector2i(0, 0)] = "iron_sword"
	e["hero"].current_hp = 0   # 阵亡
	var p = _make_panel([e], {}, {})
	var bag = p._bag_views[0]
	assert_null(bag._get_drag_data(Vector2(2, 2)), "阵亡英雄背包锁编辑：拿不出物品（哪怕格子里真有）")

func test_dead_hero_bag_locked_for_drop_in() -> void:
	var e := _warrior_entry()
	e["hero"].current_hp = 0
	var p = _make_panel([e], { Vector2i(0,0): "iron_sword" }, {})
	var bag = p._bag_views[0]
	var payload = p.grab_payload("mule", Vector2i(0,0))
	assert_false(bag._can_drop_data(Vector2(2, 2), payload), "阵亡英雄背包锁编辑：拖不进东西")

func test_alive_hero_bag_stays_editable() -> void:
	var e := _warrior_entry()
	var p = _make_panel([e], { Vector2i(0,0): "iron_sword" }, {})
	var bag = p._bag_views[0]
	var payload = p.grab_payload("mule", Vector2i(0,0))
	assert_true(bag._can_drop_data(Vector2(2, 2), payload), "活人背包不受影响，正常可编辑")


# ── 驮兽仓库（空间化，跟英雄背包同一套形状/合成逻辑）────────────────────────────

func test_mule_view_locked_is_always_false() -> void:
	# 驮兽不会"死"，_is_locked 恒 false（跟英雄背包区分开的关键行为）
	var e := _warrior_entry()
	var p = _make_panel([e], { Vector2i(0,0): "iron_sword" }, {})
	assert_false(p._mule_view._is_locked(), "驮兽仓库永不锁编辑")

func test_mule_reorganize_moves_item() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword" }
	var p = _make_panel([e], mule, {})
	p.handle_drop("mule", Vector2i(3,0), p.grab_payload("mule", Vector2i(0,0)))
	assert_false(mule.has(Vector2i(0,0)), "原锚点腾空")
	assert_eq(mule.get(Vector2i(3,0)), "iron_sword", "移到新锚点")

func test_mule_drag_onto_matching_item_merges() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword", Vector2i(3,0): "iron_sword" }
	var p = _make_panel([e], mule, {})
	p.handle_drop("mule", Vector2i(0,0), p.grab_payload("mule", Vector2i(3,0)))
	assert_eq(mule.get(Vector2i(0,0)), "iron_sword@1", "同款落在同款上 → 原地合成为绿")
	assert_false(mule.has(Vector2i(3,0)), "被消耗的那把腾空")

func test_mule_can_drop_out_of_bounds_rejected() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword" }
	var p = _make_panel([e], mule, {})
	assert_false(p.mule_can_drop("iron_sword", { "kind": "mule", "anchor": Vector2i(0,0) }, Vector2i(5,5)),
		"驮兽 6×6，锚点(5,5)+1×2竖会越到 row6 → 越界拒绝")


# ── 丢弃桶（trash：纯消耗，不落进任何地方）──────────────────────────────────────

func test_trash_consumes_item_from_mule() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword" }
	var p = _make_panel([e], mule, {})
	p.handle_drop("trash", null, p.grab_payload("mule", Vector2i(0,0)))
	assert_true(mule.is_empty(), "丢进丢弃桶后驮兽腾空，物品直接消失")

func test_trash_consumes_item_from_bag() -> void:
	var e := _warrior_entry()
	e["grid"][Vector2i(0,0)] = "iron_sword"
	var p = _make_panel([e], {}, {})
	p.handle_drop("trash", null, p.grab_payload("bag", _bag_key(0, Vector2i(0,0))))
	assert_true(e["grid"].is_empty(), "英雄背包丢进丢弃桶后腾空，物品直接消失")


func test_return_all_to_mule() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword", Vector2i(2,0): "shield" }
	var p = _make_panel([e], mule, { Vector2i(0,0): e["hero"] })
	p.handle_drop("bag", _bag_key(0, Vector2i(0,0)), p.grab_payload("mule", Vector2i(0,0)))
	p.handle_drop("bag", _bag_key(0, Vector2i(1,0)), p.grab_payload("mule", Vector2i(2,0)))
	p.return_all_to_mule()
	assert_true(e["grid"].is_empty(), "全部取回后背包空")
	assert_true("iron_sword" in mule.values(), "铁剑回驮兽")
	assert_true("shield" in mule.values(), "盾回驮兽")
