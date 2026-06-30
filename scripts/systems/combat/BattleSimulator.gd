class_name BattleSimulator

# ─────────────────────────────────────────────────────────────────────────────
# BattleSimulator — 战斗模拟器（纯静态工具类）
#
# 输入：Party（英雄队伍）+ Array[EnemyData]（敌人列表）
# 输出：BattleResult（战斗完整结果）
#
# 战斗循环规则：
#   1. 每回合开始：所有单位结算持续状态（DoT / 减速倒计）
#   2. 所有存活单位按速度排序，眩晕单位跳过
#   3. 行动 = 选目标 → 执行技能/普攻 → 记录 TurnLog
#   4. 某方全员死亡时战斗结束
#   5. 最多 MAX_TURNS 轮防止死循环
# ─────────────────────────────────────────────────────────────────────────────

const MAX_TURNS: int = 50

# SkillTable 通过 preload 引入（避免 class_name 注册时序问题）
const SkillTableScript = preload("res://scripts/utils/SkillTable.gd")


# ── 主入口 ────────────────────────────────────────────────────────────────────

static func simulate(party, enemy_data_list: Array) -> BattleResult:
	var hero_bcs   = _create_hero_combatants(party.get_alive_heroes(), party)
	var enemy_bcs  = _create_enemy_combatants(enemy_data_list)
	var turn_logs: Array = []
	# 站位模式："reach"硬触及（默认）/ "soft_row"世界树软调整
	var pos_mode: String = party.positioning_mode if party != null else "reach"

	var turn := 0
	while turn < MAX_TURNS:
		turn += 1

		# ── 回合开始：结算所有单位的持续状态 ─────────────────────────────
		_tick_all_status(hero_bcs,  turn_logs)
		_tick_all_status(enemy_bcs, turn_logs)

		# 软站位：前排全灭则后排顶上前排（世界树规则）
		if pos_mode == "soft_row":
			_promote_if_front_empty(hero_bcs)
			_promote_if_front_empty(enemy_bcs)

		# 状态结算后再检查胜负（DoT 可能导致死亡）
		var _early_end = _check_end(hero_bcs, enemy_bcs, party, hero_bcs, enemy_bcs, enemy_data_list, turn_logs, turn)
		if _early_end != null:
			return _early_end

		# ── 行动阶段：按速度排序 ──────────────────────────────────────────
		var all_units: Array = []
		all_units.append_array(hero_bcs.filter(func(bc): return bc.is_alive()))
		all_units.append_array(enemy_bcs.filter(func(bc): return bc.is_alive()))
		all_units.sort_custom(func(a, b):
			if a.speed != b.speed:
				return a.speed > b.speed
			return a.is_hero()
		)

		for unit in all_units:
			if not unit.is_alive():
				continue

			# 行动开始：技能冷却 -1（方案 B 技能书冷却）
			unit.tick_cooldowns()

			# 眩晕：跳过本回合行动
			if unit.is_stunned():
				unit.tick_effects()    # 统一递减眩晕/减速/Buff 计时
				var stun_log = TurnLog.attack(unit.source_name, unit.source_name, 0)
				stun_log.skill_id = "stun_skip"   # 特殊标记，BattleUI 显示"眩晕"
				turn_logs.append(stun_log)
				continue

			# 确定对手列表
			var opponents: Array = _get_opponents(unit, hero_bcs, enemy_bcs)
			if opponents.is_empty():
				break

			var hero_ref = unit._hero_ref if unit.is_hero() else null

			if unit.is_hero() and hero_ref != null:
				# 英雄：按背包摆放顺序，把所有"就绪+条件满足"的技能依次放掉（连招，替代普攻）
				_hero_combo_turn(unit, hero_ref, hero_bcs, enemy_bcs, pos_mode, turn_logs)
			else:
				# 敌人：单动作 AI（选目标 → 选一个技能/普攻），保持原有行为
				var reachable: Array
				if pos_mode == "soft_row":
					reachable = _soft_reachable(unit, opponents)
				else:
					reachable = _get_reachable_opponents(unit, opponents)
				var taunt_target = _find_taunt_target(reachable)
				var target: BattleCombatant = taunt_target if taunt_target != null \
					else unit.combat_strategy.choose_target(unit, reachable)
				var allies: Array = _get_allies(unit, hero_bcs, enemy_bcs)
				var skill_id: String = unit.combat_strategy.choose_skill(unit, hero_ref, allies, opponents)
				if not skill_id.is_empty():
					if unit.is_skill_on_cooldown(skill_id) \
						or unit.current_mp < int(SkillTableScript.get_skill(skill_id).get("mp_cost", 0)):
						skill_id = ""   # 冷却中/蓝量不足 → 普攻
				if not skill_id.is_empty():
					unit.trigger_skill_cooldown(skill_id)
				var logs: Array = _execute_action(unit, skill_id, target, reachable, allies, opponents, pos_mode)
				turn_logs.append_array(logs)

			# 行动后检查消耗品（英雄专属）
			if unit.is_hero():
				var used_item = unit.try_use_consumable()
				if used_item != null and not turn_logs.is_empty():
					turn_logs[-1].with_consumable(used_item.effect_type, used_item.effect_value)

			# 行动结束后递减所有计时效果（慢/Buff/眩晕，保证本回合速度排序正确）
			unit.tick_effects()

		# ── 行动结束后检查胜负 ────────────────────────────────────────────
		var result = _check_end(hero_bcs, enemy_bcs, party, hero_bcs, enemy_bcs, enemy_data_list, turn_logs, turn)
		if result != null:
			return result

	push_warning("BattleSimulator: 达到最大回合数 %d，判定失败" % MAX_TURNS)
	return _make_defeat_result(hero_bcs, enemy_bcs, turn_logs, MAX_TURNS)


