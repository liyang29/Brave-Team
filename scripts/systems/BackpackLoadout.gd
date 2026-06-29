extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# BackpackLoadout — 「背包 → 可战斗 Party」翻译器（纯函数，便于测试与复用）
#
# 把每个英雄的【裸 base 属性 + 背包网格】翻译成一支配置完毕、可直接交给
# BattleSimulator 的 Party：
#   - 属性  = 裸 base + BackpackModel.compute(grid) 的加成（攻/防/血/魔）
#   - 技能  = 背包里的技能书（按持有者职业过滤），冷却随书带入
#   - 副属性= 背包累加的 extra（暴击等）
#   - 站位  = squad_slots 摆放（soft_row：row0 前排 / row1 后排）
#
# 【幂等】最终值永远 = 裸 base + 当前背包，绝不读 hero 已 buff 的属性。
#   原因：跑局里每场遭遇前都能重编背包，若拿"已加成的值"再叠会重复累加。
#   → 调用方必须单独保存每个英雄的裸 base，每次 build 都传进来当起点。
#
# 【HP 规则·做法 A】full_heal=false 时只重算上限、当前血钳到新上限，不治疗。
#   加 +HP 装备 = 拉长血条、当前血不变（想回血靠泉水/休息点，符合消耗战）。
#   full_heal=true 供单场实验用（开战即满血）。
#
# 故意不带 class_name（用 preload 引入），同 BackpackModel 路子，避免全局类
# 缓存时序问题。实验场景与 Encounter 都 preload 本文件、调静态函数。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/experiments/BackpackModel.gd")


## 把若干英雄的背包 loadout 翻译成一支配置好的 Party（未开战）。
## loadouts: Array[{ "hero": Hero, "base": Dictionary, "grid": Dictionary }]
##   base: { "hp","atk","def","magic","spd","mp": int }（裸属性，不含背包）
##   grid: { Vector2i(col,row): item_id }
## squad_slots: { Vector2i(col,row): Hero }  row0=前排 / row1=后排（soft_row）
## full_heal: true=开战满血（实验）；false=钳血（跑局消耗战）
## 返回：Party（positioning_mode=soft_row，站位/冷却/副属性已注入）
## 计算全队"最终属性"（裸 base + 自身背包 + 小队光环）。
## 返回 Array[{hp,atk,def,magic,spd,mp}]，与 loadouts 同序。
## 面板显示与开战建队共用同一套，保证"看到的=打出来的"。
static func squad_stats(loadouts: Array, squad_slots: Dictionary) -> Array:
	var n: int = loadouts.size()
	var cell_of: Dictionary = {}
	for cell in squad_slots:
		if squad_slots[cell] != null:
			cell_of[squad_slots[cell]] = cell

	# 阶段1：各人自身最终属性
	var stats: Array = []
	for entry in loadouts:
		var base: Dictionary = entry["base"]
		var b: Dictionary = Backpack.compute(entry["grid"])
		stats.append({
			"hp":    int(base["hp"])    + int(b["hp"]),
			"atk":   int(base["atk"])   + int(b["atk"]),
			"def":   int(base["def"])   + int(b["def"]),
			"magic": int(base["magic"]) + int(b["magic"]),
			"spd":   int(base["spd"]),
			"mp":    int(base["mp"])    + int(b.get("mp", 0)),
		})

	# 阶段2：小队光环按 scope 注入
	for i in range(n):
		var auras: Array = Backpack.grid_auras(loadouts[i]["grid"])
		if auras.is_empty():
			continue
		var pcell = cell_of.get(loadouts[i]["hero"], null)
		for aura in auras:
			var scope: String = aura.get("scope", "team")
			for j in range(n):
				if not _aura_hits(scope, i, j, pcell, cell_of.get(loadouts[j]["hero"], null)):
					continue
				for k in ["atk", "def", "hp", "magic", "spd", "mp"]:
					if aura.has(k):
						stats[j][k] += int(aura[k])
	return stats


