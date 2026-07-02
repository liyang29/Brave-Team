class_name BattleCombatant extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# BattleCombatant — 战斗单位统一包装（运行时）
#
# 解决的问题：
#   BattleSimulator 同时操作英雄（Hero）和敌人（EnemyData），
#   但两者来自不同的类，属性访问方式也不同。
#   BattleCombatant 是统一的战斗接口，让 Simulator 代码完全不需要区分来源。
#
# 两种创建方式：
#   BattleCombatant.from_hero(hero)        ← HP 变化实时写回原 Hero
#   BattleCombatant.from_enemy_data(data)  ← 临时副本，战斗结束丢弃
#
# 生命周期：一场战斗开始时创建，战斗结束后引用自然消失，RefCounted 自动回收。
# ─────────────────────────────────────────────────────────────────────────────


# ── 基础字段 ──────────────────────────────────────────────────────────────────

var source_name: String = ""
var current_hp:  int    = 0
var max_hp:      int    = 0
var attack:      int    = 0
var defense:     int    = 0
var speed:       int    = 0
var magic:       int    = 0

var combat_strategy = null   # CombatStrategy 实例，不加类型避免循环引用

# ── 蓝量（Mana）─────────────────────────────────────────────────────────────
var current_mp: int = 0
var max_mp:     int = 0
var mp_regen:   int = 0

var consumables: Array = []   # Array[Consumable]
var _hero_ref          = null  # Hero 实例或 null（敌人为 null）


# ── 统一状态效果列表 ──────────────────────────────────────────────────────────
#
# 替代原来的硬编码字段：dot_damage / dot_turns / stun_turns / speed_debuff / slow_turns。
# 每种效果是一个 Dictionary，通过 "type" 字段区分，新增状态类型无需修改字段定义。
#
# 当前支持的效果类型：
#   "dot"    — 持续伤害   { "type":"dot",    "damage":int, "turns":int, "element":String }
#   "stun"   — 眩晕       { "type":"stun",   "turns":int }
#   "slow"   — 减速       { "type":"slow",   "amount":int, "turns":int }
#   "buff"   — 属性强化   { "type":"buff",   "stat":String, "value":int, "turns":int }
#              stat: "attack" / "defense" / "speed" / "magic"
#              turns=-1 表示战斗全程持续（不过期）
#   "shield" — 护盾       { "type":"shield", "amount":int }
#              受 take_damage_raw 时优先扣除，耗尽后自动移除
#
# 扩展新效果：在此添加格式说明，在 tick_effects() 和对应方法中处理逻辑即可。
var active_effects: Array = []


# ── 装备特殊触发 ──────────────────────────────────────────────────────────────
# 战斗开始时从英雄装备的 Equipment.triggers 收集，战斗中只读。
# BattleSimulator 在关键节点调用 _process_equipment_triggers() 检查并执行。
#
# 格式：{ "trigger": String, "effect": String, "value": Variant }
#   trigger: "on_hit_taken" / "on_kill" / "on_hit_dealt"
#   effect:  "thorns"（反伤比例）/ "lifesteal"（吸血量）/ "regen_mp"（回蓝量）
var equipment_triggers: Array = []


# ── 站位（方案 B：小网格站位制）────────────────────────────────────────────
# row            : "front"（前排）/ "back"（后排）—— 网格的行维度，决定触及
# col            : 列索引（0,1,2…）—— 网格的列维度，决定掩护/AOE 形状
# can_reach_back : true = 远程/突袭，可越排攻击后排（无视掩护）；
#                  false = 近战，只能打前排或"无同列前排掩护"的暴露后排
# 默认 front + col 0 + 不可越排 → 旧战斗（无网格数据，全在 col 0）行为完全不变。
var row: String = "front"
var col: int = 0
var can_reach_back: bool = false


# ── 技能回合冷却（方案 B：技能书）────────────────────────────────────────────
# skill_cd_config : { skill_id: cd_turns } —— 由背包技能书注入（经 Party）。空=无冷却。
#                   Boss 的技能冷却也走这个字段（EncounterData.boss_config.skill_cds 注入）。
# skill_cooldowns : { skill_id: remaining } —— 运行时剩余冷却回合，行动开始递减。
# 默认两者皆空 → 所有技能无冷却 → 旧战斗行为完全不变。
var skill_cd_config: Dictionary = {}
var skill_cooldowns: Dictionary = {}