# ── 技能/普攻执行 ─────────────────────────────────────────────────────────────

# 标准普通攻击：暴击 + 站位修正（仅物理）+ 装备触发。普攻无技能、无蓝耗。
# 两处共用（skill_id 为空 / 未知技能回退），确保修正一致、不再漏算。
static func _basic_attack(actor: BattleCombatant, target: BattleCombatant, pos_mode: String) -> Array:
	var logs: Array = []
	if _roll_dodge(target):
		logs.append(_make_dodge_log(target))
		return logs   # 完全免伤：不结算伤害、不触发装备/击杀
	var crit_mult := _roll_crit(actor)
	var row_mult := _row_damage_mult(actor, target, true, pos_mode)   # 普攻为物理，受站位修正
	var dmg := target.take_damage(int(round(actor.attack * crit_mult * row_mult * _roll_variance())))
	var atk_log := TurnLog.attack(actor.source_name, target.source_name, dmg, not target.is_alive())
	atk_log.is_crit = crit_mult > 1.0
	logs.append(atk_log)
	# 装备触发：攻击方 on_hit_dealt / 受击方 on_hit_taken / 击杀 on_kill
	_process_equipment_triggers("on_hit_dealt", actor,  target, dmg, logs)
	_process_equipment_triggers("on_hit_taken", target, actor,  dmg, logs)
	if not target.is_alive():
		_process_equipment_triggers("on_kill", actor, target, dmg, logs)
		_notify_battle_event("on_kill", actor, { "target": target, "damage": dmg })
	return logs


# ── 英雄连招回合（中间档：按摆放顺序连放所有就绪技能）────────────────────────
# hero_ref.skills 已按"读序"排好（BackpackModel.compute 排序）。
# 逐个技能：可放(不在CD+蓝够) + 条件满足(should_cast) → 触发CD + 释放；放完重取战场。
# 放了任一技能就不再普攻；一个都没放 → 退化为一次普攻。
static func _hero_combo_turn(unit, hero_ref, hero_bcs: Array, enemy_bcs: Array, pos_mode: String, turn_logs: Array) -> void:
	var skills: Array = hero_ref.get("skills") if hero_ref.get("skills") else []
	var fired: bool = false
	for skill_id in skills:
		var opponents: Array = _get_opponents(unit, hero_bcs, enemy_bcs)
		if opponents.is_empty():
			break
		if not _is_skill_ready(unit, skill_id):
			continue   # 冷却中 / 蓝量不足
		var allies: Array = _get_allies(unit, hero_bcs, enemy_bcs)
		if not unit.combat_strategy.should_cast(skill_id, unit, hero_ref, allies, opponents):
			continue   # 条件未满足（如满血不放治疗）
		var reachable: Array = _soft_reachable(unit, opponents) if pos_mode == "soft_row" \
			else _get_reachable_opponents(unit, opponents)
		var taunt_target = _find_taunt_target(reachable)
		var target: BattleCombatant = taunt_target if taunt_target != null \
			else unit.combat_strategy.choose_target(unit, reachable)
		unit.trigger_skill_cooldown(skill_id)
		turn_logs.append_array(_execute_action(unit, skill_id, target, reachable, allies, opponents, pos_mode))
		fired = true

	if fired:
		return   # 技能替代普攻
	# 一个技能都没放 → 普攻
	var opp: Array = _get_opponents(unit, hero_bcs, enemy_bcs)
	if opp.is_empty():
		return
	var reach: Array = _soft_reachable(unit, opp) if pos_mode == "soft_row" \
		else _get_reachable_opponents(unit, opp)
	var tt = _find_taunt_target(reach)
	var tgt: BattleCombatant = tt if tt != null else unit.combat_strategy.choose_target(unit, reach)
	turn_logs.append_array(_execute_action(unit, "", tgt, reach, _get_allies(unit, hero_bcs, enemy_bcs), opp, pos_mode))


