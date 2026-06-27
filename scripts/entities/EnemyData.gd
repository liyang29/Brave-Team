class_name EnemyData extends Combatant

# ─────────────────────────────────────────────────────────────────────────────
# EnemyData — 敌人配置模板（Resource）
#
# 继承关系：EnemyData → Combatant → GameEntity → Resource
#
# 与 Hero 的本质区别：
#   EnemyData 是"数据模板"，可以复用，同一种敌人可以有多个战斗副本。
#   它不追踪运行时状态（没有 current_hp）——战斗时由 BattleCombatant 包装。
#
# 使用方式（数据驱动）：
#   resources/data/enemies/
#     snake.tres   ← EnemyData, level=1, ai_type="basic_attack"
#     wolf.tres    ← EnemyData, level=3, ai_type="aggressive"
#     golem.tres   ← EnemyData, level=6, ai_type="tank"
#   唯一一个 EnemyNode.gd 读取不同的 .tres，不需要 100 个脚本文件。
#
# 掉落设计（分层掉落）：
#   - normal_pool  : 每次战斗必定 roll，概率较高（低价值物品/金币）
#   - rare_pool    : 每次战斗 roll 一次，概率较低（装备/材料）
#   - elite_pool   : 精英敌人专用，概率极低（高价值装备）
#
#   每个掉落池是 Array[Dictionary]，每条记录格式：
#   {
#     "template_id": "iron_sword",  # 物品模板 ID，空字符串表示纯金币
#     "chance": 0.3,                # 掉落概率（0.0~1.0）
#     "gold_min": 0,                # 金币奖励最小值（物品类填0）
#     "gold_max": 0,                # 金币奖励最大值
#   }
# ─────────────────────────────────────────────────────────────────────────────


# ── AI 类型常量 ───────────────────────────────────────────────────────────────

# 这些字符串对应 EnemyAIFactory.create(ai_type) 支持的类型
const AI_BASIC_ATTACK = "basic_attack"  # 普通攻击：攻击血量最多的目标
const AI_AGGRESSIVE   = "aggressive"    # 凶猛：优先击杀血量最低的目标
const AI_TANK         = "tank"          # 坦克：自身防御高，嘲讽吸引仇恨
const AI_SPELLCASTER  = "spellcaster"  # 法术：使用技能，攻击防御最低的目标
const AI_POISON_CASTER = "poison_caster" # 剧毒术士（方案 B）：后排放毒，需远程/突袭点掉
const AI_COLUMN_PIERCER = "column_piercer" # 列穿刺手（方案 B 网格）：穿整列，惩罚堆叠


# ── 基础字段 ──────────────────────────────────────────────────────────────────

# 敌人等级：用于任务系统匹配难度、玩家判断风险
# 建议范围：1~20，对应英雄等级上限
@export var level: int = 1

# AI 行为类型（填写上方 AI_xxx 常量之一）
@export var ai_type: String = AI_BASIC_ATTACK

# 图片资源路径（供 EnemyNode 加载 Sprite）
# 例如："res://resources/art/enemies/snake.png"
# 视觉系统未定前可暂时留空
@export var texture_path: String = ""


# ── 站位 / 角色 / 威胁（方案 B：编队解谜自走棋）──────────────────────────────
# preferred_row : 布阵倾向 "front"（前排，挡刀）/ "back"（后排，躲在前排后面）
# is_ranged     : true = 远程，可攻击敌方后排；false = 近战，需先清前排
# role          : 角色标签 "armored"/"poison"/"swarm"/"caster"/"bruiser"/"corrupted"，空=普通
# threats       : 战前展示给玩家的威胁 key 列表（如 ["poison"]），供编队界面提示
# 默认 front + 非远程 + 无角色 → 旧敌人行为完全不变。
@export var preferred_row: String = "front"
@export var preferred_col: int = 0
@export var is_ranged: bool = false
@export var role: String = ""
@export var threats: Array = []


# ── 奖励字段 ──────────────────────────────────────────────────────────────────

# 击败后给予队伍的经验值（平均分配给存活英雄）
@export var exp_reward: int = 10

# 击败后给予队伍的金币奖励（在分成前合并进任务总奖励）
# 使用随机区间增加趣味性
@export var gold_reward_min: int = 5
@export var gold_reward_max: int = 15


# ── 掉落表 ────────────────────────────────────────────────────────────────────

# 普通掉落池：每次战斗必定 roll，适合放低价值物品、小额金币
# 每条记录格式见文件头注释
@export var normal_pool: Array = []

# 稀有掉落池：每次战斗有一次 roll 机会，适合装备、材料
@export var rare_pool: Array = []

# 精英掉落池：极低概率，适合高价值装备或特殊材料
# 通常只有 Boss 级敌人才填这里
@export var elite_pool: Array = []


# ── 工具方法 ──────────────────────────────────────────────────────────────────

# roll_drops：模拟一次战斗掉落，返回中奖的掉落条目列表
# 由 BattleSimulator 在战斗结算时调用
# 返回值：Array[Dictionary]（中奖的那些条目原样返回，ItemFactory 再根据 template_id 创建物品）
func roll_drops() -> Array:
	var results: Array = []
	_roll_pool(normal_pool, results)
	_roll_pool(rare_pool,   results)
	_roll_pool(elite_pool,  results)
	return results

# roll_gold：随机生成本次战斗的金币掉落数量
func roll_gold() -> int:
	if gold_reward_max <= gold_reward_min:
		return gold_reward_min
	return randi_range(gold_reward_min, gold_reward_max)


# ── 私有工具 ──────────────────────────────────────────────────────────────────

func _roll_pool(pool: Array, results: Array) -> void:
	for entry in pool:
		var chance: float = entry.get("chance", 0.0)
		if randf() <= chance:
			results.append(entry)


# ── 存档支持（模板数据不需要存档，但保留接口以备不时之需）────────────────────

func to_dict() -> Dictionary:
	var data          = super.to_dict()
	data["level"]     = level
	data["ai_type"]   = ai_type
	data["texture_path"]    = texture_path
	data["exp_reward"]      = exp_reward
	data["gold_reward_min"] = gold_reward_min
	data["gold_reward_max"] = gold_reward_max
	data["normal_pool"]     = normal_pool.duplicate(true)
	data["rare_pool"]       = rare_pool.duplicate(true)
	data["elite_pool"]      = elite_pool.duplicate(true)
	data["preferred_row"]   = preferred_row
	data["preferred_col"]   = preferred_col
	data["is_ranged"]       = is_ranged
	data["role"]            = role
	data["threats"]         = threats.duplicate(true)
	return data

func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	level           = data.get("level",           1)
	ai_type         = data.get("ai_type",         AI_BASIC_ATTACK)
	texture_path    = data.get("texture_path",    "")
	exp_reward      = data.get("exp_reward",      10)
	gold_reward_min = data.get("gold_reward_min", 5)
	gold_reward_max = data.get("gold_reward_max", 15)
	normal_pool     = data.get("normal_pool",     []).duplicate(true)
	rare_pool       = data.get("rare_pool",       []).duplicate(true)
	elite_pool      = data.get("elite_pool",      []).duplicate(true)
	preferred_row   = data.get("preferred_row",   "front")
	preferred_col   = data.get("preferred_col",   0)
	is_ranged       = data.get("is_ranged",       false)
	role            = data.get("role",            "")
	threats         = data.get("threats",         []).duplicate(true)
