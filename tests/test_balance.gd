extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_balance — 跑局平衡 harness（Step 5）
#
# 模拟"好 build vs 烂 build"跑完整条线（HP 跨节点累积、泉水回血、build_party 钳血），
# 输出通关率。目标：中等难度——好 build 多数能通关、烂 build 多数过不去。
# 数值不达标就回 RunManager._build_map 拧敌人，再跑本测试。
# ─────────────────────────────────────────────────────────────────────────────

const Loadout = preload("res://scripts/systems/backpack/BackpackLoadout.gd")
const TRIALS := 20

# 平衡参考"难度阶梯"：固定的一条线（村庄→战→村→战→泉水→战→魔王），
# 与随机地图生成解耦——平衡应量的是"数值曲线"，不是随机路线。加/调关就改这里。
func _balance_nodes() -> Array:
	return [
		{ "type": "village", "name": "村庄", "enemies": [] },
		{ "type": "battle",  "name": "林间遭遇", "enemies": MonsterFactory.create_group(["wolf", "wolf"]) },
		{ "type": "village", "name": "村镇", "enemies": [] },
		{ "type": "battle",  "name": "剧毒巢穴", "enemies": MonsterFactory.create_group(["venom_bug", "stone_guard"]) },
		{ "type": "rest",    "name": "泉水", "enemies": [] },
		{ "type": "battle",  "name": "废墟伏击", "enemies": MonsterFactory.create_group(["bandit", "ranger"]) },
		{ "type": "boss",    "name": "魔王", "enemies": MonsterFactory.create_group(["demon_lord", "claw_minion"]) },
	]


# 好 build：协同相邻 + 放对人 + 带本职技能书
func _good_grids() -> Array:
	return [
		# 战士：开刃(剑+磨刀石) + 重装(盾+甲) + 斩击书
		{ Vector2i(0,0): "iron_sword", Vector2i(1,0): "whetstone", Vector2i(2,0): "book_slash",
		  Vector2i(0,1): "shield", Vector2i(1,1): "chainmail" },
		# 法师：共鸣(法杖+魔典) + 火球书
		{ Vector2i(0,0): "staff", Vector2i(1,0): "tome", Vector2i(2,0): "book_fireball" },
		# 牧师：生机(护符+红宝石) + 圣徽 + 治疗书
		{ Vector2i(0,0): "holy_symbol", Vector2i(2,0): "book_heal",
		  Vector2i(0,1): "amulet", Vector2i(1,1): "charm" },
	]

# 中庸 build：放对人、有装备有技能书，但没凑相邻协同（衡量"协同到底多关键"）
func _ok_grids() -> Array:
	return [
		{ Vector2i(0,0): "iron_sword", Vector2i(2,0): "chainmail", Vector2i(2,1): "book_slash" },
		{ Vector2i(0,0): "staff", Vector2i(2,0): "book_fireball" },
		{ Vector2i(0,0): "amulet", Vector2i(2,0): "book_heal" },
	]

# 真实"500 金开局"：招 3 人(360 金) + 剩 ~140 金只够 2~3 件普通货，无协同、火球书(稀有)买不起。
# 模拟一个"会买但很穷"的开局：战士铁剑+斩击书、牧师治疗书、法师裸上(靠魔法普攻)。
func _opening_grids() -> Array:
	return [
		{ Vector2i(0,0): "iron_sword", Vector2i(1,0): "book_slash" },  # 战士：攻+6 + 斩击(common×2=100)
		{},                                                            # 法师：开局买不起火球书 → 魔法普攻
		{ Vector2i(0,0): "book_heal" },                                # 牧师：治疗书(common 50)
	]

# 更穷的"裸开局"：招 3 人，没买到/买不起任何技能书 → 全员只会普攻（运气差/新手最可能的开局）。
func _opening_naked() -> Array:
	return [
		{ Vector2i(0,0): "iron_sword" },   # 战士：只有把剑(攻+6)
		{ Vector2i(0,0): "tome" },         # 法师：魔典(魔+4)，无火球书 → 魔法普攻
		{ Vector2i(0,0): "amulet" },       # 牧师：护符(血+12)，无治疗书 → 普攻
	]

