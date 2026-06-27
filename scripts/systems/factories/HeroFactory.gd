class_name HeroFactory

# class_name 注册时序不稳定，新增职业策略用 preload 显式引入
const PriestStrategyScript = preload("res://scripts/systems/combat/strategies/PriestStrategy.gd")

# ─────────────────────────────────────────────────────────────────────────────
# HeroFactory — 英雄生成工厂（纯静态工具类）
#
# 职责：根据职业创建随机英雄实例，注入策略对象。
# 使用方：HeroManager（招募流程）、测试代码
#
# 随机化规则：
#   属性  = 职业基础值 × 随机系数（0.8~1.2，即 ±20%）
#   名字  = 从名字池随机抽取（与已有英雄不重复，重复时允许重名）
#   技能  = 从职业技能池中随机抽取 2 个（不重复）
# ─────────────────────────────────────────────────────────────────────────────


# ── 名字池（按语言分组）──────────────────────────────────────────────────────

const NAME_POOL_ZH: Array[String] = [
	"南宫烈", "慕容翎", "上官羽", "独孤剑", "欧阳雪", "令狐尘",
	"迦南", "朝歌", "苍岚", "玄冥", "若尘", "辰渊", "白鹿", "青雀",
	"铁锤", "月影", "烈焰", "霜风", "暗夜", "晨曦", "铁拳", "流云",
	"苍穹", "紫电", "寒刃", "碧落", "风华", "墨尘", "银霜", "赤焰",
]

const NAME_POOL_EN: Array[String] = [
	"Theron", "Garrick", "Lyra", "Isolde", "Brennan", "Seraphine",
	"Roland", "Mira", "Drake", "Vessa", "Aldric", "Nora",
	"Caden", "Elara", "Finn", "Zara", "Marcus", "Elia",
	"Tobias", "Seren", "Bastian", "Wren", "Corvin", "Isla",
	"Hadley", "Oryn", "Petra", "Leif", "Sylvie", "Darian",
]

# 随机浮动系数范围（±20%）
const STAT_VARIANCE: float = 0.20


# ── 职业配置（基础属性 + 技能池）────────────────────────────────────────────

# 每个职业的基础属性（HeroFactory 内部使用，不对外暴露）
const CLASS_BASE_STATS: Dictionary = {
	Hero.HeroClass.WARRIOR: {
		"base_max_hp":  120,
		"base_attack":  15,
		"base_defense": 10,
		"base_speed":   8,
		"base_magic":   0,
		"base_mp":      60,  # 60←40：配合技能费用下调，确保 5 回合内保持技能节奏
	},
	Hero.HeroClass.MAGE: {
		"base_max_hp":  70,
		"base_attack":  8,
		"base_defense": 4,
		"base_speed":   13, # 13←10：脆皮需先手，速度应高于弓手(12)，仅次于盗贼(16)
		"base_magic":   18,
		"base_mp":      80,  # 高蓝量，魔法职业核心资源
	},
	Hero.HeroClass.ROGUE: {
		"base_max_hp":  90,
		"base_attack":  14,
		"base_defense": 6,
		"base_speed":   16,
		"base_magic":   0,
		"base_mp":      50,  # 中等蓝量
	},
	Hero.HeroClass.ARCHER: {
		"base_max_hp":  100,
		"base_attack":  12,
		"base_defense": 7,
		"base_speed":   12,
		"base_magic":   0,
		"base_mp":      50,  # 中等蓝量
	},
	Hero.HeroClass.PRIEST: {
		"base_max_hp":  85,
		"base_attack":  6,
		"base_defense": 7,
		"base_speed":   9,
		"base_magic":   16,
		"base_mp":      80,  # 高蓝量，治疗需要大量蓝量支撑
	},
}

