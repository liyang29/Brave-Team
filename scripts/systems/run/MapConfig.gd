extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# MapConfig — 分支地图生成的【唯一配置源】（改数据不改逻辑）
#
# MapGenerator.generate(config) 吃这份配置产出地图。调层数/宽度/密度/权重/内容池
# 全在这里改，生成器代码零改动。加节点类型进图 = types 加一行 + NodeTypes 注册一行
# （生成器遍历 types，不写死类型名）；event 未注册前不会出现（生成器按注册表过滤）。
#
# 故意不带 class_name（preload 引入），同 NodeTypes/LootTable/BackpackModel 路子，
# 避免全局类缓存时序问题。
# ─────────────────────────────────────────────────────────────────────────────

const DEFAULT: Dictionary = {
	# ── 骨架规模 ──────────────────────────────────────────────────────────────
	"layers": 9,          # 总层数（含首层村庄 + 末层魔王）。改层数就改这一个数。
	"max_width": 4,       # 每层最大宽度（列数上限）
	"paths": 6,           # 铺几条随机路径（越多图越密、汇合越多）

	# ── 固定锚点（首层 / 魔王前一层 / 末层）──────────────────────────────────
	"fixed": { "first": "village", "pre_boss": "rest", "last": "boss" },

	# ── 中间层节点类型分布（加类型 = 加一行；约束是通用规则不写死类型）────────
	#   weight          : 基础权重（越大越常见）
	#   min_layer       : 最早出现的层（elite 太早太难）
	#   weight_per_layer: 每深一层权重加成（elite 后倾）
	#   min_gap         : 与上一个同类型节点的最小层间隔（防连续回血/连续补给）
	"types": {
		"battle":  { "weight": 10 },
		"event":   { "weight": 4 },
		"rest":    { "weight": 3, "min_gap": 2 },
		"village": { "weight": 2, "min_gap": 3 },
		"elite":   { "weight": 3, "min_layer": 3, "weight_per_layer": 1 },
	},

	# ── 内容池（数据驱动；加遭遇 = 加一行）──────────────────────────────────
	# 怪物 id 见 MonsterFactory.ENEMIES。
	"battle_groups": [
		["wolf", "wolf"],
		["venom_bug", "stone_guard"],
		["bandit", "ranger"],
		["wolf", "bandit"],
	],
	"elite_groups": [
		["stone_guard", "bandit"],
		["bandit", "ranger", "wolf"],
	],
	"boss_group": ["demon_lord", "claw_minion"],

	# 各类型金币奖励
	"gold": { "battle": 20, "elite": 45, "boss": 100 },

	# 显示名（按类型随机取一个；首层村庄/末层魔王在生成器里另给固定名）
	"names": {
		"battle":  ["林间遭遇", "废墟伏击", "峡谷遭遇", "荒野遭遇"],
		"elite":   ["精英·石卫队", "精英·悍匪团"],
		"village": ["村镇", "驿站", "集市"],
		"rest":    ["泉水", "营火"],
		"event":   ["神秘事件", "岔路口"],
		"boss":    "魔王城",
	},
}