# 技能是否就绪：不在冷却 + 蓝量足够（连招/单动作共用判断）。
static func _is_skill_ready(unit, skill_id: String) -> bool:
	if unit.is_skill_on_cooldown(skill_id):
		return false
	return unit.current_mp >= int(SkillTableScript.get_skill(skill_id).get("mp_cost", 0))


static func _execute_action(
	actor:         BattleCombatant,
	skill_id:      String,
	target:        BattleCombatant,
	opponents:     Array,
	allies:        Array = [],
	all_opponents: Array = [],
	pos_mode:      String = "reach"
) -> Array:
	var logs: Array = []

	if skill_id.is_empty():
		return _basic_attack(actor, target, pos_mode)   # 普攻（暴击+站位修正+装备触发）

	var skill: Dictionary = SkillTableScript.get_skill(skill_id)
	if skill.is_empty():
		# 未知技能（如敌方 spellcaster 的占位 enemy_spell）→ 同样走标准普攻。
		# 修复：旧版此处直接 take_damage(attack)，漏算站位修正/暴击，导致伤害忽高忽低。
		return _basic_attack(actor, target, pos_mode)

	# ── 扣除蓝量（已在 simulate 里确认蓝量足够）─────────────────────────────
	var mp_cost: int = skill.get("mp_cost", 0)
	if mp_cost > 0:
		actor.spend_mp(mp_cost)

	var stype: String = skill.get("type", "damage")

	# ── 治疗友军 ──────────────────────────────────────────────────────────────
	if stype == "heal_ally":
		var power: float = skill.get("power", 1.0)
		var heal_amount: int = max(1, int(float(actor.magic) * power))

		# 找血量百分比最低的存活友军（不含自身，若无则治疗自身）
		var heal_target: BattleCombatant = actor
		var lowest_pct: float = actor.get_hp_percent()
		for ally in allies:
			if ally == actor or not ally.is_alive():
				continue
			if ally.get_hp_percent() < lowest_pct:
				lowest_pct  = ally.get_hp_percent()
				heal_target = ally

		var actual_heal := heal_target.heal(heal_amount)
		var log := TurnLog.skill_attack(
			actor.source_name, heal_target.source_name, skill_id, actual_heal, false
		)
		logs.append(log)
		return logs

	# ── 净化友军 DoT（方案 B：克制 poison 遭遇）──────────────────────────────────
	# 移除全体存活友军身上的所有 dot 效果（解毒）。
	if stype == "cleanse":
		for ally in allies:
			if not ally.is_alive():
				continue
			ally.active_effects = ally.active_effects.filter(
				func(e): return e.get("type") != "dot"
			)
		var log := TurnLog.skill_attack(actor.source_name, actor.source_name, skill_id, 0, false)
		logs.append(log)
		return logs

	# ── 主动嘲讽（taunt_self）：临时拉仇 N 回合（仅前排生效）+ 可立防 ─────────────
	# "我站出来挡"：施放后 has_taunt() 为真，敌人优先打我；前排门槛在 _find_taunt_target。
	if stype == "taunt_self":
		var taunt_turns: int = skill.get("taunt_turns", 2)
		actor.apply_taunt(taunt_turns)
		if skill.get("buff_defense", 0) != 0:
			actor.apply_buff("defense", skill.get("buff_defense"), skill.get("buff_turns", taunt_turns))
		var log := TurnLog.skill_attack(actor.source_name, actor.source_name, skill_id, 0, false)
		logs.append(log)
		return logs

	# ── 强化自身 ──────────────────────────────────────────────────────────────
	# 通过 apply_buff() 写入 active_effects，支持计时过期和属性还原
	# buff_turns: -1 = 战斗全程；>0 = 持续 N 次 tick_effects() 后自动还原
	if stype == "buff_self":
		var buff_turns: int = skill.get("buff_turns", -1)
		if skill.get("buff_attack",  0) != 0:
			actor.apply_buff("attack",  skill.get("buff_attack"),  buff_turns)
		if skill.get("buff_defense", 0) != 0:
			actor.apply_buff("defense", skill.get("buff_defense"), buff_turns)
		if skill.get("buff_speed",   0) != 0:
			actor.apply_buff("speed",   skill.get("buff_speed"),   buff_turns)
		if skill.get("buff_magic",   0) != 0:
			actor.apply_buff("magic",   skill.get("buff_magic"),   buff_turns)
		var log := TurnLog.skill_attack(actor.source_name, actor.source_name, skill_id, 0, false)
		logs.append(log)
		return logs

	# ── 伤害类技能 ────────────────────────────────────────────────────────────
	var power:      float = skill.get("power",      1.0)
	var use_magic:  bool  = skill.get("use_magic",  false)
	var ignore_def: bool  = skill.get("ignore_def", false)
	var half_def:   bool  = skill.get("half_def",   false)
	var is_aoe:     bool  = skill.get("aoe",        false)

	var base_atk: int = actor.magic if use_magic else actor.attack

	if is_aoe:
		var shape: String = skill.get("aoe_shape", "all")
		var aoe_targets: Array = _aoe_targets(shape, target, opponents, all_opponents)
		var crit_mult: float = _roll_crit(actor)
		var raw_aoe: int = int(float(base_atk) * power * crit_mult)
		for opp in aoe_targets:
			if _roll_dodge(opp):
				logs.append(_make_dodge_log(opp))
				continue
			var dmg:        int = _calc_damage(raw_aoe, opp, ignore_def, half_def)
			dmg = int(round(dmg * _row_damage_mult(actor, opp, not use_magic, pos_mode) * _roll_variance()))   # 站位修正（仅物理）+ 伤害浮动
			var actual_dmg: int = opp.take_damage_raw(dmg)   # 护盾吸收后的实际伤害
			var aoe_log := TurnLog.skill_attack(
				actor.source_name, opp.source_name, skill_id, actual_dmg, not opp.is_alive()
			)
			aoe_log.is_crit = crit_mult > 1.0
			logs.append(aoe_log)
			_process_equipment_triggers("on_hit_dealt", actor, opp, actual_dmg, logs)
			_process_equipment_triggers("on_hit_taken", opp, actor, actual_dmg, logs)
			if not opp.is_alive():
				_process_equipment_triggers("on_kill", actor, opp, actual_dmg, logs)
				_notify_battle_event("on_kill", actor, { "target": opp, "damage": actual_dmg })
	else:
		if _roll_dodge(target):
			logs.append(_make_dodge_log(target))
			return logs   # 完全免伤：不结算伤害/异常状态/触发
		var crit_mult:  float = _roll_crit(actor)
		var raw_atk:    int = int(float(base_atk) * power * crit_mult)
		var row_mult:   float = _row_damage_mult(actor, target, not use_magic, pos_mode)   # 站位修正（仅物理）
		var dmg:        int = int(round(_calc_damage(raw_atk, target, ignore_def, half_def) * row_mult * _roll_variance()))
		var actual_dmg: int = target.take_damage_raw(dmg)   # 护盾吸收后的实际伤害
		var log := TurnLog.skill_attack(
			actor.source_name, target.source_name, skill_id, actual_dmg, not target.is_alive()
		)
		log.is_crit = crit_mult > 1.0

		if target.is_alive():
			var stun_t: int   = skill.get("stun_turns",  0)
			var slow_a: int   = skill.get("slow_amount", 0)
			var slow_t: int   = skill.get("slow_turns",  0)
			var dot_p:  float = skill.get("dot_power",   0.0)
			var dot_t:  int   = skill.get("dot_turns",   0)

			if stun_t > 0:
				target.apply_stun(stun_t)
			if slow_a > 0 and slow_t > 0:
				target.apply_slow(slow_a, slow_t)
			if dot_p > 0.0 and dot_t > 0:
				var dot_dmg: int = maxi(1, int(float(actor.attack) * dot_p))
				target.apply_dot(dot_dmg, dot_t)

		logs.append(log)
		_process_equipment_triggers("on_hit_dealt", actor,  target, actual_dmg, logs)
		_process_equipment_triggers("on_hit_taken", target, actor,  actual_dmg, logs)
		if not target.is_alive():
			_process_equipment_triggers("on_kill", actor, target, actual_dmg, logs)
			_notify_battle_event("on_kill", actor, { "target": target, "damage": actual_dmg })

	return logs


