class_name Combatant extends GameEntity

# ─────────────────────────────────────────────────────────────────────────────
# Combatant — 所有战斗单位的数据基类
#
# 继承关系：
#   Combatant → Hero       （英雄实例，有 current_hp、StatBlock、装备）
#   Combatant → EnemyData  （敌人模板，只有基础数值，不追踪运行状态）
#
# 设计原则：
#   Combatant 只存"出生时就定下来的基础数值"。
#   运行时变化的状态（当前HP、临时Buff）由 Hero 或 BattleCombatant 管理。
#
# 为什么有 base_magic 但战士/弓手等职业是0？
#   统一接口比分支判断更简洁。StatBlock 计算时 base_magic=0 的结果就是0，
#   不会影响任何逻辑，也不需要在 BattleSimulator 里做 if has_magic 判断。
# ─────────────────────────────────────────────────────────────────────────────


# ── 基础属性 ──────────────────────────────────────────────────────────────────
# 前缀 base_ 明确表示"这是原始值，不含装备/Buff加成"
# 最终属性由 Hero 的 StatBlock 动态计算（含加成）

@export var base_max_hp:  int = 100
@export var base_attack:  int = 10
@export var base_defense: int = 5
@export var base_speed:   int = 10
@export var base_magic:   int = 0   # 非法师职业默认为 0


# ── 伤害计算 ──────────────────────────────────────────────────────────────────

# calculate_damage：根据传入攻击力和自身防御，计算实际承受的伤害值
#
# 为什么在 Combatant 里，而不是在 Hero 里？
#   伤害公式对英雄和敌人通用。放在父类里，BattleCombatant 可以直接调用，
#   不需要区分对象是 Hero 还是 EnemyData。
#
# 为什么只"计算"而不"扣血"？
#   Combatant 没有 current_hp（EnemyData 是模板，不追踪状态）。
#   实际扣血由 Hero.apply_damage() 或 BattleCombatant.apply_damage() 负责。
#
# 公式：实际伤害 = 攻击力 - 防御力的一半，最低为 1（不会造成0伤害）
func calculate_damage(incoming_attack: int) -> int:
	return max(1, incoming_attack - int(base_defense * 0.5))


# ── 存档支持 ──────────────────────────────────────────────────────────────────

# override 父类 GameEntity.to_dict()
# 先调用 super() 获取基础字段，再追加 Combatant 自己的字段
func to_dict() -> Dictionary:
	var data = super.to_dict()
	data["base_max_hp"]  = base_max_hp
	data["base_attack"]  = base_attack
	data["base_defense"] = base_defense
	data["base_speed"]   = base_speed
	data["base_magic"]   = base_magic
	return data

# override 父类 GameEntity.from_dict()
func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	base_max_hp  = data.get("base_max_hp",  100)
	base_attack  = data.get("base_attack",  10)
	base_defense = data.get("base_defense", 5)
	base_speed   = data.get("base_speed",   10)
	base_magic   = data.get("base_magic",   0)
