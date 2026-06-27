class_name StatBlock extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# StatBlock — 装饰器容器（属性计算器）
#
# 每个 Hero 拥有一个 StatBlock，负责把"基础属性 + 装备加成 + 临时Buff"
# 叠加成最终属性值。
#
# 装饰器模式在这里的体现：
#   base_value（Hero 的 base_xxx）是"被装饰的原始对象"
#   StatModifier 是一层层套上去的"装饰器"
#   calculate() 最终返回叠加所有装饰后的结果
#
# 计算顺序：先加所有 FLAT 修正，再乘所有 PERCENT 修正
#   例：base_attack=20, FLAT+10, PERCENT+15%
#   → (20+10) × 1.15 = 34（向下取整）
# ─────────────────────────────────────────────────────────────────────────────


# ── 属性枚举 ──────────────────────────────────────────────────────────────────

# 与 StatModifier.stat 字段对应，使用 int 存储避免循环引用
enum Stat {
	MAX_HP,
	ATTACK,
	DEFENSE,
	SPEED,
	MAGIC
}


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 持有 Hero 的引用，用于读取 base_xxx 原始值和 equipped_items
# 类型写 Object 避免与 Hero.gd 形成循环依赖（Hero 引用 StatBlock，StatBlock 引用 Hero）
var _owner: Object  # 实际上是 Hero 实例

# 当前生效的所有属性修正
var _modifiers: Array[StatModifier] = []


# ── 构造函数 ──────────────────────────────────────────────────────────────────

func _init(owner: Object) -> void:
	_owner = owner


# ── 核心计算 ──────────────────────────────────────────────────────────────────

# calculate：计算某属性的最终值（基础值 + 所有修正叠加）
#
# 计算过程：
#   1. 从 _owner 读取对应的 base_xxx 值
#   2. 累加所有 FLAT 修正
#   3. 累加所有 PERCENT 修正（转成乘数）
#   4. 最终值 = (base + flat_total) × pct_multiplier
#   5. 向下取整，最小为 1
func calculate(stat: Stat) -> int:
	var base_val = _get_base(stat)
	var flat_sum: float = 0.0
	var pct_sum:  float = 0.0

	for m in _modifiers:
		if m.stat != stat:
			continue
		if m.mod_type == StatModifier.Type.FLAT:
			flat_sum += m.value
		else:
			pct_sum += m.value

	var result = (base_val + flat_sum) * (1.0 + pct_sum / 100.0)
	return max(1, int(result))


# ── 修正管理 ──────────────────────────────────────────────────────────────────

# add_modifier：添加一条属性修正（Buff 或装备加成）
func add_modifier(mod: StatModifier) -> void:
	_modifiers.append(mod)

# remove_by_source：按来源 ID 精准移除某来源的所有修正
# 例如：卸下装备时移除那件装备产生的所有 StatModifier
func remove_by_source(source_id: String) -> void:
	_modifiers = _modifiers.filter(func(m): return m.source_id != source_id)

# tick_turn：每回合结束时调用，减少临时 Buff 的剩余回合数，自动清理过期的
func tick_turn() -> void:
	for m in _modifiers:
		if m.remaining_turns > 0:
			m.remaining_turns -= 1
	_modifiers = _modifiers.filter(func(m): return not m.is_expired())

# rebuild：重建装备层的修正（当装备变化时调用）
# 逻辑：保留所有临时 Buff（remaining_turns > 0），丢弃永久修正，
#       然后重新从当前装备中生成永久修正
func rebuild() -> void:
	# 只保留临时 Buff
	_modifiers = _modifiers.filter(func(m): return not m.is_permanent())
	# 重新加载当前装备的永久修正
	if _owner == null:
		return
	var equipped = _owner.get("equipped_items")
	if equipped == null:
		return
	for slot in equipped:
		var item = equipped[slot]
		if item == null:
			continue
		# Equipment 上存放的 modifiers 数组（将在 Equipment.gd 里定义）
		var item_mods = item.get("modifiers")
		if item_mods == null:
			continue
		for mod in item_mods:
			_modifiers.append(mod)


# ── 私有工具 ──────────────────────────────────────────────────────────────────

# _get_base：从 _owner 读取某属性的基础值
func _get_base(stat: Stat) -> int:
	match stat:
		Stat.MAX_HP:  return _owner.get("base_max_hp")  if _owner else 0
		Stat.ATTACK:  return _owner.get("base_attack")  if _owner else 0
		Stat.DEFENSE: return _owner.get("base_defense") if _owner else 0
		Stat.SPEED:   return _owner.get("base_speed")   if _owner else 0
		Stat.MAGIC:   return _owner.get("base_magic")   if _owner else 0
	return 0