# ── 暴击判定（方案 B：副属性 crit_chance / crit_dmg）────────────────────────
# 返回本次行动的暴击倍率：未暴击 = 1.0；暴击 = 基础 1.5 + crit_dmg 加成。
# crit_chance 为 0~1 概率；无副属性的单位 get_stat 返回 0 → 永远 1.0（旧行为不变）。
const CRIT_BASE_MULT: float = 1.5

static func _roll_crit(actor: BattleCombatant) -> float:
	var chance: float = actor.get_stat("crit_chance", 0.0)
	if chance > 0.0 and randf() < chance:
		return CRIT_BASE_MULT + actor.get_stat("crit_dmg", 0.0)
	return 1.0


# ── 闪避判定（小队第二档：副属性 dodge_chance）────────────────────────────────
# 被攻击者命中前 roll；闪避 = 本次完全免伤（不结算伤害/异常状态/装备触发/击杀）。
# 物理+魔法直接攻击都可闪（"闪避T"该躲一切）；DoT/反伤不走攻击路径，不受影响。
# 上限 DODGE_CAP 防"100% 无敌"。无 dodge_chance 副属性的单位恒不闪（旧行为不变）。
const DODGE_CAP: float = 0.6

## 单位的有效闪避率（已 clamp 到 [0, DODGE_CAP]）。纯函数，便于测试。
static func _dodge_chance(target: BattleCombatant) -> float:
	return clampf(target.get_stat("dodge_chance", 0.0), 0.0, DODGE_CAP)

