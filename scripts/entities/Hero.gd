class_name Hero extends Combatant

# ─────────────────────────────────────────────────────────────────────────────
# Hero — 英雄实例
#
# 继承关系：Hero → Combatant → GameEntity → Resource
#
# 与 EnemyData 的本质区别：
#   Hero 是"唯一个体"，有当前状态（HP、经验、装备）需要持久保存。
#   EnemyData 是"配置模板"，可以复用，不追踪运行时状态。
# ─────────────────────────────────────────────────────────────────────────────


# ── 常量 ─────────────────────────────────────────────────────────────────────

const MAX_LEVEL: int = 20

# 装备槽位名称（用字符串常量避免拼写错误）
const SLOT_HEAD:      String = "head"
const SLOT_CHEST:     String = "chest"
const SLOT_LEGS:      String = "legs"
const SLOT_FEET:      String = "feet"
const SLOT_WEAPON:    String = "weapon"
const SLOT_OFFHAND:   String = "offhand"
const SLOT_ACCESSORY: String = "accessory"

# 所有合法槽位（用于初始化和校验）
const ALL_SLOTS: Array[String] = [
	SLOT_HEAD, SLOT_CHEST, SLOT_LEGS, SLOT_FEET,
	SLOT_WEAPON, SLOT_OFFHAND, SLOT_ACCESSORY
]

# 每个等级段能拥有的最大技能数
# 1-5级: 2个，6-15级: 3个，16-20级: 4个
const MAX_SKILLS_BY_LEVEL: Array[int] = [
	0,             # 占位（没有0级）
	2,2,2,2,2,     # 1-5级
	3,3,3,3,3,3,3,3,3,3,  # 6-15级
	4,4,4,4,4      # 16-20级
]


# ── 职业 ──────────────────────────────────────────────────────────────────────

enum HeroClass {
	WARRIOR,  # 战士：近战，高HP高防
	MAGE,     # 法师：远程法术，高魔低防
	ROGUE,    # 盗贼：敏捷，速度快，单体高爆发
	ARCHER,   # 弓手：远程物理，均衡
	PRIEST,   # 牧师：神圣法术，中等防御，全体/穿透输出
}


# ── 状态 ──────────────────────────────────────────────────────────────────────

enum HeroStatus {
	IDLE,      # 空闲，可以被派遣（HP 可能不满）
	ON_QUEST,  # 执行任务中，不可派遣
	DEAD       # 永久死亡，从名单中移除
}

# 满意度等级（用于外部快速判断英雄行为倾向）
enum SatisfactionTier {
	SATISFIED,   # 75~100：全力战斗，接受任何任务
	NORMAL,      # 40~74 ：正常表现，偶尔推脱高危任务
	DISGRUNTLED, # 15~39 ：消极怠工，拒绝高危任务
	FURIOUS      # 0~14  ：触发离职对话
}


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 职业（由 HeroFactory 生成时确定，不可更改）
@export var hero_class: HeroClass = HeroClass.WARRIOR

# 当前状态
@export var status: HeroStatus = HeroStatus.IDLE

# 成长数据
@export var level: int      = 1
@export var experience: int = 0

# 当前 HP（持久保存，任务结束后保留受伤状态）
# 为什么不在 Combatant 里：EnemyData 是模板不追踪状态，只有 Hero 需要这个字段
@export var current_hp: int = 0

# 最大蓝量（由 HeroFactory 根据职业设置，决定英雄能释放多少次技能）
# current_mp 是战斗运行时状态，存在 BattleCombatant 里，每场战斗重置为满
@export var base_mp: int = 0

# 技能列表（存技能 ID 字符串，具体效果从数据文件读取）
# 初始 2 个，随等级解锁，最多 4 个
@export var skills: Array[String] = []

# 装备槽（Dictionary: 槽位名 → Equipment 实例，空槽存 null）
# 为什么用 Dictionary 而不是 7 个独立变量：
#   新增/删除槽位只改 ALL_SLOTS 常量，不需要同时改多个地方
@export var equipped_items: Dictionary = {}

# 满意度（0~100）：决定英雄的工作状态和行为
# 初始值 75（满意区间），低于 15 触发离职对话
@export var satisfaction: float = 75.0

# 私人钱包：英雄的个人积蓄，玩家不可控
# 来源：任务分成（英雄分到的那份）
# 用途：酒馆消费、自购装备/消耗品
@export var personal_wallet: int = 0

