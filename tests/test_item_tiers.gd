extends GutTest

# 物品色阶合成系统：id 编码 / 数值缩放 / 合成规则 / 掉落分流 / UI 交互 / 战力评分。

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")
const PowerScore = preload("res://scripts/systems/PowerScore.gd")
const Prep = preload("res://scripts/ui/BackpackPrepPanel.gd")


# ── id 编码：base_id / item_tier / tiered_id ─────────────────────────────────

func test_tier0_id_is_unchanged() -> void:
	assert_eq(Backpack.base_id("iron_sword"), "iron_sword", "无后缀 → base_id 就是原 id")
	assert_eq(Backpack.item_tier("iron_sword"), 0, "无后缀 → tier 0（白，缺省）")
	assert_eq(Backpack.tiered_id("iron_sword", 0), "iron_sword", "tier0 构造回原始 id（完全向后兼容）")

func test_tiered_id_roundtrip() -> void:
	var id: String = Backpack.tiered_id("iron_sword", 3)
	assert_eq(id, "iron_sword@3", "构造带后缀 id")
	assert_eq(Backpack.base_id(id), "iron_sword", "base_id 剥掉后缀")
	assert_eq(Backpack.item_tier(id), 3, "item_tier 解析出 3")

func test_item_def_resolves_through_tier() -> void:
	var def: Dictionary = Backpack.item_def("iron_sword@2")
	assert_eq(def.get("name"), "铁剑", "带色阶 id 仍能查到基础定义")


# ── 数值缩放：白×1 ... 红×32 ──────────────────────────────────────────────────

func test_tier_multiplier_doubles_each_level() -> void:
	assert_eq(Backpack.tier_multiplier(0), 1.0, "白×1")
	assert_eq(Backpack.tier_multiplier(1), 2.0, "绿×2")
	assert_eq(Backpack.tier_multiplier(2), 4.0, "蓝×4")
	assert_eq(Backpack.tier_multiplier(3), 8.0, "紫×8")
	assert_eq(Backpack.tier_multiplier(4), 16.0, "橙×16")
	assert_eq(Backpack.tier_multiplier(5), 32.0, "红×32（32把白的合成）")

func test_item_stat_scales_plain_stats() -> void:
	assert_eq(Backpack.item_stat("iron_sword", "atk"), 6, "白铁剑 攻6（与旧行为一致）")
	assert_eq(Backpack.item_stat("iron_sword@1", "atk"), 12, "绿铁剑 攻12(×2)")
	assert_eq(Backpack.item_stat("iron_sword@5", "atk"), 192, "红铁剑 攻192(×32)")

func test_item_stat_ignores_extra_keys() -> void:
	# 副属性(crit_chance等)不吃色阶缩放——即便物品实例带色阶后缀，extra 数值也不查 item_stat，
	# 这里验证 compute() 层面：一件"手动标了色阶"的副属性件不会指数爆炸。
	var grid := { Vector2i(0, 0): "crit_gem@4" }   # 假设一件橙色暴击宝石(fixed_tier本应生成的样子)
	var b: Dictionary = Backpack.compute(grid)
	assert_almost_eq(float(b["extra"].get("crit_chance", 0.0)), 0.15, 0.001,
		"crit_chance 不因色阶缩放（避免百分比属性指数爆炸）")


# ── 合成规则 ──────────────────────────────────────────────────────────────────

func test_mergeable_flags() -> void:
	assert_true(Backpack.is_mergeable("iron_sword"), "纯数值装备可合成")
	assert_true(Backpack.is_mergeable("staff"), "法杖可合成")
	assert_false(Backpack.is_mergeable("book_slash"), "技能书不可合成")
	assert_false(Backpack.is_mergeable("crit_gem"), "副属性件不可合成（走固定色阶）")
	assert_false(Backpack.is_mergeable("decoy_mask"), "嘲讽面具不可合成（机制类）")

func test_merge_result_advances_one_tier() -> void:
	assert_eq(Backpack.merge_result("iron_sword"), "iron_sword@1", "白+白→绿")
	assert_eq(Backpack.merge_result("iron_sword@1"), "iron_sword@2", "绿+绿→蓝")
	assert_eq(Backpack.merge_result("iron_sword@4"), "iron_sword@5", "橙+橙→红")

func test_merge_result_capped_at_red() -> void:
	assert_eq(Backpack.merge_result("iron_sword@5"), "", "红已到顶，不能再合")

func test_merge_result_rejects_non_mergeable() -> void:
	assert_eq(Backpack.merge_result("crit_gem"), "", "非合成链物品不可合成")
	assert_eq(Backpack.merge_result("book_slash"), "", "技能书不可合成")

func test_fixed_tier_of() -> void:
	assert_eq(Backpack.fixed_tier_of("decoy_mask"), 4, "诱敌面具固定橙色(索引4)")
	assert_eq(Backpack.fixed_tier_of("iron_sword"), -1, "合成链物品无固定色阶")


# ── compute() 里色阶生效 ──────────────────────────────────────────────────────

func test_compute_scales_tiered_item_in_grid() -> void:
	var white: Dictionary = Backpack.compute({ Vector2i(0, 0): "iron_sword" })
	var green: Dictionary = Backpack.compute({ Vector2i(0, 0): "iron_sword@1" })
	assert_eq(int(white["atk"]), 6, "白铁剑背包总攻 6")
	assert_eq(int(green["atk"]), 12, "绿铁剑背包总攻 12")