# ── Boss 机制（方案：阶段转换 + 召唤援军，EncounterData.boss_config 注入）────────
# 默认三者皆空 → 非 Boss 单位零影响，跟普通敌人行为完全一致。
#
# available_skills : Array[String] —— Boss 当前"会放"的技能池（BossStrategy 从这里选技，
#                     不是像英雄那样读背包）。初始 = boss_config.base_skills；阶段转换会追加新技能。
# boss_phases      : Array[{hp_pct,atk_mult,def_mult,extra_skills}] —— 血量阈值→效果，
#                     按 hp_pct 从高到低排列。BattleSimulator 每次受伤后检查是否该跃迁。
# boss_phase_index : 已跃迁到第几个阈值（0=还没跃迁过任何一个）。
# boss_summons     : Array[{every,group,max_total,_spawned_count}] —— 每 N 回合召一批新怪，
#                     召满 max_total 停止。_spawned_count 是运行时累计计数（战斗内私有）。
var available_skills: Array = []
var boss_phases: Array = []
var boss_phase_index: int = 0
var boss_summons: Array = []


# ── 副属性字典（方案 B：可扩展战斗属性的地基）──────────────────────────────
# 暴击/吸血/法抗/破甲/闪避… 这类"次级属性"统一住这里，避免每加一个就改结构。
# 加新副属性 = 物品声明该 key + BackpackModel 累加 + 战斗公式读 get_stat()。
# 默认空 → get_stat 返回默认值 → 旧战斗行为不变。
# 当前已接入战斗：crit_chance(0~1 暴击率)、crit_dmg(暴击额外倍率，暴击=1.5+此值)
var extra_stats: Dictionary = {}

## 读取副属性（不存在返回 default）
func get_stat(key: String, default: float = 0.0) -> float:
	return float(extra_stats.get(key, default))

## 是否带嘲讽 → 敌人优先攻击本单位（吸火力保后排）。两种来源：
##   ① 常驻副属性 taunt>0（物品：挑衅护符/诱敌面具）
##   ② 临时嘲讽效果（主动技能"挑衅怒吼"施放，active_effects 里的 taunt，按回合到期）
## 与 CombatStrategy.HAS_TAUNT 并列，由 BattleSimulator._find_taunt_target 判定（仅前排生效）。
func has_taunt() -> bool:
	if get_stat("taunt", 0.0) > 0.0:
		return true
	for eff in active_effects:
		if eff.get("type") == "taunt" and eff.get("turns", 0) > 0:
			return true
	return false


# ── 工厂方法 ──────────────────────────────────────────────────────────────────

## 从英雄创建：HP 变化会实时写回原始 Hero 对象
static func from_hero(hero) -> BattleCombatant:
	var bc             = BattleCombatant.new()
	bc.source_name     = hero.entity_name
	bc.current_hp      = hero.current_hp
	bc.max_hp          = hero.get_max_hp()
	bc.attack          = hero.get_attack()
	bc.defense         = hero.get_defense()
	bc.speed           = hero.get_speed()
	bc.magic           = hero.get_magic()
	bc.combat_strategy = hero.combat_strategy
	bc._hero_ref       = hero
	# 蓝量：每场战斗重置为满蓝，mp_regen = max_mp / 6（最少 1）
	bc.max_mp          = hero.get("base_mp") if hero.get("base_mp") else 0
	bc.current_mp      = bc.max_mp
	bc.mp_regen        = max(1, bc.max_mp / 6) if bc.max_mp > 0 else 0
	# 消耗品（副本，不影响原始数组）
	bc.consumables     = hero.get("personal_consumables") if hero.get("personal_consumables") else []
	# 从英雄装备中收集战斗触发效果（荆棘、吸血等特殊装备效果）
	var equipped = hero.get("equipped_items")
	if equipped:
		for slot in equipped:
			var item = equipped[slot]
			if item == null:
				continue
			var item_triggers = item.get("triggers")
			if item_triggers and not item_triggers.is_empty():
				bc.equipment_triggers.append_array(item_triggers)
	return bc


## 从敌人模板创建：满血临时副本，战斗结束丢弃，不写回任何对象
static func from_enemy_data(data) -> BattleCombatant:
	var bc             = BattleCombatant.new()
	bc.source_name     = data.entity_name
	bc.current_hp      = data.base_max_hp
	bc.max_hp          = data.base_max_hp
	bc.attack          = data.base_attack
	bc.defense         = data.base_defense
	bc.speed           = data.base_speed
	bc.magic           = data.base_magic
	# 敌人不参与蓝量系统（mp_cost 默认 0，技能永远可用）
	bc.max_mp          = 0
	bc.current_mp      = 0
	bc.mp_regen        = 0
	bc.combat_strategy = null   # BattleSimulator 在创建后设置
	bc.consumables     = []
	return bc


# ── 状态查询 ──────────────────────────────────────────────────────────────────

func is_alive() -> bool:
	return current_hp > 0

func is_hero() -> bool:
	return _hero_ref != null

