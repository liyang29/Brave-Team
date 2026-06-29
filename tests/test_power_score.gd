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


# ── 英雄 / 队伍战力 ────────────────────────────────────────────────────────────

func _entry(grid: Dictionary) -> Dictionary:
	return { "base": { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 }, "grid": grid }

func test_hero_power_rises_with_gear() -> void:
	var bare := Power.hero_power(_entry({}))
	var armed := Power.hero_power(_entry({ Vector2i(0,0): "iron_sword" }))
	assert_gt(armed, bare, "装上铁剑→英雄战力上升")

func test_hero_power_counts_synergy() -> void:
	# 开刃(剑+磨刀石相邻) 应高于 只放一把剑
	var sword := Power.hero_power(_entry({ Vector2i(0,0): "iron_sword" }))
	var combo := Power.hero_power(_entry({ Vector2i(0,0): "iron_sword", Vector2i(1,0): "whetstone" }))
	assert_gt(combo, sword, "凑出开刃协同→战力更高")

func test_hero_power_counts_crit() -> void:
	var no_crit := Power.hero_power(_entry({ Vector2i(0,0): "iron_sword" }))
	var crit := Power.hero_power(_entry({ Vector2i(0,0): "iron_sword", Vector2i(1,0): "crit_gem" }))
	assert_gt(crit, no_crit, "加暴击宝石→战力更高（暴击折进输出）")

func test_team_power_sums_heroes() -> void:
	var a := _entry({ Vector2i(0,0): "iron_sword" })
	var b := _entry({ Vector2i(0,0): "shield" })
	assert_almost_eq(Power.team_power([a, b]), Power.hero_power(a) + Power.hero_power(b), 0.001,
		"队伍战力=各人之和")

func test_hero_and_enemy_same_scale() -> void:
	# 同尺度健全性检查：一个建好背包的英雄，量级应和怪物可比（不是天差地别）
	var hero := Power.hero_power(_entry({
		Vector2i(0,0): "iron_sword", Vector2i(1,0): "whetstone", Vector2i(0,1): "shield" }))
	var wolf := Power.enemy_power(MonsterFactory.create("wolf"))
	assert_gt(hero, 0.0, "英雄战力>0")
	assert_gt(hero, wolf * 0.2, "英雄与野狼同量级（非数量级差异）")
