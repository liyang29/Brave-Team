class_name TurnLog extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# TurnLog — 单回合行动日志
#
# BattleSimulator 每个行动单位行动一次，生成一条 TurnLog。
# BattleResult 收集所有 TurnLog，BattleUI 顺序读取播放动画。
#
# 设计原则：TurnLog 只存字符串和数值，不存对象引用。
#   这样日志可以在战斗结束后独立存在，BattleUI 播放动画时不需要对象还活着。
# ─────────────────────────────────────────────────────────────────────────────


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 行动者名称（英雄或敌人的 entity_name）
var actor_name: String = ""

# 行动目标名称
var target_name: String = ""

# 使用的技能 ID（空字符串 = 普通攻击）
var skill_id: String = ""

# 造成的伤害值（已扣除防御后的实际伤害）
var damage: int = 0

# 此行动是否击杀了目标（供 BattleUI 播放死亡动画）
var is_kill: bool = false

# 此次伤害是否暴击（供 UI 显示"暴击!"）
var is_crit: bool = false

# 此回合自动使用了哪种消耗品（空字符串 = 未使用）
# 存 effect_type 字符串（如 "heal_hp"），供 UI 显示图标和文字提示
var consumable_used: String = ""

# 消耗品恢复/效果数值（例如回复了多少 HP）
var consumable_value: int = 0


# ── 工厂方法 ──────────────────────────────────────────────────────────────────

# 创建一条普通攻击日志
static func attack(
	p_actor:   String,
	p_target:  String,
	p_damage:  int,
	p_is_kill: bool = false
) -> TurnLog:
	var log          = TurnLog.new()
	log.actor_name   = p_actor
	log.target_name  = p_target
	log.damage       = p_damage
	log.is_kill      = p_is_kill
	return log

# 创建一条技能攻击日志
static func skill_attack(
	p_actor:   String,
	p_target:  String,
	p_skill:   String,
	p_damage:  int,
	p_is_kill: bool = false
) -> TurnLog:
	var log          = TurnLog.new()
	log.actor_name   = p_actor
	log.target_name  = p_target
	log.skill_id     = p_skill
	log.damage       = p_damage
	log.is_kill      = p_is_kill
	return log

# 追加消耗品使用记录到已有日志（同一回合内先攻击再自动使用消耗品）
func with_consumable(effect_type: String, value: int) -> TurnLog:
	consumable_used  = effect_type
	consumable_value = value
	return self  # 返回 self 方便链式调用


# ── 调试 ──────────────────────────────────────────────────────────────────────

func describe() -> String:
	var action = "[普攻]" if skill_id.is_empty() else "[%s]" % skill_id
	var result = "%s %s → %s 造成 %d 伤害%s" % [
		actor_name, action, target_name, damage,
		"（击杀）" if is_kill else ""
	]
	if not consumable_used.is_empty():
		result += " / 使用 %s（%+d）" % [consumable_used, consumable_value]
	return result