# 烂 build：放错人、无协同、无对职业技能书
func _bad_grids() -> Array:
	return [
		{ Vector2i(0,0): "staff" },        # 战士拿法杖（魔力对物理战士没用）
		{ Vector2i(0,0): "iron_sword" },   # 法师拿剑（攻击对法系没用）
		{ Vector2i(0,0): "shield" },       # 牧师只有个盾
	]


# 组一支测试队（战/法/牧）并装上 build，返回 loadouts + 站位
func _team(grids: Array) -> Dictionary:
	var ids := ["warrior", "mage", "priest"]
	var loadouts: Array = []
	for i in range(ids.size()):
		var e: Dictionary = RunManager.make_hero_entry(ids[i])
		e["grid"] = grids[i].duplicate()
		loadouts.append(e)
	var slots := {
		Vector2i(0, 0): loadouts[0]["hero"],
		Vector2i(0, 1): loadouts[1]["hero"],
		Vector2i(1, 1): loadouts[2]["hero"],
	}
	return { "loadouts": loadouts, "slots": slots }

# 单关满血胜率：每次新队满血单独打这关 N 次（隔离每关难度，不含跨关消耗）
func _node_winrate(grids: Array, enemies: Array) -> int:
	var wins := 0
	for t in range(TRIALS):
		var tm: Dictionary = _team(grids)
		var party: Party = Loadout.build_party(tm["loadouts"], tm["slots"], true)
		if BattleSimulator.simulate(party, enemies).party_won:
			wins += 1
	return wins

# ── 逐关体检表（用法 A：模拟当尺子，给每关标难易）────────────────────────────
func test_per_node_health_report() -> void:
	RunManager.start_run()
	gut.p("===== 逐关体检（每关满血单独打 %d 次）=====" % TRIALS)
	gut.p("关卡            好build  中庸  500金开局(会买)  裸开局(无技能书)")
	for node in _balance_nodes():
		var enemies: Array = node.get("enemies", [])
		if enemies.is_empty():
			continue
		var g := _node_winrate(_good_grids(), enemies)
		var o := _node_winrate(_ok_grids(), enemies)
		var op := _node_winrate(_opening_grids(), enemies)
		var nk := _node_winrate(_opening_naked(), enemies)
		gut.p("%-12s   %d/%d   %d/%d   %d/%d   %d/%d" % [node.get("name", "?"), g, TRIALS, o, TRIALS, op, TRIALS, nk, TRIALS])
	# 阵亡分布：整局中庸 build 在哪一关倒下（消耗战难度真正的落点）
	gut.p("--- 中庸 build 整局阵亡分布（%d 局）---" % TRIALS)
	var dist: Dictionary = {}
	for t in range(TRIALS):
		var where := _run_track(_ok_grids())
		dist[where] = int(dist.get(where, 0)) + 1
	for k in dist:
		gut.p("  %-12s ×%d" % [k, dist[k]])
	assert_true(true, "体检报告（看 gut.p 输出）")

# 跑一整局，返回在哪一关失败（节点名），通关则返回"通关"
func _run_track(grids: Array) -> String:
	RunManager.start_run()
	var tm: Dictionary = _team(grids)
	RunManager.roster = tm["loadouts"]
	RunManager.party = RunManager.roster.map(func(e): return e["hero"])
	RunManager.squad_slots = tm["slots"]
	for node in _balance_nodes():
		match node.get("type"):
			"village":
				pass
			"rest":
				RunManager.rest_heal()
			_:
				var alive: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
				var party: Party = Loadout.build_party(alive, RunManager.squad_slots, false)
				if not BattleSimulator.simulate(party, node.get("enemies", [])).party_won:
					return String(node.get("name", "?"))
	return "通关"


