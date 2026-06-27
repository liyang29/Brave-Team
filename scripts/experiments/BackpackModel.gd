extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# BackpackModel — 背包数据 + 邻接协同计算（纯数据/纯函数，便于测试与复用）
#
# 方案 B 新方向（"商队远征版 Megaloot + 小队"）的核心：
#   背包 = 网格，物品占格子（空间有限 → 取舍），相邻同类触发协同（摆位 → 深度）。
#
# 故意不带 class_name（用 preload 引入），避免全局类缓存时序问题。
# 场景与测试都 preload 本文件，调静态函数。
# ─────────────────────────────────────────────────────────────────────────────

# ── 物品表 ────────────────────────────────────────────────────────────────────
# 每件：name + 属性(atk/def/hp/magic) + tag(用于协同)
const ITEMS: Dictionary = {
	"iron_sword":  { "name": "铁剑",   "atk": 6,  "tag": "blade" },
	"longsword":   { "name": "长剑",   "atk": 8,  "tag": "blade" },
	"whetstone":   { "name": "磨刀石", "atk": 2,  "tag": "sharpen" },
	"shield":      { "name": "圆盾",   "def": 5,  "tag": "guard" },
	"chainmail":   { "name": "锁甲",   "def": 6, "hp": 10, "tag": "armor" },
	"leather":     { "name": "皮甲",   "def": 3, "hp": 15, "tag": "armor" },
	"staff":       { "name": "法杖",   "magic": 6, "tag": "arcane" },
	"tome":        { "name": "魔典",   "magic": 4, "tag": "arcane" },
	"holy_symbol": { "name": "圣徽",   "magic": 5, "tag": "holy" },
	"amulet":      { "name": "护符",   "hp": 12, "def": 2, "tag": "vital" },
	"charm":       { "name": "红宝石", "hp": 20, "tag": "vital" },

	# ── 副属性物品（第一个副属性：暴击）──────────────────────────────────────
	"crit_gem":    { "name": "暴击宝石", "crit_chance": 0.15, "tag": "crit" },
	"keen_edge":   { "name": "锋锐之刃", "atk": 4, "crit_chance": 0.10, "tag": "blade" },
	"berserk_ring":{ "name": "狂战戒",   "crit_dmg": 0.5, "tag": "crit" },

	# ── 技能书（占格、不给属性；认职业；带回合冷却）──────────────────────────
	# 技能书 = 把"技能"也做成背包物品：占格 → 和装备抢空间（带书=少带甲）。
	# 职业由对应技能的 SkillTable.hero_class 决定（实验里按持有者职业过滤）。
	"book_slash":    { "name": "斩击书", "tag": "skillbook", "skill_id": "slash",     "cd": 1 },
	"book_cleave":   { "name": "横扫书", "tag": "skillbook", "skill_id": "cleave",    "cd": 2 },
	"book_fireball": { "name": "火球书", "tag": "skillbook", "skill_id": "fireball",  "cd": 2 },
	"book_icelance": { "name": "冰枪书", "tag": "skillbook", "skill_id": "ice_lance", "cd": 1 },
	"book_heal":     { "name": "治疗书", "tag": "skillbook", "skill_id": "holy_heal", "cd": 1 },
	"book_purify":   { "name": "净化书", "tag": "skillbook", "skill_id": "purify",    "cd": 2 },
}

# ── 邻接协同规则 ──────────────────────────────────────────────────────────────
# 两个 tag 在网格中正交相邻 → 给该背包持有者加成（每对相邻只算一次）
const SYNERGIES: Array = [
	{ "a": "blade",  "b": "sharpen", "bonus": { "atk": 6 },            "name": "开刃" },
	{ "a": "guard",  "b": "armor",   "bonus": { "def": 5, "hp": 12 },  "name": "重装" },
	{ "a": "arcane", "b": "arcane",  "bonus": { "magic": 6 },          "name": "共鸣" },
	{ "a": "vital",  "b": "vital",   "bonus": { "hp": 18 },            "name": "生机" },
]