func test_compute_synergy_unaffected_by_tier() -> void:
	# 绿铁剑(1×2竖) + 磨刀石 相邻仍触发开刃（tag 查找走 base_id，色阶不影响协同判定）
	var b: Dictionary = Backpack.compute({ Vector2i(0, 0): "iron_sword@1", Vector2i(1, 0): "whetstone" })
	assert_true("开刃" in b["synergies"], "色阶不影响协同判定")


# ── 掉落分流：mergeable恒白 / fixed_tier恒定色 ─────────────────────────────────

func test_mergeable_items_always_drop_white() -> void:
	for i in range(50):
		var draft: Array = LootTable.draw_draft(1)
		if draft.is_empty():
			continue
		var id: String = draft[0]
		if Backpack.is_mergeable(id):
			assert_eq(Backpack.item_tier(id), 0, "%s 合成链物品恒掉白" % id)

func test_fixed_tier_items_drop_at_configured_tier() -> void:
	# decoy_mask 固定橙(4)；直接验证 LootTable 内部映射函数
	assert_eq(LootTable._drop_id("decoy_mask"), "decoy_mask@4", "诱敌面具掉落即带橙色后缀")
	assert_eq(LootTable._drop_id("iron_sword"), "iron_sword", "合成链物品掉落是裸 base id（白）")

func test_price_unaffected_by_tier() -> void:
	# 两条轴独立：rarity(定价) 不因色阶变化
	assert_eq(LootTable.price("iron_sword"), LootTable.price("iron_sword@3"), "售价只看 rarity，不看色阶")


# ── BackpackPrepPanel：库存合成 + 背包内拖拽合成 ──────────────────────────────

func _warrior_entry() -> Dictionary:
	var h: Hero = HeroFactory.create(Hero.HeroClass.WARRIOR)
	h.entity_name = "战士"
	return { "hero": h, "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 }, "grid": {} }

func test_merge_pool_item_consumes_two_produces_one() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 2 }
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], owned, {})
	assert_true(p.merge_pool_item("iron_sword"), "2件白铁剑可合成")
	assert_eq(int(owned.get("iron_sword", 0)), 0, "消耗了2件白铁剑")
	assert_eq(int(owned.get("iron_sword@1", 0)), 1, "得到1件绿铁剑")

func test_merge_pool_item_fails_with_insufficient_count() -> void:
	var e := _warrior_entry()
	var owned := { "iron_sword": 1 }
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], owned, {})
	assert_false(p.merge_pool_item("iron_sword"), "只有1件不能合成")

func test_merge_pool_item_fails_for_non_mergeable() -> void:
	var e := _warrior_entry()
	var owned := { "crit_gem": 3 }
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], owned, {})
	assert_false(p.merge_pool_item("crit_gem"), "非合成链物品即便≥2件也不能合成")

func test_bag_drag_onto_matching_item_merges() -> void:
	# 拖一把白铁剑落到另一把白铁剑上 → 合成为绿铁剑，原地
	var e := _warrior_entry()
	e["grid"][Vector2i(0, 0)] = "iron_sword"
	var owned := { "iron_sword": 1 }
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], owned, {})
	var data = p.grab_payload("pool", "iron_sword")
	p.handle_drop("bag", { "hero_index": 0, "cell": Vector2i(0, 0) }, data)
	assert_eq(e["grid"].get(Vector2i(0, 0)), "iron_sword@1", "落在同款上 → 原地合成为绿")
	assert_eq(int(owned.get("iron_sword", 0)), 0, "库存那把被消耗")

func test_bag_drag_different_tier_does_not_merge() -> void:
	# 白铁剑拖到绿铁剑上：色阶不同，不合成，按常规重叠规则拒绝
	var e := _warrior_entry()
	e["grid"][Vector2i(0, 0)] = "iron_sword@1"   # 绿
	var owned := { "iron_sword": 1 }              # 白
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], owned, {})
	var data = p.grab_payload("pool", "iron_sword")
	p.handle_drop("bag", { "hero_index": 0, "cell": Vector2i(0, 0) }, data)
	assert_eq(e["grid"].get(Vector2i(0, 0)), "iron_sword@1", "色阶不同 → 不合成，原物不变")
	assert_eq(int(owned.get("iron_sword", 0)), 1, "库存那把没被消耗（拒绝落地）")

func test_bag_can_drop_reports_merge_as_placeable() -> void:
	var e := _warrior_entry()
	e["grid"][Vector2i(0, 0)] = "iron_sword"
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], { "iron_sword": 1 }, {})
	assert_true(p.bag_can_drop(0, "iron_sword", { "kind": "pool" }, Vector2i(0, 0)),
		"落点是可合成的同款 → 幽灵预览应报可放（绿）")


# ── 战力评分吃色阶 ────────────────────────────────────────────────────────────

func test_power_score_scales_with_tier() -> void:
	var white := PowerScore.item_power("iron_sword")
	var green := PowerScore.item_power("iron_sword@1")
	assert_almost_eq(green, white * 2.0, 0.01, "绿装战力分是白装的2倍")
