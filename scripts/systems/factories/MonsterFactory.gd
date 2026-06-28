class_name MonsterFactory

# ─────────────────────────────────────────────────────────────────────────────
# MonsterFactory — 怪物生成工厂（纯静态工具类，仿 HeroFactory）
#
# 怪物数值数据驱动：一张 ENEMIES 表，加一只怪 = 加一行。
# create(id) 按表造一个 EnemyData 实例（每次新实例，可重复造同种怪）。
# AI 策略由 EnemyData.ai_type 决定（实际策略对象在 BattleSimulator 经 EnemyAIFactory 注入）。
#
# 取代过去散在 RunManager._e() / 实验场景 _enemy() 里的内联手搓怪物。
# ─────────────────────────────────────────────────────────────────────────────

# ── 怪物表 ────────────────────────────────────────────────────────────────────
# 每只：name + hp/atk/def/spd（必填）；magic 选填(默认=atk)；row/ranged/ai 选填。
#   row    : "front"/"back"（默认 front）
#   ranged : 是否远程（默认 false）
#   ai     : EnemyData.AI_*（默认 AI_BASIC_ATTACK）
const ENEMIES: Dictionary = {
	# ── 跑局线（村庄→林间→剧毒→泉水→废墟→魔王）──────────────────────────────
	"wolf":        { "name": "野狼", "hp": 56, "atk": 10, "def": 2, "spd": 9 },
	"venom_bug":   { "name": "毒虫", "hp": 45, "atk": 8,  "def": 1, "spd": 11, "row": "back", "ranged": true },
	"stone_guard": { "name": "石卫", "hp": 93, "atk": 10, "def": 7, "spd": 6 },
	"bandit":      { "name": "强盗", "hp": 78, "atk": 12, "def": 4, "spd": 10 },
	"ranger":      { "name": "游侠", "hp": 60, "atk": 11, "def": 2, "spd": 12, "row": "back", "ranged": true },
	"demon_lord":  { "name": "魔王", "hp": 222, "atk": 18, "def": 10, "spd": 10 },
	"claw_minion": { "name": "爪牙", "hp": 84, "atk": 12, "def": 4, "spd": 9 },

	# ── 实验场景用（前排蛮兵 + 后排巫师）──────────────────────────────────────
	"brute":     { "name": "蛮兵",   "hp": 90, "atk": 15, "def": 6, "spd": 8, "ai": EnemyData.AI_AGGRESSIVE },
	"dark_mage": { "name": "黑巫师", "hp": 60, "atk": 17, "def": 3, "spd": 11, "row": "back", "ranged": true, "ai": EnemyData.AI_SPELLCASTER },
}


# create：按 id 造一个 EnemyData。name_override 可覆盖显示名（如同种怪标"甲/乙"）。
static func create(id: String, name_override: String = "") -> EnemyData:
	var d: Dictionary = ENEMIES.get(id, {})
	if d.is_empty():
		push_warning("MonsterFactory: 未知怪物 id '%s'，返回占位弱怪" % id)
	var e: EnemyData = EnemyData.new()
	e.entity_name = name_override if name_override != "" else String(d.get("name", id))
	e.base_max_hp = int(d.get("hp", 1))
	e.base_attack = int(d.get("atk", 1))
	e.base_defense = int(d.get("def", 0))
	e.base_speed = int(d.get("spd", 10))
	e.base_magic = int(d.get("magic", d.get("atk", 1)))   # 默认魔力=攻击（沿用旧约定）
	e.preferred_row = String(d.get("row", "front"))
	e.is_ranged = bool(d.get("ranged", false))
	e.ai_type = d.get("ai", EnemyData.AI_BASIC_ATTACK)
	return e


# create_group：按 id 列表批量造（地图节点常用）。
static func create_group(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(create(id))
	return out
