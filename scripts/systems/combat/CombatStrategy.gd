class_name CombatStrategy extends RefCounted

# SkillTable 用 preload 引入（读 mp_cost 判断可放性），避免全局类缓存时序问题
const SkillTableScript = preload("res://scripts/utils/SkillTable.gd")

# ─────────────────────────────────────────────────────────────────────────────
# CombatStrategy — 战斗决策策略基类（Strategy 模式）
#
# 解决的问题：英雄和敌人的 AI 行为各不相同，但 BattleSimulator 的战斗循环代码
# 不应该充满 if hero_class == WARRIOR 这类判断。
# 策略模式把"如何决策"封装进各自的子类，Simulator 只调用统一接口。
#
# 使用方式：
#   - 英雄由 HeroFactory 根据职业注入对应策略（WarriorStrategy 等）
#   - 敌人由 EnemyAIFactory.create(ai_type) 创建对应策略
#   - BattleSimulator 统一调用 strategy.choose_target() 和 choose_skill()
#
# 子类只需要 override 需要改变的方法，其余继承默认行为。
# ─────────────────────────────────────────────────────────────────────────────


# choose_target：从对手列表中选择攻击目标
#
# 参数：
#   self_bc   : 自身的 BattleCombatant（可用于判断自身状态）
#   opponents : 对方所有存活单位的 Array[BattleCombatant]
# 返回：选中的目标 BattleCombatant
# 默认行为：攻击第一个（列表顺序为速度排序后的顺序）
func choose_target(self_bc: BattleCombatant, opponents: Array) -> BattleCombatant:
	return opponents[0]


# choose_skill：决定本回合使用哪个技能
#
# 参数：
#   self_bc : 自身的 BattleCombatant（可用于读取 HP、MP 等）
#   hero_ref: 原始英雄对象（用于读取 skills 列表）；敌人传 null
#   allies  : 同队存活单位列表（用于牧师等支援职业判断友军状态）
# 返回：技能 ID 字符串；空字符串 = 普通攻击
# 默认行为：普通攻击（子类按概率 override 选择技能）
func choose_skill(self_bc: BattleCombatant, hero_ref, allies: Array = [], opponents: Array = []) -> String:
	return ""


# should_cast：连招模型——英雄按摆放顺序逐个判断"这个就绪技能现在该不该放"。
# 已知技能"可放"(不在 CD + 蓝够)，此处只判"条件"：纯伤害技默认 true(就绪即放)；
# 治疗/嘲讽/净化等条件技由各职业 override（满血不空放治疗等）。
func should_cast(_skill_id: String, _self_bc: BattleCombatant, _hero_ref, _allies: Array, _opponents: Array) -> bool:
	return true


# ── 共享工具方法（子类复用）────────────────────────────────────────────────────

# 从存活对手中找血量最多的（战士偏好：打最厚的）
func _target_highest_hp(opponents: Array) -> BattleCombatant:
	var best = opponents[0]
	for bc in opponents:
		if bc.current_hp > best.current_hp:
			best = bc
	return best

# 从存活对手中找血量最少的（盗贼偏好：补刀）
func _target_lowest_hp(opponents: Array) -> BattleCombatant:
	var best = opponents[0]
	for bc in opponents:
		if bc.current_hp < best.current_hp:
			best = bc
	return best

# 从存活对手中找防御最低的（法师偏好：找软目标）
func _target_lowest_defense(opponents: Array) -> BattleCombatant:
	var best = opponents[0]
	for bc in opponents:
		if bc.defense < best.defense:
			best = bc
	return best

# 从存活对手中找攻击最高的（弓手偏好：压制威胁）
func _target_highest_attack(opponents: Array) -> BattleCombatant:
	var best = opponents[0]
	for bc in opponents:
		if bc.attack > best.attack:
			best = bc
	return best

# ── 被动技能钩子 ──────────────────────────────────────────────────────────────

# on_battle_event：战斗关键节点回调（被动技能扩展入口）
#
# 由 BattleSimulator._notify_battle_event() 在以下时机调用：
#   "on_kill"      — 本单位击杀敌人后
#   "on_hit_dealt" — 本单位命中敌人后（普攻）
#   "on_hit_taken" — 本单位被命中后（普攻）
#   "on_turn_start"— 本单位回合开始时（待扩展）
#
# context 字段视 event 而定，例如：
#   { "target": BattleCombatant, "damage": int }
#
# 子类 override 此方法实现被动触发逻辑；
# 当前所有策略为空实现，框架可用，逻辑待被动技能系统接入后填充。
func on_battle_event(_event: String, _self_bc: BattleCombatant, _context: Dictionary) -> void:
	pass


# ── 技能可放性 & 选技（英雄：确定性 / 可放就放，蓝量+CD 当唯一节流阀）──────────
# 设计原则：本作是构筑游戏，玩家唯一的杆是搭背包 → 战斗要"可读"：配了什么书，
# 蓝够、转好就放什么，不再掷骰子。蓝量消耗 + 回合冷却本身就是天然节流。
# （敌人 AI 保持各自的随机/特定逻辑——不可预测对"敌人"是优点。）

## 单个技能现在能不能放（不在冷却 + 蓝量足够）
func _is_castable(self_bc: BattleCombatant, skill_id: String) -> bool:
	if self_bc.is_skill_on_cooldown(skill_id):
		return false
	var mp_cost: int = int(SkillTableScript.get_skill(skill_id).get("mp_cost", 0))
	return self_bc.current_mp >= mp_cost

## 英雄当前【可放】的技能子集（已学 + 不在冷却 + 蓝够）
func _castable_skills(self_bc: BattleCombatant, hero_ref) -> Array:
	if hero_ref == null:
		return []
	var skills = hero_ref.get("skills")
	if skills == null:
		return []
	return skills.filter(func(sid): return _is_castable(self_bc, sid))

## 可放的【伤害】技能里 power 最高的一个（确定性"放最强可用攻击技"）；无 → 普攻("")。
## 拉仇/buff/治疗等非伤害技由各职业策略按优先级单独处理，不进这里。
func _strongest_castable_damage(self_bc: BattleCombatant, hero_ref) -> String:
	var best := ""
	var best_power := -1.0
	for sid in _castable_skills(self_bc, hero_ref):
		var s: Dictionary = SkillTableScript.get_skill(sid)
		if s.get("type", "damage") != "damage":
			continue
		var p: float = float(s.get("power", 1.0))
		if p > best_power:
			best_power = p
			best = sid
	return best
