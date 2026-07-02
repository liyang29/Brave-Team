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
	# 2026-07：9→45（塞下 3 个中程 Boss @ 层20/30/40 + 终点魔王），下面 5 张"按层数"的表
	# （门槛/分档/缩放系数）跟着按比例重标定过，改这个数还要一并想清楚要不要重标定它们。
	"layers": 45,          # 总层数（含首层村庄 + 末层魔王）。改层数就改这一个数。
	"max_width": 4,        # 每层最大宽度（列数上限）
	"paths": 8,            # 铺几条随机路径（越多图越密、汇合越多；层数变多了适度加密）

	# ── 固定锚点（首层 / 魔王前一层 / 末层 / 中程Boss层）───────────────────────
	"fixed": { "first": "village", "pre_boss": "rest", "last": "boss" },
	# 中程 Boss：这几层强制单节点（跟 pre_boss/last 一样是"漏斗"锚点，必经）。
	# 加/挪中程 Boss = 改这个数组 + EncounterData.MID_BOSS_PROFILES 加对应 id。
	"mid_boss_layers": [20, 30, 40],

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
		"elite":   { "weight": 3, "min_layer": 15, "weight_per_layer": 1 },
	},

	# ── 内容池（数据驱动；加遭遇 = 加一行）──────────────────────────────────
	# 怪物 id 见 MonsterFactory.ENEMIES。
	# ── 分档怪池：按节点所在层选对应档（第一个 max_layer≥层 的档）──────────────
	# 加档/加怪 = 往对应档 groups 加一行；后期档想有质变就加新怪到 MonsterFactory。
	"battle_tiers": [
		{ "max_layer": 10,  "groups": [ ["wolf", "wolf"], ["venom_bug", "wolf"] ] },
		{ "max_layer": 25,  "groups": [ ["venom_bug", "stone_guard"], ["wolf", "bandit"] ] },
		{ "max_layer": 999, "groups": [ ["bandit", "ranger"], ["stone_guard", "bandit"] ] },
	],
	"elite_tiers": [
		{ "max_layer": 22,  "groups": [ ["stone_guard", "bandit"] ] },
		{ "max_layer": 999, "groups": [ ["bandit", "ranger", "wolf"], ["stone_guard", "stone_guard"] ] },
	],
	"boss_group": ["demon_lord", "claw_minion"],

	# ── 深度缩放：第 N 层的怪按系数放大属性（数值 ramp）──────────────────────────
	# enabled=总开关（false=整体关掉）；各 *_per_layer=每层增幅（0=该属性不缩放，即"关掉这一样"）。
	# skip_types=不吃缩放的节点类型（Boss 手调终点门槛，数值自成一档，不跟着按层再叠一层缩放）。
	# 第 N 层某属性 = 基础 × (1 + N × 该系数)。防御默认小幅（缩太多会让战斗变拖）。
	# 系数比旧版(0.05/0.04/0.02·9层)减半：层数拉长到45后，同样的曲线该在更长的跨度上展开，
	# 不是终点层数暴涨到原来5倍那么猛——具体强度用 test_depth_scaling 的曲线数据核对。
	"enemy_scale": {
		"enabled": true,
		"hp_per_layer": 0.025,
		"atk_per_layer": 0.02,
		"def_per_layer": 0.01,
		"skip_types": ["boss", "mid_boss"],
	},

	# 各类型金币奖励
	"gold": { "battle": 20, "elite": 45, "boss": 100, "mid_boss": 70 },

	# 显示名（按类型随机取一个；首层村庄/末层魔王/中程Boss在生成器里另给固定名）
	"names": {
		"battle":  ["林间遭遇", "废墟伏击", "峡谷遭遇", "荒野遭遇"],
		"elite":   ["精英·石卫队", "精英·悍匪团"],
		"village": ["村镇", "驿站", "集市"],
		"rest":    ["泉水", "营火"],
		"event":   ["神秘事件", "岔路口"],
		"boss":    "魔王城",
	},
}