# 连续闲置（在家休息）天数（每天结算 +1，派遣归来后归零）
# 闲置不再扣满意度；低落英雄在家会缓慢回暖（HeroManager.tick_idle_turns 处理）
@export var idle_turns: int = 0

# 已完成训练的等级列表（每个等级只能训练一次，训练后追加当前 level）
@export var trained_levels: Array[int] = []

# 战斗策略（由 HeroFactory 根据职业注入，运行时不序列化）
var combat_strategy  # CombatStrategy，不加类型避免循环引用

# 属性计算器（装饰器模式，管理装备和 Buff 带来的属性加成）
# 为什么不在 Combatant 里：EnemyData 没有装备系统，不需要 StatBlock
var stat_block: StatBlock


# ── 初始化 ────────────────────────────────────────────────────────────────────

func _init() -> void:
	super._init()
	_init_equipment_slots()
	stat_block = StatBlock.new(self)
	current_hp = get_max_hp()

# 将所有槽位初始化为空（null）
func _init_equipment_slots() -> void:
	for slot in ALL_SLOTS:
		equipped_items[slot] = null


# ── 属性读取（通过 StatBlock 计算，含装备加成）────────────────────────────────

# 以下方法 override Combatant 的方式：
# Combatant 只有 base_xxx 原始值；Hero 通过 StatBlock 叠加装备加成后返回最终值

func get_max_hp() -> int:
	if stat_block == null:
		return base_max_hp
	return stat_block.calculate(StatBlock.Stat.MAX_HP)

func get_attack() -> int:
	return stat_block.calculate(StatBlock.Stat.ATTACK)

func get_defense() -> int:
	return stat_block.calculate(StatBlock.Stat.DEFENSE)

func get_speed() -> int:
	return stat_block.calculate(StatBlock.Stat.SPEED)

func get_magic() -> int:
	return stat_block.calculate(StatBlock.Stat.MAGIC)


# ── 状态查询 ──────────────────────────────────────────────────────────────────

func is_alive() -> bool:
	return current_hp > 0

func is_available() -> bool:
	# 可派遣条件：空闲状态 + 活着 + 满意度足够（≥ 50 才愿意接受派遣）
	# 注意：HP 不满时仍可派遣，玩家自己判断风险
	if not is_alive():
		return false
	if satisfaction < 50.0:
		return false
	return status == HeroStatus.IDLE

func get_hp_percent() -> float:
	var max_hp = get_max_hp()
	if max_hp <= 0:
		return 0.0
	return float(current_hp) / float(max_hp)


# ── 满意度 ────────────────────────────────────────────────────────────────────

# 获取当前满意度等级
func get_satisfaction_tier() -> SatisfactionTier:
	if satisfaction >= 75.0:
		return SatisfactionTier.SATISFIED
	elif satisfaction >= 40.0:
		return SatisfactionTier.NORMAL
	elif satisfaction >= 15.0:
		return SatisfactionTier.DISGRUNTLED
	else:
		return SatisfactionTier.FURIOUS

# 修改满意度（自动夹到 0~100 范围内）
# 返回修改后的实际值
func change_satisfaction(delta: float) -> float:
	satisfaction = clampf(satisfaction + delta, 0.0, 100.0)
	return satisfaction

# 英雄私人钱包收入（任务分成结算时调用）
func receive_share(amount: int) -> void:
	personal_wallet += amount

# 英雄私人支出（酒馆/自购装备时扣除，可能透支，由行为逻辑控制上限）
func spend_personal(amount: int) -> bool:
	if personal_wallet < amount:
		return false  # 钱不够
	personal_wallet -= amount
	return true


# ── 伤害与回复 ────────────────────────────────────────────────────────────────

# apply_damage：真正扣血（配合 Combatant.calculate_damage 使用）
#
# 用法示例（在 BattleCombatant 里）：
#   var dmg = target_hero.calculate_damage(attacker.get_attack())
#   target_hero.apply_damage(dmg)
func apply_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)

# heal：恢复 HP，不超过上限
func heal(amount: int) -> int:
	var max_hp   = get_max_hp()
	var actual   = min(amount, max_hp - current_hp)
	current_hp  += actual
	return actual  # 返回实际恢复量（供 UI 显示）

# full_heal：满血恢复（任务结束 or 特殊道具）
func full_heal() -> void:
	current_hp = get_max_hp()


# ── 装备 ──────────────────────────────────────────────────────────────────────

# equip：给英雄装备一件物品，返回被替换下来的旧装备（如果有）
func equip(item: Equipment) -> Equipment:
	var slot     = item.slot_name           # 从物品自身读取槽位名
	var old_item = equipped_items.get(slot) # 记录旧装备
	equipped_items[slot] = item
	stat_block.rebuild()                    # 重新计算属性
	return old_item

