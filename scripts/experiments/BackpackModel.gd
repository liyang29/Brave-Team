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
# 每件：name + 属性(atk/def/hp/magic) + tag(用于协同) + rarity(战利品掉落权重档)
# rarity: "common"/"rare"/"epic"，权重见 LootTable.RARITY_WEIGHTS。
const ITEMS: Dictionary = {
	"iron_sword":  { "name": "铁剑",   "atk": 6,  "tag": "blade",   "rarity": "common" },
	"longsword":   { "name": "长剑",   "atk": 8,  "tag": "blade",   "rarity": "rare" },
	"whetstone":   { "name": "磨刀石", "atk": 2,  "tag": "sharpen", "rarity": "common" },
	"shield":      { "name": "圆盾",   "def": 5,  "tag": "guard",   "rarity": "common" },
	"chainmail":   { "name": "锁甲",   "def": 6, "hp": 10, "tag": "armor", "rarity": "rare" },
	"leather":     { "name": "皮甲",   "def": 3, "hp": 15, "tag": "armor", "rarity": "common" },
	"staff":       { "name": "法杖",   "magic": 6, "tag": "arcane", "rarity": "rare" },
	"tome":        { "name": "魔典",   "magic": 4, "tag": "arcane", "rarity": "common" },
	"holy_symbol": { "name": "圣徽",   "magic": 5, "tag": "holy",   "rarity": "rare" },
	"amulet":      { "name": "护符",   "hp": 12, "def": 2, "tag": "vital", "rarity": "common" },
	"charm":       { "name": "红宝石", "hp": 20, "tag": "vital",    "rarity": "rare" },

	# ── 副属性物品（第一个副属性：暴击）──────────────────────────────────────
	"crit_gem":    { "name": "暴击宝石", "crit_chance": 0.15, "tag": "crit", "rarity": "epic" },
	"keen_edge":   { "name": "锋锐之刃", "atk": 4, "crit_chance": 0.10, "tag": "blade", "rarity": "rare" },
	"berserk_ring":{ "name": "狂战戒",   "crit_dmg": 0.5, "tag": "crit",  "rarity": "epic" },

	# ── 技能书（占格、不给属性；认职业；带回合冷却）──────────────────────────
	# 技能书 = 把"技能"也做成背包物品：占格 → 和装备抢空间（带书=少带甲）。
	# 职业由对应技能的 SkillTable.hero_class 决定（实验里按持有者职业过滤）。
	"book_slash":    { "name": "斩击书", "tag": "skillbook", "skill_id": "slash",     "cd": 1, "rarity": "common" },
	"book_cleave":   { "name": "横扫书", "tag": "skillbook", "skill_id": "cleave",    "cd": 2, "rarity": "rare" },
	"book_fireball": { "name": "火球书", "tag": "skillbook", "skill_id": "fireball",  "cd": 2, "rarity": "rare" },
	"book_icelance": { "name": "冰枪书", "tag": "skillbook", "skill_id": "ice_lance", "cd": 1, "rarity": "rare" },
	"book_heal":     { "name": "治疗书", "tag": "skillbook", "skill_id": "holy_heal", "cd": 1, "rarity": "common" },
	"book_purify":   { "name": "净化书", "tag": "skillbook", "skill_id": "purify",    "cd": 2, "rarity": "common" },
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


const _RARITY_ZH: Dictionary = { "common": "普通", "rare": "稀有", "epic": "史诗" }
const _TAG_HINT: Dictionary = {
	"blade": "刃 · 与磨刀石相邻 = 开刃(攻+6)",
	"sharpen": "磨 · 与刀刃相邻 = 开刃(攻+6)",
	"guard": "盾 · 与护甲相邻 = 重装(防+5血+12)",
	"armor": "甲 · 与盾相邻 = 重装(防+5血+12)",
	"arcane": "法器 · 两件相邻 = 共鸣(魔+6)",
	"vital": "生命 · 两件相邻 = 生机(血+18)",
}

## 物品详细信息（鼠标悬浮 tooltip 用，多行）。
static func item_tooltip(item_id: String) -> String:
	var it: Dictionary = ITEMS.get(item_id, {})
	if it.is_empty():
		return item_id
	var lines: Array = []
	lines.append("%s 【%s】" % [it.get("name", item_id), _RARITY_ZH.get(it.get("rarity", "common"), "普通")])

	if it.get("tag", "") == "skillbook":
		var sid: String = it.get("skill_id", "")
		lines.append("技能书 · 冷却 %d 回合（占格、和装备抢空间）" % int(it.get("cd", 0)))
		lines.append("认职业：%s" % _class_zh(SkillTable.get_skill(sid).get("hero_class", "")))
		lines.append("效果：" + _skill_effect_text(sid))
		return "\n".join(lines)

	# 装备：属性 + 协同提示
	var stats: Array = []
	if int(it.get("atk", 0)) != 0:   stats.append("攻 +%d" % it["atk"])
	if int(it.get("def", 0)) != 0:   stats.append("防 +%d" % it["def"])
	if int(it.get("hp", 0)) != 0:    stats.append("血 +%d" % it["hp"])
	if int(it.get("magic", 0)) != 0: stats.append("魔 +%d" % it["magic"])
	if float(it.get("crit_chance", 0.0)) != 0.0: stats.append("暴击 +%d%%" % int(it["crit_chance"] * 100))
	if float(it.get("crit_dmg", 0.0)) != 0.0:    stats.append("暴伤 +%d%%" % int(it["crit_dmg"] * 100))
	if not stats.is_empty():
		lines.append("属性：" + "  ".join(stats))
	var hint: String = _TAG_HINT.get(it.get("tag", ""), "")
	if hint != "":
		lines.append("协同：" + hint)
	return "\n".join(lines)


static func _class_zh(c: String) -> String:
	match c:
		"warrior": return "战士"
		"mage":    return "法师"
		"priest":  return "牧师"
		"rogue":   return "盗贼"
		"archer":  return "猎人"
	return c if c != "" else "通用"

# 把 SkillTable 的技能数据转成一句人话效果
static func _skill_effect_text(sid: String) -> String:
	var s: Dictionary = SkillTable.get_skill(sid)
	if s.is_empty():
		return sid
	var t: String = s.get("type", "damage")
	var mp: String = "（耗蓝 %d）" % int(s.get("mp_cost", 0)) if int(s.get("mp_cost", 0)) > 0 else ""
	if t == "heal_ally":
		return "治疗血量最少的友军，回血 = %.1f×魔力 %s" % [float(s.get("power", 1.0)), mp]
	if t == "buff_self":
		var b: Array = []
		if int(s.get("buff_attack", 0)) != 0:  b.append("攻+%d" % s["buff_attack"])
		if int(s.get("buff_defense", 0)) != 0: b.append("防+%d" % s["buff_defense"])
		if int(s.get("buff_speed", 0)) != 0:   b.append("速+%d" % s["buff_speed"])
		if int(s.get("buff_magic", 0)) != 0:   b.append("魔+%d" % s["buff_magic"])
		var dur: String = "全程" if int(s.get("buff_turns", -1)) < 0 else "%d回合" % int(s.get("buff_turns", 0))
		return "强化自身 %s（%s）%s" % [", ".join(b), dur, mp]
	# damage 类
	var attr: String = "魔法" if s.get("use_magic", false) else "物理"
	var parts: Array = ["造成 %.1f×%s 伤害" % [float(s.get("power", 1.0)), attr]]
	if s.get("aoe", false):        parts.append("群体")
	if s.get("ignore_def", false): parts.append("无视防御")
	elif s.get("half_def", false): parts.append("半防")
	if int(s.get("stun_turns", 0)) > 0:  parts.append("眩晕%d回合" % int(s["stun_turns"]))
	if int(s.get("slow_turns", 0)) > 0:  parts.append("减速%d回合" % int(s["slow_turns"]))
	if float(s.get("dot_power", 0.0)) > 0.0: parts.append("中毒%d回合" % int(s.get("dot_turns", 0)))
	return "，".join(parts) + " " + mp