func get_hp_percent() -> float:
	if max_hp <= 0:
		return 0.0
	return float(current_hp) / float(max_hp)

## 是否被眩晕（本回合无法行动）
func is_stunned() -> bool:
	for eff in active_effects:
		if eff.get("type") == "stun" and eff.get("turns", 0) > 0:
			return true
	return false


# ── 战斗操作 ──────────────────────────────────────────────────────────────────

## take_damage：承受伤害（含防御计算），用于普通攻击，返回实际伤害值
## 伤害公式：max(1, 攻击力 - 防御力 / 2)
func take_damage(incoming_attack: int) -> int:
	var actual_damage := maxi(1, incoming_attack - defense / 2)
	current_hp = max(0, current_hp - actual_damage)
	if _hero_ref != null:
		_hero_ref.current_hp = current_hp
	return actual_damage


## take_damage_raw：直接扣血（防御由 BattleSimulator 外部算好后传入）
## 护盾优先吸收伤害，返回护盾吸收后的实际伤害（可能为 0）
func take_damage_raw(amount: int) -> int:
	var incoming: int = maxi(1, amount)
	var absorbed: int = _absorb_shield(incoming)
	var actual:   int = incoming - absorbed
	if actual > 0:
		current_hp = maxi(0, current_hp - actual)
		if _hero_ref != null:
			_hero_ref.current_hp = current_hp
	return actual   # 护盾全挡时为 0


## heal：恢复 HP，不超过最大值，返回实际恢复量
func heal(amount: int) -> int:
	var actual := mini(amount, max_hp - current_hp)
	current_hp += actual
	if _hero_ref != null:
		_hero_ref.current_hp = current_hp
	return actual


## try_use_consumable：检查是否应该自动使用消耗品（HP 低于阈值时触发）
func try_use_consumable():   # → Consumable or null
	for i in range(consumables.size()):
		var item = consumables[i]
		if item.effect_type == "heal_hp" and get_hp_percent() <= item.auto_use_hp_threshold:
			consumables.remove_at(i)
			heal(item.effect_value)
			return item
	return null


## apply_consumable_effect：消耗品 Buff 效果（如攻击/防御加成药水）
func apply_consumable_effect(effect_type: String, value: int) -> void:
	match effect_type:
		"boost_attack":  attack  = max(0, attack  + value)
		"boost_defense": defense = max(0, defense + value)


# ── 效果施加接口 ──────────────────────────────────────────────────────────────

## apply_buff：施加属性强化 Buff（立即修改属性，同时记入 active_effects 用于过期追踪）
## stat: "attack" / "defense" / "speed" / "magic"
## turns: -1 = 战斗全程持续；>0 = 持续 N 次 tick_effects() 后过期并还原
func apply_buff(stat: String, value: int, turns: int) -> void:
	match stat:
		"attack":  attack  += value
		"defense": defense += value
		"speed":   speed    = max(1, speed + value)
		"magic":   magic   += value
	active_effects.append({ "type": "buff", "stat": stat, "value": value, "turns": turns })


## apply_stun：施加眩晕（取较大值，不叠加但可刷新）
func apply_stun(turns: int) -> void:
	for eff in active_effects:
		if eff.get("type") == "stun":
			eff["turns"] = max(eff["turns"], turns)
			return
	active_effects.append({ "type": "stun", "turns": turns })


## apply_slow：施加减速（若已有减速先还原再重新施加，不叠加）
func apply_slow(amount: int, turns: int) -> void:
	for i in range(active_effects.size() - 1, -1, -1):
		if active_effects[i].get("type") == "slow":
			speed += active_effects[i].get("amount", 0)   # 还原旧速度
			active_effects.remove_at(i)
			break
	speed = max(1, speed - amount)
	active_effects.append({ "type": "slow", "amount": amount, "turns": turns })


## apply_dot：施加持续伤害（取较大 damage，turns 取新值）
func apply_dot(damage_per_turn: int, turns: int) -> void:
	for eff in active_effects:
		if eff.get("type") == "dot":
			eff["damage"] = max(eff["damage"], damage_per_turn)
			eff["turns"]  = turns
			return
	active_effects.append({ "type": "dot", "damage": damage_per_turn, "turns": turns, "element": "poison" })


## apply_shield：施加护盾（可叠加，每个护盾独立记录）
func apply_shield(amount: int) -> void:
	active_effects.append({ "type": "shield", "amount": amount })


## apply_taunt：施加临时嘲讽（主动技能用；不叠加，取较大 turns 刷新）
## 计时由 tick_effects() 递减，到期解除。has_taunt() 会读它。
func apply_taunt(turns: int) -> void:
	for eff in active_effects:
		if eff.get("type") == "taunt":
			eff["turns"] = max(eff["turns"], turns)
			return
	active_effects.append({ "type": "taunt", "turns": turns })