# 副属性 key 列表：以后加新副属性（吸血/法抗/破甲…）只需往这里加 key，
# 物品声明该 key、战斗公式读 BattleCombatant.get_stat()，compute 自动累加。
const EXTRA_KEYS: Array = ["crit_chance", "crit_dmg"]

## 计算一个背包的总加成。
## grid: { Vector2i(col,row): item_id }
## 返回: { "atk","def","hp","magic":int, "synergies":Array, "books":Array, "extra":Dictionary }
static func compute(grid: Dictionary) -> Dictionary:
	var atk: int = 0
	var def_v: int = 0
	var hp: int = 0
	var magic: int = 0
	var fired: Array = []
	var books: Array = []   # [{ "id": skill_id, "cd": cd_turns }]
	var extra: Dictionary = {}   # 副属性累加（crit_chance 等）

	# 物品基础属性（技能书无属性，只收集到 books）
	for cell in grid:
		var it: Dictionary = ITEMS.get(grid[cell], {})
		if it.get("tag", "") == "skillbook":
			books.append({ "id": it.get("skill_id", ""), "cd": int(it.get("cd", 0)) })
			continue
		atk   += int(it.get("atk", 0))
		def_v += int(it.get("def", 0))
		hp    += int(it.get("hp", 0))
		magic += int(it.get("magic", 0))
		# 副属性（通用累加，加新属性无需改这里的逻辑）
		for k in EXTRA_KEYS:
			if it.has(k):
				extra[k] = float(extra.get(k, 0.0)) + float(it[k])

	# 邻接协同：每格只看右、下邻居，保证每对相邻只算一次
	for cell in grid:
		var tag: String = ITEMS.get(grid[cell], {}).get("tag", "")
		if tag == "":
			continue
		for nb in [cell + Vector2i(1, 0), cell + Vector2i(0, 1)]:
			if not grid.has(nb):
				continue
			var tag2: String = ITEMS.get(grid[nb], {}).get("tag", "")
			for s in SYNERGIES:
				var sa: String = s["a"]
				var sb: String = s["b"]
				if (tag == sa and tag2 == sb) or (tag == sb and tag2 == sa):
					var bonus: Dictionary = s["bonus"]
					atk   += int(bonus.get("atk", 0))
					def_v += int(bonus.get("def", 0))
					hp    += int(bonus.get("hp", 0))
					magic += int(bonus.get("magic", 0))
					fired.append(s["name"])

	return { "atk": atk, "def": def_v, "hp": hp, "magic": magic, "synergies": fired, "books": books, "extra": extra }


## 物品显示名
static func item_name(item_id: String) -> String:
	return ITEMS.get(item_id, {}).get("name", item_id)

## 物品简短属性描述（UI 用）
static func item_desc(item_id: String) -> String:
	var it: Dictionary = ITEMS.get(item_id, {})
	if it.get("tag", "") == "skillbook":
		return "%s(技能·CD%d)" % [it.get("name", item_id), int(it.get("cd", 0))]
	var parts: Array = []
	if int(it.get("atk", 0)) != 0:   parts.append("攻+%d" % it["atk"])
	if int(it.get("def", 0)) != 0:   parts.append("防+%d" % it["def"])
	if int(it.get("hp", 0)) != 0:    parts.append("血+%d" % it["hp"])
	if int(it.get("magic", 0)) != 0: parts.append("魔+%d" % it["magic"])
	if float(it.get("crit_chance", 0.0)) != 0.0: parts.append("暴击+%d%%" % int(it["crit_chance"] * 100))
	if float(it.get("crit_dmg", 0.0)) != 0.0:    parts.append("暴伤+%d%%" % int(it["crit_dmg"] * 100))
	return "%s(%s)" % [it.get("name", item_id), ", ".join(parts)]