# 每个职业的技能 ID 池（英雄从中随机抽2个作为初始技能）
# 技能 ID 是占位字符串，等技能系统实现时对应具体效果
const CLASS_SKILL_POOLS: Dictionary = {
	Hero.HeroClass.WARRIOR: [
		"slash",        # 斩击：单体物理
		"shield_bash",  # 盾击：伤害+眩晕
		"battle_cry",   # 战吼：提升自身攻击
		"cleave",       # 横扫：范围物理
	],
	Hero.HeroClass.MAGE: [
		"fireball",     # 火球：单体魔法
		"ice_lance",    # 冰矛：单体+减速
		"arcane_bolt",  # 奥术箭：快速施法
		"mana_surge",   # 法力涌动：全体魔法
	],
	Hero.HeroClass.ROGUE: [
		"backstab",      # 背刺：高爆发单体
		"shadow_strike", # 暗影打击：无视部分防御
		"poison_blade",  # 毒刃：持续伤害
		"evasion",       # 闪避：提升回避率
	],
	Hero.HeroClass.ARCHER: [
		"precise_shot",   # 精准射击：单体高伤
		"multi_shot",     # 多箭齐发：范围物理
		"piercing_arrow", # 穿刺箭：穿透防御
		"eagle_eye",      # 鹰眼：提升命中和暴击
	],
	Hero.HeroClass.PRIEST: [
		"holy_smite",    # 圣光击：穿透半防御魔法伤害
		"divine_wrath",  # 神圣之怒：无视防御魔法伤害
		"radiance",      # 圣光辐射：全体魔法伤害
		"blessing",      # 神圣祝福：提升自身防御
		"holy_heal",     # 圣愈术：治疗血量最少的友军
	],
}

# 每个职业对应的战斗策略类
const CLASS_STRATEGIES: Dictionary = {
	Hero.HeroClass.WARRIOR: "WarriorStrategy",
	Hero.HeroClass.MAGE:    "MageStrategy",
	Hero.HeroClass.ROGUE:   "RogueStrategy",
	Hero.HeroClass.ARCHER:  "ArcherStrategy",
}


# ── 主工厂方法 ────────────────────────────────────────────────────────────────

# create：生成一个指定职业的随机英雄
# 如果 hero_class 传 -1，则随机选择职业
static func create(hero_class: int = -1) -> Hero:
	var cls = hero_class if hero_class >= 0 else _random_class()

	var hero       = Hero.new()
	hero.hero_class = cls
	hero.entity_name = _pick_name()

	_apply_random_stats(hero, cls)
	_apply_random_skills(hero, cls)
	_inject_strategy(hero, cls)

	# StatBlock 在 Hero._init() 里已创建，初始化后重建确保装备加成正确
	hero.stat_block.rebuild()
	# 满血出场
	hero.current_hp = hero.get_max_hp()

	return hero

# create_random：随机职业的英雄（快捷方法）
static func create_random() -> Hero:
	return create(-1)


# ── 私有方法 ──────────────────────────────────────────────────────────────────

static func _random_class() -> Hero.HeroClass:
	var classes = [
		Hero.HeroClass.WARRIOR,
		Hero.HeroClass.MAGE,
		Hero.HeroClass.ROGUE,
		Hero.HeroClass.ARCHER,
		Hero.HeroClass.PRIEST,
	]
	return classes[randi() % classes.size()]

static func _pick_name() -> String:
	var pool := NAME_POOL_EN if TranslationServer.get_locale().begins_with("en") \
				else NAME_POOL_ZH
	return pool[randi() % pool.size()]

# 根据职业基础值 ± 20% 随机浮动生成属性
static func _apply_random_stats(hero: Hero, cls: Hero.HeroClass) -> void:
	var base = CLASS_BASE_STATS[cls]
	for stat_key in base:
		var base_val: int = base[stat_key]
		var variance = base_val * STAT_VARIANCE
		# randi_range 要求整数，换成 randf_range 后取整
		var actual = base_val + int(randf_range(-variance, variance))
		# 保证最小值为1（魔力为0的职业除外）
		if stat_key == "base_magic":
			actual = max(0, actual)
		else:
			actual = max(1, actual)
		hero.set(stat_key, actual)

# 从职业技能池随机抽2个不重复技能
static func _apply_random_skills(hero: Hero, cls: Hero.HeroClass) -> void:
	var pool: Array = CLASS_SKILL_POOLS[cls].duplicate()
	pool.shuffle()
	var count = min(2, pool.size())  # 初始最多2个
	for i in range(count):
		hero.learn_skill(pool[i])

# 注入对应职业的战斗策略实例
static func _inject_strategy(hero: Hero, cls: Hero.HeroClass) -> void:
	match cls:
		Hero.HeroClass.WARRIOR: hero.combat_strategy = WarriorStrategy.new()
		Hero.HeroClass.MAGE:    hero.combat_strategy = MageStrategy.new()
		Hero.HeroClass.ROGUE:   hero.combat_strategy = RogueStrategy.new()
		Hero.HeroClass.ARCHER:  hero.combat_strategy = ArcherStrategy.new()
		Hero.HeroClass.PRIEST:  hero.combat_strategy = PriestStrategyScript.new()