## 本次攻击是否被闪避。
static func _roll_dodge(target: BattleCombatant) -> bool:
	var c: float = _dodge_chance(target)
	return c > 0.0 and randf() < c

## 构造一条"闪避"日志（skill_id="dodge"，伤害 0，BattleUI 显示为闪避）。
static func _make_dodge_log(target: BattleCombatant) -> TurnLog:
	var log := TurnLog.attack(target.source_name, target.source_name, 0)
	log.skill_id = "dodge"
	return log


# ── 伤害浮动（±DMG_VARIANCE）────────────────────────────────────────────────
# 给每次伤害落地乘一个 [1-v, 1+v] 的小随机，AI 出招仍确定可读，但战斗结果不再
# "分毫不差"——恢复胜率梯度（否则确定性战斗下胜率非 0 即 100，难度无法细调），
# 手感也更自然。普攻/单体技能/AOE 三处统一调用。
const DMG_VARIANCE: float = 0.10

static func _roll_variance() -> float:
	return randf_range(1.0 - DMG_VARIANCE, 1.0 + DMG_VARIANCE)


# ── 软站位伤害修正（方案 B / 世界树式，仅 soft_row 模式 + 仅物理伤害）──────────
# 后排发起近战(物理) → ×0.5；后排承受物理伤害 → ×0.7（可叠乘）。
# 魔法/远程(is_physical=false) 与 reach 模式 → 恒 1.0（不受站位影响）。
const SOFT_BACK_ATTACK_MULT: float = 0.5   # 后排近战输出
const SOFT_BACK_DEFENSE_MULT: float = 0.7  # 后排受物理伤

static func _row_damage_mult(attacker: BattleCombatant, defender: BattleCombatant, is_physical: bool, pos_mode: String) -> float:
	if pos_mode != "soft_row" or not is_physical:
		return 1.0
	var m: float = 1.0
	if attacker.row == "back":
		m *= SOFT_BACK_ATTACK_MULT
	if defender.row == "back":
		m *= SOFT_BACK_DEFENSE_MULT
	return m


# 软站位：某一方前排全灭时，把存活后排顶上前排（世界树规则）
static func _promote_if_front_empty(units: Array) -> void:
	for bc in units:
		if bc.is_alive() and bc.row == "front":
			return   # 还有前排，无需顶上
	for bc in units:
		if bc.is_alive() and bc.row == "back":
			bc.row = "front"


