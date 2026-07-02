extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# EncounterData — Boss 专属"战斗输入"（R6 建议范围收窄版：只做 Boss 需要的最小子集）
#
# 不是完整的"战斗入口包装类"——非全歼胜利条件/护送/存活N回合等留到以后真需要时再扩。
# 这里只解决一件事：把"这场战斗的 Boss 是谁、有没有阶段转换/召唤援军"这份数据，
# 从地图节点（MapGenerator 生成）带到战斗（BattleSimulator.simulate 的可选第三参数）。
#
# boss_config schema（BattleSimulator.simulate 的第三参数）：
#   boss_index  : int    —— enemies 数组里第几个是 Boss（默认 0）
#   base_skills : Array[String] —— Boss 开局就会的技能（对应 SkillTable 技能 id）
#   skill_cds   : { skill_id: cd_turns } —— 可选，给 Boss 技能加冷却（复用现成冷却机制）
#   phases      : Array[{ hp_pct, atk_mult, def_mult, extra_skills }]
#                 —— 血量跌破 hp_pct 时触发：属性乘倍率 + 解锁新技能。按 hp_pct 从高到低排列。
#   summons     : Array[{ every, group, max_total }]
#                 —— 每 every 回合召唤一组 group（MonsterFactory id），召到 max_total 为止。
#
# 3 个 Boss 演示三种组合：石卫王=纯阶段转换 / 毒沼领主=纯召唤援军 / 深渊统领=两者都要。
# 加/调 Boss = 改这份数据，不用碰 BattleSimulator 的阶段/召唤引擎代码。
# ─────────────────────────────────────────────────────────────────────────────

const MID_BOSS_PROFILES: Dictionary = {
	20: {
		"name": "石卫王",
		"group": ["stone_guard_king"],
		"gold": 70,
		"boss_config": {
			"boss_index": 0,
			"base_skills": ["boss_smash"],
			"skill_cds": { "boss_smash": 3 },
			"phases": [
				{ "hp_pct": 0.5, "atk_mult": 1.3, "extra_skills": [] },
			],
			"summons": [],
		},
	},
	30: {
		"name": "毒沼领主",
		"group": ["venom_lord"],
		"gold": 90,
		"boss_config": {
			"boss_index": 0,
			"base_skills": ["boss_venom_nova"],
			"skill_cds": { "boss_venom_nova": 3 },
			"phases": [],
			"summons": [
				{ "every": 4, "group": ["venom_bug"], "max_total": 6 },
			],
		},
	},
	40: {
		"name": "深渊统领",
		"group": ["abyss_overlord"],
		"gold": 120,
		"boss_config": {
			"boss_index": 0,
			"base_skills": ["boss_abyss_strike"],
			"skill_cds": { "boss_abyss_strike": 4, "boss_frenzy": 5 },
			"phases": [
				{ "hp_pct": 0.6, "atk_mult": 1.2, "extra_skills": ["boss_frenzy"] },
				{ "hp_pct": 0.3, "atk_mult": 1.3, "extra_skills": [] },
			],
			"summons": [
				{ "every": 5, "group": ["bandit", "ranger"], "max_total": 4 },
			],
		},
	},
}


## 该层是否是中程 Boss 层。
static func is_mid_boss_layer(layer: int) -> bool:
	return MID_BOSS_PROFILES.has(layer)

## 取某层的中程 Boss 档案（未配置返回空）。
static func profile_for_layer(layer: int) -> Dictionary:
	return MID_BOSS_PROFILES.get(layer, {})