# ── 蓝量 ──────────────────────────────────────────────────────────────────────

## 消耗蓝量，返回实际消耗量（蓝量不足时返回 -1）
func spend_mp(cost: int) -> int:
	if current_mp < cost:
		return -1
	current_mp -= cost
	return cost

## 回复蓝量，不超过上限
func regen_mp(amount: int) -> void:
	current_mp = min(max_mp, current_mp + amount)


# ── 技能回合冷却 ──────────────────────────────────────────────────────────────

## 该技能当前是否在冷却中（剩余 > 0）
func is_skill_on_cooldown(skill_id: String) -> bool:
	return int(skill_cooldowns.get(skill_id, 0)) > 0

## 使用技能后触发冷却（仅当该技能在 config 里配了 > 0 的冷却）
func trigger_skill_cooldown(skill_id: String) -> void:
	var cd: int = int(skill_cd_config.get(skill_id, 0))
	if cd > 0:
		skill_cooldowns[skill_id] = cd

## 行动开始时调用：所有技能冷却 -1，归零移除
func tick_cooldowns() -> void:
	var next: Dictionary = {}
	for sid in skill_cooldowns:
		var r: int = int(skill_cooldowns[sid]) - 1
		if r > 0:
			next[sid] = r
	skill_cooldowns = next


# ── 回合结算 ──────────────────────────────────────────────────────────────────

## tick_status：回合开始时由 BattleSimulator 调用
## 结算 MP 回蓝 + DoT 伤害，返回本回合 DoT 总伤害（已扣血）
func tick_status() -> int:
	var dot_dealt := 0

	# MP 回蓝（静默，不记日志）
	if mp_regen > 0:
		regen_mp(mp_regen)

	# DoT 伤害结算（受 1/4 防御减免，直接扣血，不经过护盾）
	var next_effects: Array = []
	for eff in active_effects:
		if eff.get("type") != "dot":
			next_effects.append(eff)
			continue
		var actual: int = maxi(1, eff["damage"] - defense / 4)
		current_hp  = max(0, current_hp - actual)
		if _hero_ref != null:
			_hero_ref.current_hp = current_hp
		dot_dealt    += actual
		eff["turns"] -= 1
		if eff["turns"] > 0:
			next_effects.append(eff)
		# turns == 0：DoT 结束，不再 append

	active_effects = next_effects
	return dot_dealt


## tick_effects：单位行动或被眩晕后由 BattleSimulator 调用（替代旧版 tick_slow）
## 统一递减 stun / slow / buff 的剩余计时，过期时自动还原属性
## "dot" 由 tick_status 管理，"shield" 由 _absorb_shield 管理，此处直接保留
func tick_effects() -> void:
	var next_effects: Array = []

	for eff in active_effects:
		match eff.get("type", ""):

			"stun":
				eff["turns"] -= 1
				if eff["turns"] > 0:
					next_effects.append(eff)
				# turns == 0：眩晕解除，不再 append

			"slow":
				eff["turns"] -= 1
				if eff["turns"] <= 0:
					speed += eff.get("amount", 0)   # 还原速度
				else:
					next_effects.append(eff)

			"taunt":
				eff["turns"] -= 1
				if eff["turns"] > 0:
					next_effects.append(eff)
				# turns == 0：临时嘲讽解除，不再 append

			"buff":
				if eff.get("turns") == -1:
					next_effects.append(eff)   # 永久 Buff，不倒计
				else:
					eff["turns"] -= 1
					if eff["turns"] <= 0:
						# 过期：还原属性
						match eff.get("stat", ""):
							"attack":  attack  -= eff.get("value", 0)
							"defense": defense -= eff.get("value", 0)
							"speed":   speed   -= eff.get("value", 0)
							"magic":   magic   -= eff.get("value", 0)
					else:
						next_effects.append(eff)

			_:   # "dot" 和 "shield" 以及未来新类型由各自逻辑管理，此处保留
				next_effects.append(eff)

	active_effects = next_effects


# ── 私有工具 ──────────────────────────────────────────────────────────────────

## 护盾吸收：消耗 active_effects 中的 shield 条目，返回实际吸收量
func _absorb_shield(incoming: int) -> int:
	var absorbed := 0
	for eff in active_effects:
		if eff.get("type") != "shield":
			continue
		var can_absorb: int = min(eff.get("amount", 0), incoming - absorbed)
		eff["amount"] -= can_absorb
		absorbed      += can_absorb
		if absorbed >= incoming:
			break
	# 清除已耗尽的护盾条目
	active_effects = active_effects.filter(
		func(e): return e.get("type") != "shield" or e.get("amount", 0) > 0
	)
	return absorbed
