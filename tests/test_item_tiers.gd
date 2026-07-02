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


# ── 深度门控：min_layer ────────────────────────────────────────────────────────

func test_min_layer_defaults_to_zero() -> void:
	assert_eq(Backpack.min_layer_of("iron_sword"), 0, "普通装备不设门槛，起手就能遇到")
	assert_eq(Backpack.min_layer_of("shield"), 0, "普通装备不设门槛")

func test_min_layer_gates_special_items() -> void:
	assert_eq(Backpack.min_layer_of("keen_edge"), 5, "锋锐之刃 min_layer 5")
	assert_eq(Backpack.min_layer_of("war_banner"), 10, "军旗 min_layer 10")
	assert_eq(Backpack.min_layer_of("crit_gem"), 20, "暴击宝石 min_layer 20")
	assert_eq(Backpack.min_layer_of("decoy_mask"), 25, "诱敌面具 min_layer 25")
	assert_eq(Backpack.min_layer_of("iron_standard"), 25, "铁壁旗 min_layer 25")

func test_draw_draft_excludes_gated_items_at_low_layer() -> void:
	# 第 0 层：min_layer>0 的物品一件都不该出现（跑很多次覆盖随机性）
	for i in range(80):
		var draft: Array = LootTable.draw_draft(3, 0)
		for id in draft:
			assert_eq(Backpack.min_layer_of(id), 0, "第0层掉落的 %s 不该有门槛" % id)

func test_draw_draft_allows_gated_items_at_high_layer() -> void:
	# 第 10 层：门槛全部解开，理论上能抽到任意物品（跑很多次应至少见到一件 min_layer>0 的）
	var saw_gated := false
	for i in range(80):
		var draft: Array = LootTable.draw_draft(3, 10)
		for id in draft:
			if Backpack.min_layer_of(id) > 0:
				saw_gated = true
	assert_true(saw_gated, "第10层应能抽到深度门控物品（80次里至少一次，概率上稳）")

func test_draw_draft_default_layer_is_ungated() -> void:
	# 不传 layer（旧调用/旧测试）→ 默认几乎不限，行为与门控加入前一致
	var huge: Array = LootTable.draw_draft(9999)
	assert_eq(huge.size(), Backpack.ITEMS.size(), "不传层数 → 不限门槛，仍能抽满整池")

func test_shop_stock_respects_layer_gate() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()   # 第 0 层村庄
	for id in RunManager.shop_stock:
		assert_eq(Backpack.min_layer_of(id), 0, "第0层商店 %s 不该有门槛物品" % id)


# ── 深度掉落色阶曲线（走得越深，越可能直接摸到预合成好的绿/蓝）──────────────────

func test_shallow_layer_is_always_white() -> void:
	# 第0-4层：曲线 100% 白，mergeable 物品即便指定了层数也不该出现色阶
	for i in range(60):
		var draft: Array = LootTable.draw_draft(2, 2)
		for id in draft:
			if Backpack.is_mergeable(id):
				assert_eq(Backpack.item_tier(id), 0, "浅层(2) %s 应仍是白" % id)

func test_deep_layer_can_drop_tiered_mergeable() -> void:
	# 第20层（曲线最深档 60/25/12/3）：跑够样本应能见到非白的合成链物品
	var saw_tiered := false
	for i in range(100):
		var draft: Array = LootTable.draw_draft(2, 20)
		for id in draft:
			if Backpack.is_mergeable(id) and Backpack.item_tier(id) > 0:
				saw_tiered = true
	assert_true(saw_tiered, "第20层应能摸到预合成的非白装备（100次里至少一次，概率上稳）")

func test_natural_drop_never_exceeds_purple() -> void:
	# 天然掉落封顶紫色(3)——橙(4)/红(5)只能靠玩家自己合成，不会被 LootTable 直接掉出
	for i in range(150):
		var draft: Array = LootTable.draw_draft(3, 50)
		for id in draft:
			if Backpack.is_mergeable(id):
				assert_lte(Backpack.item_tier(id), 3, "%s 天然掉落不应超过紫色(3)" % id)

func test_tier_weights_by_layer_never_exceed_cap() -> void:
	# 数据层面直接校验曲线表：任何档位的权重表都不包含 tier>3 的键
	for cfg in LootTable.TIER_WEIGHTS_BY_LAYER:
		for t in cfg["weights"].keys():
			assert_lte(int(t), 3, "曲线表不应配置超过紫色(3)的档")


# ── 新增后期基础装备（深度解锁新内容，非单纯数字更大）────────────────────────────

func test_late_game_items_have_higher_base_stats() -> void:
	assert_gt(int(Backpack.item_def("steel_sword").get("atk", 0)), int(Backpack.item_def("iron_sword").get("atk", 0)),
		"精钢剑攻击 > 铁剑")
	assert_gt(int(Backpack.item_def("mithril_staff").get("magic", 0)), int(Backpack.item_def("staff").get("magic", 0)),
		"秘银法杖魔力 > 法杖")
	assert_gt(int(Backpack.item_def("dragon_scale").get("def", 0)), int(Backpack.item_def("chainmail").get("def", 0)),
		"巨龙鳞甲防御 > 锁甲")

func test_late_game_items_are_gated_and_mergeable() -> void:
	for id in ["steel_sword", "mithril_staff", "holy_hammer"]:
		assert_gt(Backpack.min_layer_of(id), 0, "%s 有深度门控" % id)
		assert_true(Backpack.is_mergeable(id), "%s 参与合成链" % id)
	assert_eq(Backpack.min_layer_of("dragon_scale"), 30, "巨龙鳞甲(epic防具) min_layer 30，比武器类更晚")

