class_name SpellcasterStrategy extends CombatStrategy

# ─────────────────────────────────────────────────────────────────────────────
# SpellcasterStrategy — 敌人AI：法术型
#
# 对应 EnemyData.AI_SPELLCASTER
# 行为：攻击防御最低的英雄，模拟法师的"找软目标"逻辑
# 使用技能（技能效果由 BattleSimulator 处理，此处只返回技能 ID）
# 适用：女巫、萨满、魔法师类敌人
# ─────────────────────────────────────────────────────────────────────────────

# 法术型敌人的技能列表（模板数据，实际从 EnemyData 扩展字段获取，这里先占位）
# 将来 EnemyData 可以加 enemy_skills: Array[String] 字段
const ENEMY_SKILL_CHANCE: float = 0.60

func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return _target_lowest_defense(opponents)

func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	# 敌人技能系统扩展点：将来从 enemy_data.enemy_skills 随机取
	# 目前按概率决定是否"施法"（施法时伤害由 BattleSimulator 用 magic 属性计算）
	if randf() < ENEMY_SKILL_CHANCE:
		return "enemy_spell"  # 占位技能 ID，BattleSimulator 识别此 ID 用 magic 值计算
	return ""