# unequip：卸下某槽位的装备，返回被卸下的物品（槽位为空则返回 null）
func unequip(slot: String) -> Equipment:
	if not ALL_SLOTS.has(slot):
		push_warning("Hero.unequip: 无效的槽位名 '%s'" % slot)
		return null
	var item             = equipped_items.get(slot)
	equipped_items[slot] = null
	stat_block.rebuild()
	return item

# get_equipped：获取某槽位当前的装备（可能为 null）
func get_equipped(slot: String) -> Equipment:
	return equipped_items.get(slot, null)


# ── 技能 ──────────────────────────────────────────────────────────────────────

# 当前等级允许的最大技能数
func get_max_skills() -> int:
	var idx = clamp(level, 1, MAX_LEVEL)
	return MAX_SKILLS_BY_LEVEL[idx]

# 能否再学一个技能
func can_learn_skill() -> bool:
	return skills.size() < get_max_skills()

# learn_skill：学习新技能（返回是否成功）
func learn_skill(skill_id: String) -> bool:
	if skills.has(skill_id):
		push_warning("Hero.learn_skill: 已拥有技能 '%s'" % skill_id)
		return false
	if not can_learn_skill():
		return false
	skills.append(skill_id)
	return true

# forget_skill：遗忘技能（用于替换）
func forget_skill(skill_id: String) -> bool:
	var idx = skills.find(skill_id)
	if idx == -1:
		return false
	skills.remove_at(idx)
	return true


# ── 成长 ──────────────────────────────────────────────────────────────────────

# 升到下一级所需的总经验值
# 公式：level × 100（1级→2级需100，2级→3级需200，以此类推）
func get_exp_required() -> int:
	return level * 100

# add_experience：增加经验值，自动处理升级（可连续升多级）
# 返回升级次数（0 = 没升级）
func add_experience(amount: int) -> int:
	if status == HeroStatus.DEAD:
		return 0
	experience  += amount
	var level_ups = 0
	while level < MAX_LEVEL and experience >= get_exp_required():
		experience -= get_exp_required()
		_level_up()
		level_ups  += 1
	return level_ups

# 升级：提升等级，属性成长（具体成长值由职业模板决定，这里先用固定值占位）
func _level_up() -> void:
	level += 1
	# 属性成长（TODO：后续从职业模板数据读取成长系数）
	base_max_hp  += 10
	base_attack  += 2
	base_defense += 1
	base_speed   += 1
	if hero_class == HeroClass.MAGE:
		base_magic += 3
	# 升级后 HP 不自动满（保持当前 HP，玩家需要休养）
	# 但上限提升了，所以相对比例变好了
	stat_block.rebuild()


# ── 存档 ──────────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var data              = super.to_dict()
	data["hero_class"]    = hero_class
	data["status"]        = status
	data["level"]         = level
	data["experience"]    = experience
	data["current_hp"]    = current_hp
	data["satisfaction"]  = satisfaction
	data["personal_wallet"] = personal_wallet
	data["idle_turns"]     = idle_turns
	data["trained_levels"] = trained_levels.duplicate()
	data["skills"]         = skills.duplicate()
	# 装备槽：存每个物品的 instance_id（null 槽位存空字符串）
	var equipped_data: Dictionary = {}
	for slot in ALL_SLOTS:
		var item = equipped_items.get(slot)
		equipped_data[slot] = item.instance_id if item else ""
	data["equipped_items"] = equipped_data
	return data

func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	hero_class       = data.get("hero_class",      HeroClass.WARRIOR)
	status           = data.get("status",          HeroStatus.IDLE)
	level            = data.get("level",           1)
	experience       = data.get("experience",      0)
	current_hp       = data.get("current_hp",      get_max_hp())
	satisfaction     = data.get("satisfaction",    75.0)
	personal_wallet  = data.get("personal_wallet", 0)
	idle_turns       = data.get("idle_turns",       0)
	var raw_tl: Array = data.get("trained_levels", [])
	trained_levels.clear()
	for lv in raw_tl:
		trained_levels.append(int(lv))
	var raw_skills: Array = data.get("skills", [])
	skills.clear()
	for s in raw_skills:
		skills.append(str(s))
	# 装备槽的物品引用由 DataManager 在加载完所有物品后二次恢复
	# 此处只还原为空，实际恢复逻辑在 DataManager.restore_hero_equipment()
	_init_equipment_slots()