# ── 伤害计算（不含防御的原始攻击 → 实际伤害）────────────────────────────────

static func _calc_damage(
	raw_attack: int,
	target:     BattleCombatant,
	ignore_def: bool,
	half_def:   bool
) -> int:
	var eff_def: int
	if ignore_def:
		eff_def = 0
	elif half_def:
		eff_def = target.defense / 2
	else:
		eff_def = target.defense
	return maxi(1, raw_attack - eff_def / 2)


# ── 持续状态结算 ──────────────────────────────────────────────────────────────

static func _tick_all_status(units: Array, turn_logs: Array) -> void:
	for unit in units:
		if not unit.is_alive():
			continue
		var dot_dealt: int = unit.tick_status()
		if dot_dealt > 0:
			var log := TurnLog.attack(
				"毒伤", unit.source_name, dot_dealt, not unit.is_alive()
			)
			log.skill_id = "dot_tick"   # 特殊标记，BattleUI 显示为毒伤
			turn_logs.append(log)


# ── 胜负检查（返回 BattleResult 或 null）────────────────────────────────────

static func _check_end(
	hero_bcs:        Array,
	enemy_bcs:       Array,
	party,
	_hbc:            Array,
	_ebc:            Array,
	enemy_data_list: Array,
	turn_logs:       Array,
	turn:            int
):
	var heroes_alive  := hero_bcs.any(func(bc):  return bc.is_alive())
	var enemies_alive := enemy_bcs.any(func(bc): return bc.is_alive())

	if not enemies_alive:
		return _make_victory_result(party, hero_bcs, enemy_bcs, enemy_data_list, turn_logs, turn)
	if not heroes_alive:
		return _make_defeat_result(hero_bcs, enemy_bcs, turn_logs, turn)
	return null


# ── 私有：对手列表 ────────────────────────────────────────────────────────────

static func _get_opponents(unit: BattleCombatant, hero_bcs: Array, enemy_bcs: Array) -> Array:
	if unit.is_hero():
		return enemy_bcs.filter(func(bc): return bc.is_alive())
	else:
		return hero_bcs.filter(func(bc): return bc.is_alive())


# ── 私有：站位触及过滤（方案 B：逐列掩护）────────────────────────────────────
# 远程/突袭单位（can_reach_back）可打任意格，无视掩护。
# 近战单位：可打「暴露」单位 = 所有前排 + 所在列没有存活前排掩护的后排。
#   → 把脆皮后排摆在有肉盾的同一列才挡得住；摆在空列会被近战点穿。
# 入参 opponents 已是存活列表；返回非空（全暴露则退化为全体）。
# soft_row 触及（模型 C：站位 + 职业）：
#   前排：打任何人；后排：远程(can_reach_back)打任何人、近战只能打对方前排。
# 配合"前排全灭后排顶上"，近战永远有前排可打；对方无前排时退化为全体（兜底）。
static func _soft_reachable(unit: BattleCombatant, opponents: Array) -> Array:
	if unit.row == "front" or unit.can_reach_back:
		return opponents
	var front: Array = opponents.filter(func(bc): return bc.row == "front")
	return front if not front.is_empty() else opponents


static func _get_reachable_opponents(unit: BattleCombatant, opponents: Array) -> Array:
	if unit.can_reach_back:
		return opponents
	# 收集"有存活前排"的列
	var covered_cols: Dictionary = {}
	for bc in opponents:
		if bc.row == "front":
			covered_cols[bc.col] = true
	var reachable: Array = []
	for bc in opponents:
		# 前排恒可达；后排仅当所在列无前排掩护时暴露
		if bc.row == "front" or not covered_cols.has(bc.col):
			reachable.append(bc)
	return reachable if not reachable.is_empty() else opponents


# ── 私有：AOE 命中形状（方案 B：列维度）──────────────────────────────────────
# "all"    : 命中可触及范围（保持原行为，受掩护限制）
# "row"    : 命中目标所在「行」的全部单位（横扫，无视掩护）
# "column" : 命中目标所在「列」的全部单位（穿刺，前后排一锅端，无视掩护）
# shaped AOE 用完整对手列表 all_opponents（穿透掩护）；为空时退化为 reachable。
static func _aoe_targets(shape: String, target: BattleCombatant, reachable: Array, all_opponents: Array) -> Array:
	var pool: Array = all_opponents if not all_opponents.is_empty() else reachable
	match shape:
		"row":
			return pool.filter(func(bc): return bc.row == target.row)
		"column":
			return pool.filter(func(bc): return bc.col == target.col)
		_:
			return reachable


