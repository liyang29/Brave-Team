class_name Equipment extends Item

# ─────────────────────────────────────────────────────────────────────────────
# Equipment — 可装备物品
#
# 继承关系：Equipment → Item → GameEntity → Resource
#
# 核心设计：
#   装备上的属性加成以 Array[StatModifier] 形式存储。
#   当英雄装备/卸下此物品时，Hero.equip/unequip 调用 StatBlock.rebuild()，
#   StatBlock 会重新扫描 equipped_items 中所有 Equipment 的 modifiers，
#   重建永久属性修正列表。
#
# 数据文件示例（iron_sword.tres）：
#   slot_name   = "weapon"
#   modifiers   = [StatModifier(ATTACK, FLAT, 10, -1, "iron_sword")]
#   rarity      = COMMON
#   sell_price  = 50
# ─────────────────────────────────────────────────────────────────────────────


# ── 装备槽 ────────────────────────────────────────────────────────────────────

# 对应 Hero 的 ALL_SLOTS 常量（head/chest/legs/feet/weapon/offhand/accessory）
# 装备时 Hero.equip() 读取这个字段决定放哪个槽
@export var slot_name: String = "weapon"


# ── 属性修正 ──────────────────────────────────────────────────────────────────

# 此装备提供的所有属性加成
# 元素类型为 StatModifier，remaining_turns = -1（永久），source_id = instance_id
# 注意：StatModifier 是 RefCounted，不能直接 @export 到 .tres（Inspector 不支持）
#       所以这里用 Array（无类型注释），在运行时由 ItemFactory 创建时填充
var modifiers: Array = []   # Array[StatModifier]

# Inspector 用替代字段：在编辑器里配置装备加成数据，运行时由 ItemFactory 转换
# 格式：每条记录 { "stat": int, "type": int, "value": float }
# stat  → StatBlock.Stat 枚举值（0=MAX_HP, 1=ATTACK, 2=DEFENSE, 3=SPEED, 4=MAGIC）
# type  → StatModifier.Type 枚举值（0=FLAT, 1=PERCENT）
# value → 修正数值
@export var modifier_configs: Array = []


# ── 战斗触发效果 ──────────────────────────────────────────────────────────────

# Inspector 用配置字段（同 modifier_configs 模式，运行时通过 build_triggers() 展开）
# 格式：每条 { "trigger": String, "effect": String, "value": Variant }
#   trigger: "on_hit_taken"（受击）/ "on_kill"（击杀）/ "on_hit_dealt"（命中）
#   effect:  "thorns"（反伤，value = 比例如 0.15）
#            "lifesteal"（吸血，value = 固定值）
#            "regen_mp"（回蓝，value = 固定值）
# 示例（荆棘甲）：[{ "trigger": "on_hit_taken", "effect": "thorns", "value": 0.15 }]
@export var trigger_configs: Array = []

# 运行时触发器列表（战斗开始时由 BattleCombatant.from_hero() 收集）
var triggers: Array = []


# ── 初始化 ────────────────────────────────────────────────────────────────────

# 从 modifier_configs 构建运行时 modifiers 数组
# ItemFactory.create_equipment() 会在创建物品时调用此方法
func build_modifiers() -> void:
	modifiers.clear()
	for cfg in modifier_configs:
		var mod = StatModifier.new(
			cfg.get("stat",   0),
			cfg.get("type",   StatModifier.Type.FLAT),
			cfg.get("value",  0.0),
			-1,          # 永久生效
			instance_id  # 来源 ID = 本物品实例 ID，方便 StatBlock 按来源移除
		)
		modifiers.append(mod)

# 从 trigger_configs 展开运行时 triggers（战斗触发器，战斗开始时由 BattleCombatant 读取）
func build_triggers() -> void:
	triggers = trigger_configs.duplicate(true)


# ── 存档 ──────────────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var data                  = super.to_dict()
	data["slot_name"]         = slot_name
	data["modifier_configs"]  = modifier_configs.duplicate(true)
	data["trigger_configs"]   = trigger_configs.duplicate(true)
	# modifiers / triggers 是运行时对象，不存档，读档时通过 build_*() 重建
	return data

func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	slot_name        = data.get("slot_name",        "weapon")
	modifier_configs = data.get("modifier_configs", []).duplicate(true)
	trigger_configs  = data.get("trigger_configs",  []).duplicate(true)
	build_modifiers()   # 重建属性修正
	build_triggers()    # 重建战斗触发器
