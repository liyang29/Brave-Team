extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_monster_factory — MonsterFactory 数据表 + 工厂
# ─────────────────────────────────────────────────────────────────────────────


func test_create_reads_table() -> void:
	# 对照表本身断言（数值调参不会让本测试失效）
	var t: Dictionary = MonsterFactory.ENEMIES["wolf"]
	var e: EnemyData = MonsterFactory.create("wolf")
	assert_eq(e.entity_name, String(t["name"]), "名字来自表")
	assert_eq(e.base_max_hp, int(t["hp"]), "血来自表")
	assert_eq(e.base_attack, int(t["atk"]), "攻来自表")
	assert_eq(e.base_defense, int(t["def"]), "防来自表")
	assert_eq(e.preferred_row, "front", "默认前排")
	assert_false(e.is_ranged, "默认非远程")
	assert_eq(e.ai_type, EnemyData.AI_BASIC_ATTACK, "默认基础攻击 AI")


func test_magic_defaults_to_attack() -> void:
	var e: EnemyData = MonsterFactory.create("wolf")
	assert_eq(e.base_magic, e.base_attack, "未声明 magic → 默认=攻击")


func test_ranged_back_and_ai_from_table() -> void:
	var bug: EnemyData = MonsterFactory.create("venom_bug")
	assert_eq(bug.preferred_row, "back", "毒虫后排")
	assert_true(bug.is_ranged, "毒虫远程")
	var mage: EnemyData = MonsterFactory.create("dark_mage")
	assert_eq(mage.ai_type, EnemyData.AI_SPELLCASTER, "黑巫师施法 AI")
	var brute: EnemyData = MonsterFactory.create("brute")
	assert_eq(brute.ai_type, EnemyData.AI_AGGRESSIVE, "蛮兵激进 AI")


func test_name_override() -> void:
	var e: EnemyData = MonsterFactory.create("brute", "蛮兵·甲")
	assert_eq(e.entity_name, "蛮兵·甲", "覆盖显示名")
	assert_eq(e.base_max_hp, 90, "数值仍来自 brute 表项")


func test_each_create_is_new_instance() -> void:
	var a: EnemyData = MonsterFactory.create("wolf")
	var b: EnemyData = MonsterFactory.create("wolf")
	assert_ne(a, b, "每次 create 是新实例（可重复造同种怪）")


func test_create_group() -> void:
	var g: Array = MonsterFactory.create_group(["wolf", "wolf", "demon_lord"])
	assert_eq(g.size(), 3, "批量造 3 只")
	assert_eq(g[2].entity_name, "魔王", "第三只是魔王")


func test_unknown_id_fallback() -> void:
	var e: EnemyData = MonsterFactory.create("not_a_real_id")
	assert_not_null(e, "未知 id 不崩，返回占位 EnemyData")
	assert_true(e is EnemyData, "仍是 EnemyData")