# ── 私有：同队存活列表（heal_ally 用）────────────────────────────────────────
static func _get_allies(unit: BattleCombatant, hero_bcs: Array, enemy_bcs: Array) -> Array:
	if unit.is_hero():
		return hero_bcs.filter(func(bc): return bc.is_alive())
	else:
		return enemy_bcs.filter(func(bc): return bc.is_alive())


# ── 私有：创建战斗单位 ────────────────────────────────────────────────────────

# 英雄的"远程"标签（按职业）：在此清单里 = 远程（后排也能越过前排打后排）；
# 不在 = 近战（后排只能打对方前排，需顶到前排才能威胁后排）。
# 盗贼定位为近战刺客（不在此列）——要它咬后排脆皮就得顶前排，制造站位取舍。
# 怪物侧用 EnemyData.is_ranged 数据标签表示同一概念。
const REACH_BACK_CLASSES: Array = [
	Hero.HeroClass.MAGE,
	Hero.HeroClass.ARCHER,
]

static func _create_hero_combatants(heroes: Array, party = null) -> Array:
	var result: Array = []
	for hero in heroes:
		var bc = BattleCombatant.from_hero(hero)
		if bc.combat_strategy == null:
			push_warning("英雄 '%s' 没有设置 combat_strategy，使用默认策略" % hero.entity_name)
			bc.combat_strategy = CombatStrategy.new()
		# 站位：玩家编队（party.formation_cell）→ 职业默认；触及能力按职业判定
		bc.row = party.get_row(hero) if party != null else "front"
		bc.col = party.get_col(hero) if party != null else 0
		bc.can_reach_back = hero.hero_class in REACH_BACK_CLASSES
		# 技能回合冷却配置（背包技能书注入；无则空=无冷却）
		bc.skill_cd_config = party.get_skill_cd(hero) if party != null else {}
		# 副属性（暴击等，背包注入；无则空=无副属性）
		bc.extra_stats = party.get_extra_stats(hero) if party != null else {}
		result.append(bc)
	return result


static func _create_enemy_combatants(enemy_data_list: Array) -> Array:
	var result: Array = []
	for data in enemy_data_list:
		var bc = BattleCombatant.from_enemy_data(data)
		bc.combat_strategy = EnemyAIFactory.create(data.ai_type)
		bc.row = data.preferred_row
		bc.col = data.preferred_col
		bc.can_reach_back = data.is_ranged
		result.append(bc)
	return result


# ── 私有：嘲讽检测 ────────────────────────────────────────────────────────────

static func _find_taunt_target(opponents: Array):
	for bc in opponents:
		# 嘲讽=「我站出来挡」→ 只有【前排】嘲讽才生效。
		# 后排嘲讽件失效（否则后排既偷 ×0.7 物理减伤又吸火力 = 主题别扭 + 站位无抉择）。
		# 「前排全灭→后排顶上」(_promote_if_front_empty) 会把幸存坦克转为 front，仍能继续嘲讽。
		if bc.row != "front":
			continue
		# 嘲讽来源二选一：① 物品副属性 taunt（小队第二档，可放谁背包谁吸火力）
		#                  ② 策略硬编码 HAS_TAUNT（旧机制，保留）
		if bc.has_taunt():
			return bc
		if bc.combat_strategy != null and bc.combat_strategy.get("HAS_TAUNT") == true:
			return bc
	return null


# ── 私有：结算 ────────────────────────────────────────────────────────────────

static func _make_victory_result(party, hero_bcs, enemy_bcs, enemy_data_list, turn_logs, turn) -> BattleResult:
	var dead_heroes  = _collect_dead_heroes(hero_bcs)
	var surviving_hp = _collect_surviving_hp(hero_bcs)
	var loot         = _roll_all_loot(enemy_data_list)
	var result       = BattleResult.victory(turn_logs, dead_heroes, surviving_hp, loot, turn)
	# 胜利时敌人全部死亡
	result.enemies_killed = enemy_bcs.size()
	# 经验：全部击败敌人的 exp_reward 累加（存活英雄各自获得）
	result.exp_reward = _sum_enemy_exp(enemy_data_list)
	# 金币：每个敌人按 gold_reward_min/max 必掉一份（roll_gold），累加后回城并入分成
	# 掉落池（normal/rare/elite）专放物品，金币不走掉落池
	result.loot_gold = _sum_enemy_gold(enemy_data_list)
	return result


