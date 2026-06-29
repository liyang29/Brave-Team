extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_power_score — 战力分函数（断言"相对排序"合理，不锁死具体数值，方便调权重）
# ─────────────────────────────────────────────────────────────────────────────

const Power = preload("res://scripts/systems/PowerScore.gd")
const Backpack = preload("res://scripts/experiments/BackpackModel.gd")


# ── 物品战力 ──────────────────────────────────────────────────────────────────

func test_item_power_stronger_item_scores_higher() -> void:
	# 长剑(攻8) 应高于 铁剑(攻6)
	assert_gt(Power.item_power("longsword"), Power.item_power("iron_sword"), "长剑>铁剑")

func test_item_power_def_worth_more_than_hp() -> void:
	# 锁甲(防6血10) 应高于 皮甲(防3血15)——防御每点更值
	assert_gt(Power.item_power("chainmail"), Power.item_power("leather"), "锁甲>皮甲")

func test_item_power_crit_and_skillbook_nonzero() -> void:
	assert_gt(Power.item_power("crit_gem"), 0.0, "暴击宝石有分")
	assert_gt(Power.item_power("book_fireball"), 0.0, "技能书有分")

func test_item_power_unknown_is_zero() -> void:
	assert_eq(Power.item_power("not_a_real_item"), 0.0, "未知物品=0")

func test_item_power_roughly_tracks_rarity() -> void:
	# 史诗级暴击件应高于一件普通白板（粗略，rarity 越高一般越强）
	assert_gt(Power.item_power("berserk_ring"), Power.item_power("whetstone"), "狂战戒>磨刀石")


# ── 单位 / 怪物战力 ────────────────────────────────────────────────────────────

func test_unit_power_monotonic_in_hp() -> void:
	var low := Power.unit_power(50, 10, 5, 0, 10)
	var high := Power.unit_power(100, 10, 5, 0, 10)
	assert_gt(high, low, "血更多→战力更高")

func test_unit_power_monotonic_in_offense() -> void:
	var low := Power.unit_power(80, 8, 5, 0, 10)
	var high := Power.unit_power(80, 16, 5, 0, 10)
	assert_gt(high, low, "攻更高→战力更高")

func test_unit_power_uses_max_of_atk_magic() -> void:
	# 法系单位(高魔零攻)应被算出可观战力（用 max(atk,magic)）
	var caster := Power.unit_power(60, 0, 3, 18, 12)
	assert_gt(caster, 0.0, "纯法系也有战力(用魔力当输出)")

func test_enemy_power_boss_stronger_than_trash() -> void:
	var boss: EnemyData = MonsterFactory.create("demon_lord")
	var trash: EnemyData = MonsterFactory.create("wolf")
	assert_gt(Power.enemy_power(boss), Power.enemy_power(trash), "魔王>野狼")

func test_group_power_sums() -> void:
	var one: EnemyData = MonsterFactory.create("wolf")
	var two: Array = [MonsterFactory.create("wolf"), MonsterFactory.create("wolf")]
	assert_almost_eq(Power.group_power(two), Power.enemy_power(one) * 2.0, 0.001, "两只野狼=单只×2")
