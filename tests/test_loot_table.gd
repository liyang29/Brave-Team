extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_loot_table — 战利品加权抽取（Step 4）
# ─────────────────────────────────────────────────────────────────────────────

const LootTable = preload("res://scripts/systems/LootTable.gd")
const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")


func test_every_item_has_known_rarity() -> void:
	for id in Backpack.ITEMS:
		var r: String = Backpack.ITEMS[id].get("rarity", "")
		assert_true(LootTable.RARITY_WEIGHTS.has(r), "%s 的 rarity '%s' 在权重表里" % [id, r])


func test_draw_returns_three_distinct_valid() -> void:
	# 注：抽出的 id 可能带色阶后缀（如 "decoy_mask@4"），合法性判断要走 base_id。
	var draft: Array = LootTable.draw_draft(3)
	assert_eq(draft.size(), 3, "抽出 3 件")
	var seen: Dictionary = {}
	for id in draft:
		assert_true(Backpack.ITEMS.has(Backpack.base_id(id)), "%s 是合法物品" % id)
		assert_false(seen.has(id), "同一次抽不重复：%s" % id)
		seen[id] = true


func test_draw_capped_by_pool_size() -> void:
	var huge: Array = LootTable.draw_draft(9999)
	assert_eq(huge.size(), Backpack.ITEMS.size(), "要的比池大 → 最多给满整池且不重复")


func test_price_by_rarity() -> void:
	assert_eq(LootTable.price("iron_sword"), 50, "普通=50")
	assert_eq(LootTable.price("longsword"), 120, "稀有=120")
	assert_eq(LootTable.price("crit_gem"), 250, "史诗=250")


func test_weighting_favors_common_over_epic() -> void:
	# 统计大量单抽，普通应明显多于史诗（概率性，给足样本 + 宽松阈值）
	var common := 0
	var epic := 0
	for i in range(600):
		var one: Array = LootTable.draw_draft(1)
		var r: String = Backpack.item_def(one[0]).get("rarity", "")
		if r == "common": common += 1
		elif r == "epic": epic += 1
	gut.p("common=%d  epic=%d" % [common, epic])
	assert_gt(common, epic, "普通掉落应明显多于史诗")