static func _make_defeat_result(hero_bcs, enemy_bcs, turn_logs, turn) -> BattleResult:
	var dead_heroes = _collect_dead_heroes(hero_bcs)
	var result      = BattleResult.defeat(turn_logs, dead_heroes, turn)
	# 失败时统计已击杀的敌人数（全灭无存活英雄，经验/掉落均为 0）
	result.enemies_killed = enemy_bcs.filter(func(bc): return not bc.is_alive()).size()
	return result


## 累加全部敌人的经验奖励
static func _sum_enemy_exp(enemy_data_list: Array) -> int:
	var total := 0
	for data in enemy_data_list:
		total += data.exp_reward
	return total


## 累加全部敌人的金币掉落（每个敌人 roll_gold()：gold_reward_min~max 随机，必掉）
static func _sum_enemy_gold(enemy_data_list: Array) -> int:
	var total := 0
	for data in enemy_data_list:
		total += data.roll_gold()
	return total


static func _collect_dead_heroes(hero_bcs: Array) -> Array:
	var dead: Array = []
	for bc in hero_bcs:
		if not bc.is_alive() and bc._hero_ref != null:
			dead.append(bc._hero_ref)
	return dead


static func _collect_surviving_hp(hero_bcs: Array) -> Dictionary:
	var result: Dictionary = {}
	for bc in hero_bcs:
		if bc.is_alive() and bc._hero_ref != null:
			result[bc._hero_ref.instance_id] = bc.current_hp
	return result


static func _roll_all_loot(enemy_data_list: Array) -> Array:
	var all_drops: Array = []
	for data in enemy_data_list:
		all_drops.append_array(data.roll_drops())
	return all_drops


# ── 装备特殊触发处理 ──────────────────────────────────────────────────────────

## 在关键战斗时机检查单位的装备触发器并执行对应效果。
## trigger_owner: 持有触发器的单位（"on_hit_taken" 是受击者，"on_kill" 是击杀者）
## event_actor:   触发事件的另一方（用于反伤等效果的作用目标）
static func _process_equipment_triggers(
	trigger:       String,
	trigger_owner: BattleCombatant,
	event_actor:   BattleCombatant,
	damage:        int,
	logs:          Array
) -> void:
	for eff in trigger_owner.equipment_triggers:
		if eff.get("trigger") != trigger:
			continue
		match eff.get("effect", ""):
			"thorns":
				# 反伤：将受到伤害的一定比例反弹给攻击者
				var thorns_dmg: int = maxi(1, int(damage * eff.get("value", 0.0)))
				var actual: int     = event_actor.take_damage_raw(thorns_dmg)
				var log := TurnLog.attack("荆棘", event_actor.source_name, actual, not event_actor.is_alive())
				log.skill_id = "thorns"
				logs.append(log)
			"lifesteal":
				# 吸血：击杀后回复固定 HP
				var heal_amount: int  = maxi(1, int(eff.get("value", 0)))
				var actual_heal: int  = trigger_owner.heal(heal_amount)
				var log := TurnLog.skill_attack(
					trigger_owner.source_name, trigger_owner.source_name, "lifesteal", actual_heal, false
				)
				logs.append(log)
			"regen_mp":
				# 回蓝：触发时恢复 MP（静默，不记日志）
				trigger_owner.regen_mp(int(eff.get("value", 0)))


# ── 被动技能事件通知 ──────────────────────────────────────────────────────────

## 在关键战斗节点通知单位的战斗策略（被动技能钩子）。
## 当前所有策略均为空实现（CombatStrategy.on_battle_event），此为扩展预留入口。
## event:   "on_kill" / "on_hit_taken" / "on_hit_dealt" / "on_turn_start"
## context: { "target": BattleCombatant, "damage": int, ... }（内容视 event 而定）
static func _notify_battle_event(
	event:   String,
	unit:    BattleCombatant,
	context: Dictionary
) -> void:
	if unit.combat_strategy != null and unit.combat_strategy.has_method("on_battle_event"):
		unit.combat_strategy.on_battle_event(event, unit, context)