func test_late_game_items_absent_before_min_layer() -> void:
	for i in range(60):
		var draft: Array = LootTable.draw_draft(3, 1)   # 第1层，早于所有新物品的 min_layer(15/30)
		for id in draft:
			assert_false(Backpack.base_id(id) in ["steel_sword", "mithril_staff", "holy_hammer", "dragon_scale"],
				"第1层不该摸到后期新装备")


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

func test_mergeable_items_drop_white_when_layer_unspecified() -> void:
	# 未指定层数(旧调用/旧测试兼容路径) → 合成链物品恒掉白；指定层数后见 test_tier_weights_by_layer 系列。
	for i in range(50):
		var draft: Array = LootTable.draw_draft(1)
		if draft.is_empty():
			continue
		var id: String = draft[0]
		if Backpack.is_mergeable(id):
			assert_eq(Backpack.item_tier(id), 0, "%s 未指定层数时恒掉白" % id)

func test_fixed_tier_items_drop_at_configured_tier() -> void:
	# decoy_mask 固定橙(4)；直接验证 LootTable 内部映射函数
	assert_eq(LootTable._drop_id("decoy_mask", -1), "decoy_mask@4", "诱敌面具掉落即带橙色后缀（固定色阶不受层数影响）")
	assert_eq(LootTable._drop_id("iron_sword", -1), "iron_sword", "未指定层数 → 合成链物品掉落是裸 base id（白）")

func test_price_unaffected_by_tier() -> void:
	# 两条轴独立：rarity(定价) 不因色阶变化
	assert_eq(LootTable.price("iron_sword"), LootTable.price("iron_sword@3"), "售价只看 rarity，不看色阶")


# ── BackpackPrepPanel：驮兽仓库内合成 + 背包内拖拽合成 ─────────────────────────
# （合成只有一条路：拖同款同色阶物品叠上去；旧版"⇪合成"按钮已随 pool 空间化下线）

func _warrior_entry() -> Dictionary:
	var h: Hero = HeroFactory.create(Hero.HeroClass.WARRIOR)
	h.entity_name = "战士"
	return { "hero": h, "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 }, "grid": {} }

func test_mule_merge_consumes_two_produces_one() -> void:
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "iron_sword", Vector2i(3,0): "iron_sword" }
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], mule, {})
	p.handle_drop("mule", Vector2i(0,0), p.grab_payload("mule", Vector2i(3,0)))
	assert_eq(mule.get(Vector2i(0,0)), "iron_sword@1", "2件白铁剑合成为1件绿铁剑")
	assert_false(mule.has(Vector2i(3,0)), "被消耗的那把腾空")
	assert_eq(mule.size(), 1, "驮兽里只剩合成结果这一件")

func test_mule_merge_fails_for_non_mergeable() -> void:
	# 非合成链物品（固定色阶）：拖同款叠上去不合成，按常规重叠规则拒绝，两件都原地不动
	var e := _warrior_entry()
	var mule := { Vector2i(0,0): "crit_gem", Vector2i(3,0): "crit_gem" }
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], mule, {})
	p.handle_drop("mule", Vector2i(0,0), p.grab_payload("mule", Vector2i(3,0)))
	assert_eq(mule.get(Vector2i(0,0)), "crit_gem", "非合成链物品即便同款落上去也不合成")
	assert_eq(mule.get(Vector2i(3,0)), "crit_gem", "落点被拒 → 源物品留在原位")

func test_bag_drag_onto_matching_item_merges() -> void:
	# 拖一把白铁剑落到另一把白铁剑上 → 合成为绿铁剑，原地
	var e := _warrior_entry()
	e["grid"][Vector2i(0, 0)] = "iron_sword"
	var mule := { Vector2i(0,0): "iron_sword" }
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], mule, {})
	var data = p.grab_payload("mule", Vector2i(0,0))
	p.handle_drop("bag", { "hero_index": 0, "cell": Vector2i(0, 0) }, data)
	assert_eq(e["grid"].get(Vector2i(0, 0)), "iron_sword@1", "落在同款上 → 原地合成为绿")
	assert_false(mule.has(Vector2i(0,0)), "驮兽那把被消耗")

func test_bag_drag_different_tier_does_not_merge() -> void:
	# 白铁剑拖到绿铁剑上：色阶不同，不合成，按常规重叠规则拒绝
	var e := _warrior_entry()
	e["grid"][Vector2i(0, 0)] = "iron_sword@1"   # 绿
	var mule := { Vector2i(0,0): "iron_sword" }   # 白
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], mule, {})
	var data = p.grab_payload("mule", Vector2i(0,0))
	p.handle_drop("bag", { "hero_index": 0, "cell": Vector2i(0, 0) }, data)
	assert_eq(e["grid"].get(Vector2i(0, 0)), "iron_sword@1", "色阶不同 → 不合成，原物不变")
	assert_eq(mule.get(Vector2i(0,0)), "iron_sword", "驮兽那把没被消耗（拒绝落地）")

func test_bag_can_drop_reports_merge_as_placeable() -> void:
	var e := _warrior_entry()
	e["grid"][Vector2i(0, 0)] = "iron_sword"
	var p = Prep.new()
	add_child_autofree(p)
	p.setup([e], { Vector2i(0,0): "iron_sword" }, {})
	assert_true(p.bag_can_drop(0, "iron_sword", { "kind": "mule", "anchor": Vector2i(0,0) }, Vector2i(0, 0)),
		"落点是可合成的同款 → 幽灵预览应报可放（绿）")


# ── 战力评分吃色阶 ────────────────────────────────────────────────────────────

func test_power_score_scales_with_tier() -> void:
	var white := PowerScore.item_power("iron_sword")
	var green := PowerScore.item_power("iron_sword@1")
	assert_almost_eq(green, white * 2.0, 0.01, "绿装战力分是白装的2倍")