# 跑一整局，返回是否通关（魔王也打过）
func _run_once(grids: Array) -> bool:
	RunManager.start_run()
	# 起手空队 → 直接组一支固定测试队（战/法/牧）并装上 build
	RunManager.roster = [
		RunManager.make_hero_entry("warrior"),
		RunManager.make_hero_entry("mage"),
		RunManager.make_hero_entry("priest"),
	]
	RunManager.party = RunManager.roster.map(func(e): return e["hero"])
	RunManager.squad_slots = {
		Vector2i(0, 0): RunManager.roster[0]["hero"],
		Vector2i(0, 1): RunManager.roster[1]["hero"],
		Vector2i(1, 1): RunManager.roster[2]["hero"],
	}
	for i in range(grids.size()):
		RunManager.roster[i]["grid"] = grids[i].duplicate()
	for node in _balance_nodes():
		match node.get("type"):
			"village":
				pass
			"rest":
				RunManager.rest_heal()
			_:
				var alive: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
				if alive.is_empty():
					return false
				var party: Party = Loadout.build_party(alive, RunManager.squad_slots, false)
				var result: BattleResult = BattleSimulator.simulate(party, node.get("enemies", []))
				if not result.party_won:
					return false
	return true


func _win_rate(grids: Array) -> int:
	var wins := 0
	for t in range(TRIALS):
		if _run_once(grids):
			wins += 1
	return wins


# 任意人数/配置的队伍打一组敌人的满血胜率（第一个英雄前排，其余后排）。
func _winrate_custom(hero_ids: Array, grids: Array, enemies: Array) -> int:
	var wins := 0
	for t in range(TRIALS):
		var loadouts: Array = []
		for i in range(hero_ids.size()):
			var e: Dictionary = RunManager.make_hero_entry(hero_ids[i])
			e["grid"] = grids[i].duplicate()
			loadouts.append(e)
		var slots: Dictionary = { Vector2i(0, 0): loadouts[0]["hero"] }
		for i in range(1, loadouts.size()):
			slots[Vector2i(i - 1, 1)] = loadouts[i]["hero"]
		var party: Party = Loadout.build_party(loadouts, slots, true)
		if BattleSimulator.simulate(party, enemies).party_won:
			wins += 1
	return wins

# 第一关(林间遭遇 野狼×2)对"招几个人"的开局：找出能过第一关的最少人数
func test_first_node_by_party_size() -> void:
	var wolves: Array = MonsterFactory.create_group(["wolf", "wolf"])
	var w1 := _winrate_custom(["warrior"], [{Vector2i(0,0):"iron_sword"}], wolves)
	var w2 := _winrate_custom(["warrior", "priest"], [{Vector2i(0,0):"iron_sword"}, {Vector2i(0,0):"amulet"}], wolves)
	var w3 := _winrate_custom(["warrior", "mage", "priest"],
		[{Vector2i(0,0):"iron_sword"}, {Vector2i(0,0):"tome"}, {Vector2i(0,0):"amulet"}], wolves)
	gut.p("第一关(野狼×2)裸队胜率：1人 %d/%d · 2人 %d/%d · 3人 %d/%d" % [w1, TRIALS, w2, TRIALS, w3, TRIALS])
	assert_true(true, "看 gut.p：第一关对小队人数的门槛")


func test_good_build_beats_bad_build() -> void:
	var good := _win_rate(_good_grids())
	var ok := _win_rate(_ok_grids())
	var bad := _win_rate(_bad_grids())
	gut.p("通关率  好build %d/%d  ·  中庸 %d/%d  ·  烂build %d/%d" % [good, TRIALS, ok, TRIALS, bad, TRIALS])
	# 目标区间(中等)：好 build 稳赢、中庸有真实风险(~50%)、烂 build 必败。
	# 这几条断言锁住区间——以后若英雄被买强/敌人变弱使"中庸稳通关"，会立刻红。
	assert_gt(good, bad, "好 build 通关率应明显高于烂 build")
	assert_gte(good, int(TRIALS * 0.7), "好 build 多数能通关（稳赢，留采样冗余）")
	assert_lt(ok, good, "中庸 build 应弱于好 build（相邻协同有价值）")
	assert_lte(ok, int(TRIALS * 0.75), "中庸 build 不应稳通关 —— 要有真实风险（锁住'确定性买强'漂移）")
	assert_lte(bad, int(TRIALS * 0.2), "烂 build 应基本必败（build 要有意义）")
