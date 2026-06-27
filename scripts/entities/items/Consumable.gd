class_name Consumable extends Item

# ─────────────────────────────────────────────────────────────────────────────
# Consumable — 消耗品
#
# 继承关系：Consumable → Item → GameEntity → Resource
#
# 设计方式：效果类型（字符串）+ 数值，数据驱动。
#   BattleSimulator 读取 effect_type，匹配对应的执行逻辑。
#   新增消耗品只需加 .tres 文件，不需要修改代码（除非 effect_type 全新）。
#
# 支持的 effect_type（在 BattleSimulator 里实现）：
#   "heal_hp"        → 恢复 effect_value 点 HP（固定值）
#   "heal_hp_pct"    → 恢复最大 HP 的 effect_pct 百分比（0.0~1.0，推荐药水使用此类型）
#   "restore_mp"     → 恢复 effect_value 点魔力（法师专用）
#   "boost_attack"   → 本战斗内攻击力 + effect_value（持续 effect_duration 回合）
#   "boost_defense"  → 本战斗内防御力 + effect_value（持续 effect_duration 回合）
#   "revive"         → 防止下一次致死伤害（效果特殊，effect_value 无意义）
#
# 自动使用触发条件：
#   BattleSimulator 在每回合行动后检查 HP 阈值，如果达到触发条件则自动使用。
#   "heal_hp" 的默认触发是 HP < 30%，其他类型可以在战斗前手动使用（待扩展）。
# ─────────────────────────────────────────────────────────────────────────────


# ── 效果类型常量 ──────────────────────────────────────────────────────────────

const EFFECT_HEAL_HP       = "heal_hp"
const EFFECT_HEAL_HP_PCT   = "heal_hp_pct"   # 百分比回血，用 effect_pct 字段
const EFFECT_RESTORE_MP    = "restore_mp"
const EFFECT_BOOST_ATTACK  = "boost_attack"
const EFFECT_BOOST_DEFENSE = "boost_defense"
const EFFECT_REVIVE        = "revive"


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 效果类型（填写上方 EFFECT_xxx 常量之一）
@export var effect_type: String = EFFECT_HEAL_HP

# 效果数值（固定值类型使用）
# heal_hp      → 恢复 HP 量
# restore_mp   → 恢复魔力量
# boost_attack → 攻击力提升量
# boost_defense→ 防御力提升量
# revive       → 无意义，填 0 即可
@export var effect_value: int = 0

# 效果百分比（百分比类型使用，范围 0.0~1.0）
# heal_hp_pct  → 恢复最大 HP × effect_pct 的血量（例：0.4 = 回复 40% 最大生命值）
@export var effect_pct: float = 0.0

# 持续回合数（仅对 Buff 类效果有意义，-1 表示战斗全程）
# heal_hp / restore_mp 填 1（瞬时），boost_xxx 填具体回合数
@export var effect_duration: int = 1

# 自动使用触发：HP 低于此百分比时自动使用（0.0 = 不自动使用）
# 默认 0.3 = HP < 30% 时自动触发
@export var auto_use_hp_threshold: float = 0.3

# 携带数量上限（英雄最多携带多少个）
@export var max_carry: int = 5


# ── 工具方法 ──────────────────────────────────────────────────────────────────

# 判断是否是 Buff 类效果（持续多回合）
func is_buff() -> bool:
	return effect_type in [EFFECT_BOOST_ATTACK, EFFECT_BOOST_DEFENSE]

# 判断是否是瞬时回复类效果
func is_instant_heal() -> bool:
	return effect_type in [EFFECT_HEAL_HP, EFFECT_HEAL_HP_PCT, EFFECT_RESTORE_MP]

# 计算实际回血量（需传入目标最大 HP，供 BattleSimulator 调用）
func calculate_heal(max_hp: int) -> int:
	if effect_type == EFFECT_HEAL_HP_PCT:
		return max(1, int(max_hp * effect_pct))
	return effect_value

# 生成对应的 StatModifier（仅 Buff 类消耗品使用，由 BattleSimulator 调用）
# 返回 null 表示非 Buff 类，不需要创建修正
func create_buff_modifier() -> StatModifier:
	if not is_buff():
		return null
	var stat: int
	match effect_type:
		EFFECT_BOOST_ATTACK:  stat = 1  # StatBlock.Stat.ATTACK
		EFFECT_BOOST_DEFENSE: stat = 2  # StatBlock.Stat.DEFENSE
		_: return null
	return StatModifier.new(
		stat,
		StatModifier.Type.FLAT,
		float(effect_value),
		effect_duration,
		"consumable_" + instance_id
	)


# ── 存档 ──────────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var data                       = super.to_dict()
	data["effect_type"]            = effect_type
	data["effect_value"]           = effect_value
	data["effect_pct"]             = effect_pct
	data["effect_duration"]        = effect_duration
	data["auto_use_hp_threshold"]  = auto_use_hp_threshold
	data["max_carry"]              = max_carry
	return data

func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	effect_type           = data.get("effect_type",           EFFECT_HEAL_HP)
	effect_value          = data.get("effect_value",          0)
	effect_pct            = data.get("effect_pct",            0.0)
	effect_duration       = data.get("effect_duration",       1)
	auto_use_hp_threshold = data.get("auto_use_hp_threshold", 0.3)
	max_carry             = data.get("max_carry",             5)
