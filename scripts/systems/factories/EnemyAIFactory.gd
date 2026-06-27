class_name EnemyAIFactory

# ─────────────────────────────────────────────────────────────────────────────
# EnemyAIFactory — 敌人 AI 策略工厂
#
# 根据 EnemyData.ai_type 字符串创建对应的 CombatStrategy 实例。
# BattleSimulator 在创建 BattleCombatant 时调用此工厂。
#
# 新增敌人 AI 类型时，只需：
#   1. 在 strategies/ 目录下创建新的策略类
#   2. 在 create() 方法里加一个 match 分支
#   3. 在 EnemyData 里加对应的常量
#
# 为什么是静态类而不是 Autoload？
#   工厂只做"创建"，没有状态，不需要单例。静态方法更简洁。
# ─────────────────────────────────────────────────────────────────────────────


# create：根据 ai_type 字符串创建对应策略
# 未知类型时返回 BasicAttackStrategy 作为兜底，并打印警告
static func create(ai_type: String) -> CombatStrategy:
	match ai_type:
		EnemyData.AI_BASIC_ATTACK:
			return BasicAttackStrategy.new()
		EnemyData.AI_AGGRESSIVE:
			return AggressiveStrategy.new()
		EnemyData.AI_TANK:
			return TankStrategy.new()
		EnemyData.AI_SPELLCASTER:
			return SpellcasterStrategy.new()
		EnemyData.AI_POISON_CASTER:
			return PoisonCasterStrategy.new()
		EnemyData.AI_COLUMN_PIERCER:
			return ColumnPiercerStrategy.new()
		_:
			push_warning("EnemyAIFactory: 未知 AI 类型 '%s'，使用 BasicAttack 兜底" % ai_type)
			return BasicAttackStrategy.new()