static func build_party(loadouts: Array, squad_slots: Dictionary, full_heal: bool) -> Party:
	var n: int = loadouts.size()
	var stats: Array = squad_stats(loadouts, squad_slots)   # 自身+光环，与面板一致

	# ── 应用到英雄 + HP%保留 + 技能/冷却/副属性 ──
	var heroes: Array = []
	var cd_map: Dictionary = {}
	var extra_map: Dictionary = {}
	for i in range(n):
		var hero = loadouts[i]["hero"]
		var st: Dictionary = stats[i]
		var b: Dictionary = Backpack.compute(loadouts[i]["grid"])   # 自身（技能书/副属性用）

		var old_max: int = hero.get_max_hp()
		var old_cur: int = hero.current_hp
		var hp_pct: float = (float(old_cur) / float(old_max)) if old_max > 0 else 1.0
		hero.set("base_max_hp", st["hp"])
		hero.set("base_attack", st["atk"])
		hero.set("base_defense", st["def"])
		hero.set("base_magic", st["magic"])
		hero.set("base_speed", st["spd"])
		hero.set("base_mp", st["mp"])
		hero.stat_block.rebuild()

		# HP：满血 或 保留百分比（满血加血上限仍满血；摘装按比例缩；阵亡不复活）
		var new_max: int = hero.get_max_hp()
		if full_heal:
			hero.current_hp = new_max
		elif old_cur <= 0:
			hero.current_hp = 0
		else:
			hero.current_hp = clampi(int(round(hp_pct * new_max)), 1, new_max)

		# 技能来自背包技能书（按职业过滤），冷却随书带入
		var sk = hero.get("skills")
		if sk != null:
			sk.clear()
		var cfg: Dictionary = {}
		var ck: String = class_key(hero.hero_class)
		for book in b["books"]:
			var sid: String = book["id"]
			if SkillTable.get_skill(sid).get("hero_class", "") == ck:
				if sk != null and not (sid in sk):
					sk.append(sid)
				if int(book["cd"]) > 0:
					cfg[sid] = int(book["cd"])
		cd_map[hero] = cfg
		extra_map[hero] = b["extra"]
		heroes.append(hero)

	var party: Party = Party.create(heroes, null, 0.4)
	party.positioning_mode = "soft_row"
	# 站位：来自 squad_slots（只认前/后排，列不计入战斗）
	for cell in squad_slots:
		var ph = squad_slots[cell]
		if ph != null:
			party.set_row(ph, "front" if cell.y == 0 else "back")
	# 冷却 + 副属性注入
	for hero in cd_map:
		party.set_skill_cd(hero, cd_map[hero])
	for hero in extra_map:
		party.set_extra_stats(hero, extra_map[hero])

	return party


## 光环命中判定：scope 下，提供者 i 的光环是否作用到受益者 j。
## 统一规则：**只要受益者落在范围内就生效，含持有者本人**（带旗的人自己也吃）。
##   team      = 全队
##   adjacent  = 自己 + 正交相邻格
##   same_row  = 跟提供者同排（含自己）
##   front_row = 前排(row0)全体（绝对，含自己若在前排）
##   back_row  = 后排(row1)全体（绝对，含自己若在后排）
static func _aura_hits(scope: String, i: int, j: int, pcell, rcell) -> bool:
	match scope:
		"team":
			return true
		"adjacent":
			if i == j:
				return true                       # 含自己
			if pcell == null or rcell == null:
				return false
			return abs(pcell.x - rcell.x) + abs(pcell.y - rcell.y) == 1
		"same_row":
			if pcell == null or rcell == null:
				return false
			return pcell.y == rcell.y             # 同排，含自己
		"front_row":
			return rcell != null and rcell.y == 0
		"back_row":
			return rcell != null and rcell.y == 1
	return false


## Hero.HeroClass 枚举 → SkillTable.hero_class 字符串（技能书职业匹配用）
static func class_key(cls: int) -> String:
	match cls:
		Hero.HeroClass.WARRIOR: return "warrior"
		Hero.HeroClass.MAGE:    return "mage"
		Hero.HeroClass.PRIEST:  return "priest"
		Hero.HeroClass.ROGUE:   return "rogue"
		Hero.HeroClass.ARCHER:  return "archer"
	return ""
